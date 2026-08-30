"""Aseprite (.aseprite / .ase) を PNG へ変換する。

Aseprite 本体がインストールされていない環境向け。フォーマットを直接読んで、
可視レイヤーを通常合成で重ね、フレーム0を PNG として書き出す。

使い方（リポジトリのルートで）:

    python tools/aseprite_to_png.py resources/texture/kanie.aseprite
    python tools/aseprite_to_png.py resources/texture/*.aseprite

出力は入力と同じ場所に .png として保存される。

対応範囲:
  - 32bpp RGBA のみ（8bpp インデックス / 16bpp グレースケールは非対応）
  - 通常（Normal）ブレンドのみ。他のブレンドモードは警告して通常扱いにする
  - フレーム0のみ。アニメーションは扱わない
"""

import struct
import sys
import zlib
from pathlib import Path

CHUNK_LAYER = 0x2004
CHUNK_CEL = 0x2005

LAYER_FLAG_VISIBLE = 1
LAYER_TYPE_GROUP = 1
BLEND_NORMAL = 0


def parse(path):
    data = path.read_bytes()
    _size, magic, frames, width, height, depth = struct.unpack_from("<IHHHHH", data, 0)
    if magic != 0xA5E0:
        raise ValueError("Aseprite ファイルではありません: %s" % path)
    if depth != 32:
        raise ValueError("32bpp RGBA のみ対応しています (このファイルは %dbpp): %s" % (depth, path))

    layers = []
    cels = []
    pos = 128
    for frame_index in range(frames):
        frame_size, frame_magic, old_chunks, _duration = struct.unpack_from("<IHHH", data, pos)
        new_chunks = struct.unpack_from("<I", data, pos + 12)[0]
        if frame_magic != 0xF1FA:
            raise ValueError("フレームヘッダが壊れています")
        count = new_chunks if new_chunks != 0 else old_chunks
        cursor = pos + 16
        for _ in range(count):
            chunk_size, chunk_type = struct.unpack_from("<IH", data, cursor)
            body = data[cursor + 6:cursor + chunk_size]
            if chunk_type == CHUNK_LAYER and frame_index == 0:
                layers.append(_parse_layer(body))
            elif chunk_type == CHUNK_CEL and frame_index == 0:
                cels.append(_parse_cel(body))
            cursor += chunk_size
        pos += frame_size
    return width, height, layers, cels


def _parse_layer(body):
    flags, layer_type, child_level = struct.unpack_from("<HHH", body, 0)
    blend, opacity = struct.unpack_from("<HB", body, 10)
    name_len = struct.unpack_from("<H", body, 16)[0]
    name = body[18:18 + name_len].decode("utf-8", "replace")
    return {
        "visible": bool(flags & LAYER_FLAG_VISIBLE),
        "type": layer_type,
        "child_level": child_level,
        "blend": blend,
        "opacity": opacity,
        "name": name,
    }


def _parse_cel(body):
    layer_index, x, y = struct.unpack_from("<Hhh", body, 0)
    opacity, cel_type = struct.unpack_from("<BH", body, 6)
    # cel_type の後ろは z_index(2) + 予約(5) の計7バイト
    head = 16
    if cel_type in (0, 2):
        w, h = struct.unpack_from("<HH", body, head)
        raw = body[head + 4:]
        pixels = zlib.decompress(raw) if cel_type == 2 else raw
    else:
        return None  # リンクセル / タイルマップは非対応
    return {"layer": layer_index, "x": x, "y": y, "opacity": opacity,
            "w": w, "h": h, "pixels": pixels}


def composite(width, height, layers, cels):
    """可視レイヤーを下から順に通常合成する。"""
    out = bytearray(width * height * 4)
    # 非表示グループの中身も隠す
    hidden_until = None
    effective = []
    for layer in layers:
        if hidden_until is not None:
            if layer["child_level"] > hidden_until:
                effective.append(False)
                continue
            hidden_until = None
        visible = layer["visible"]
        if not visible and layer["type"] == LAYER_TYPE_GROUP:
            hidden_until = layer["child_level"]
        effective.append(visible)

    warned = set()
    for cel in cels:
        if cel is None:
            continue
        layer = layers[cel["layer"]]
        if not effective[cel["layer"]]:
            continue
        if layer["blend"] != BLEND_NORMAL and layer["name"] not in warned:
            print("  警告: レイヤー '%s' は通常以外のブレンド(%d)です。通常として合成します"
                  % (layer["name"], layer["blend"]))
            warned.add(layer["name"])
        alpha_scale = (layer["opacity"] / 255.0) * (cel["opacity"] / 255.0)
        _blend_cel(out, width, height, cel, alpha_scale)
    return out


def _blend_cel(out, width, height, cel, alpha_scale):
    src = cel["pixels"]
    for row in range(cel["h"]):
        dst_y = cel["y"] + row
        if dst_y < 0 or dst_y >= height:
            continue
        for col in range(cel["w"]):
            dst_x = cel["x"] + col
            if dst_x < 0 or dst_x >= width:
                continue
            si = (row * cel["w"] + col) * 4
            sa = src[si + 3] * alpha_scale
            if sa <= 0.0:
                continue
            sa /= 255.0
            di = (dst_y * width + dst_x) * 4
            da = out[di + 3] / 255.0
            oa = sa + da * (1.0 - sa)
            if oa <= 0.0:
                continue
            for c in range(3):
                sc = src[si + c]
                dc = out[di + c]
                out[di + c] = int(round((sc * sa + dc * da * (1.0 - sa)) / oa))
            out[di + 3] = int(round(oa * 255.0))


def write_png(path, width, height, rgba):
    raw = b"".join(b"\x00" + bytes(rgba[y * width * 4:(y + 1) * width * 4])
                   for y in range(height))

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(raw, 9))
                     + chunk(b"IEND", b""))


def convert(path):
    width, height, layers, cels = parse(path)
    print("%s: %dx%d レイヤー%d セル%d"
          % (path.name, width, height, len(layers), len([c for c in cels if c])))
    rgba = composite(width, height, layers, cels)
    out = path.with_suffix(".png")
    write_png(out, width, height, rgba)
    opaque = sum(1 for i in range(3, len(rgba), 4) if rgba[i] > 0)
    print("  -> %s (不透明ピクセル %d / %d)" % (out.name, opaque, width * height))


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    for arg in argv:
        for path in sorted(Path().glob(arg)) or [Path(arg)]:
            convert(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
