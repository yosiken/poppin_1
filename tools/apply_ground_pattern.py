# -*- coding: utf-8 -*-
"""本編ステージの地面を「模様」で塗る。

    python tools/apply_ground_pattern.py [--all] [--stripe] [Stage01 Stage02 ...]

ステージ名を書かなければ本編10面すべて。地面らしい名前のノード
（Ground / Ramp / Platform / Floor / Slope / Block）だけに貼り、壁や天井は
そのままにする。--all を付けると Graphics の下の Gfx_* 全部に貼る。
--stripe を付けると、枠線の見た目を resources/terrain_look_default.tres に預ける。
色・太さ・縞の長さは、その .tres をエディタで開いて直す（全ブロックに効く）。何度流しても結果は同じ（貼り直すだけ）。

やっていること（Graphics の下の Gfx_* ノード1つにつき）:

1. terrain_sprite.gd の ground_pattern に resources/ground_pattern_grass.tres を
   割り当てる（エディタでその欄へドラッグするのと同じ）。
   前の版で書いていた pattern_enabled / pattern_size の行は消す
2. そのノードが持つ ShaderMaterial を terrain_pattern.gdshader に替える

模様の絵・大きさ・パララックスの強さは .tres 側で直す（貼った全ブロックに効く）。

模様は Polygon2D の UV ではなくワールド座標で敷くので、ブロックの拡大率や
地形をどこで分割したかに関係なく、隣のブロックと柄が繋がる。
カメラに合わせたパララックスは terrain_sprite.gd が実行時に入れる。

元に戻すには、ノードの ground_pattern を空にする（シェーダーは起動時に
terrain_fill へ戻る）。ノードのテクスチャは書き換えないので、元の絵に戻る。
"""
import io
import os
import re
import sys

# 地面とみなすノード名（Gfx_ のあとの頭）。壁や天井は別の絵のままにしておきたい
# ことが多いので、既定では外してある。--all で全部の Gfx_ に貼る
GROUND_PREFIXES = ("Ground", "Ramp", "Platform", "Floor", "Slope", "Block")
# 模様の .tres（GroundPattern）。絵・大きさ・パララックスはこちらが持つ
PATTERN_RES = "res://resources/ground_pattern_grass.tres"
PATTERN_RES_ID = "pattern_grass"
SHADER = "res://resources/shader/terrain_pattern.gdshader"
# 枠線の見た目（色・太さ・縞）をまとめた .tres。--stripe で割り当てる
LOOK = "res://resources/terrain_look_default.tres"
LOOK_ID = "look_default"
SH_ID = "sh_pattern"
DEFAULT_STAGES = ["Stage%02d" % i for i in range(1, 11)]


## .import / .uid から uid を拾う。無ければ空（Godot が初回読み込みで振る）
def uid_of(res_path):
    rel = res_path.replace("res://", "")
    imp = rel + ".import"
    if os.path.exists(imp):
        m = re.search(r'(?m)^uid="([^"]+)"', io.open(imp, encoding="utf-8").read())
        if m:
            return ' uid="%s"' % m.group(1)
    if os.path.exists(rel + ".uid"):
        return ' uid="%s"' % io.open(rel + ".uid", encoding="utf-8").read().strip()
    if rel.endswith(".tres") and os.path.exists(rel):
        # .tres は1行目の見出しに uid が入っている
        m = re.search(r'uid="([^"]+)"', io.open(rel, encoding="utf-8").readline())
        if m:
            return ' uid="%s"' % m.group(1)
    return ""


## ext_resource を1行足す（すでにあれば何もしない）
def ensure_ext(src, kind, path, ext_id):
    if 'id="%s"' % ext_id in src:
        return src
    line = '[ext_resource type="%s"%s path="%s" id="%s"]\n' % (
        kind, uid_of(path), path, ext_id)
    last = list(re.finditer(r"(?m)^\[ext_resource .*\]\n", src))[-1]
    return src[:last.end()] + line + src[last.end():]


## ノード（または sub_resource）のブロックに1行を書く。
## 同じ名前の行があれば差し替え、無ければ after で指定した行の後ろに足す
def set_line(block, key, value, after=None):
    line = "%s = %s" % (key, value)
    pat = re.compile(r"(?m)^%s = .*$" % re.escape(key))
    if pat.search(block):
        return pat.sub(line, block, count=1)
    lines = block.rstrip("\n").split("\n")
    at = len(lines)
    if after:
        for i, l in enumerate(lines):
            if l.startswith(after + " ="):
                at = i + 1
                break
    lines.insert(at, line)
    return "\n".join(lines) + "\n\n"


def is_ground(name):
    """Gfx_ を外した名前が地面らしいか"""
    base = name[4:]
    return any(base.startswith(p) for p in GROUND_PREFIXES)


def apply(path, every=False, stripe=False):
    src = io.open(path, encoding="utf-8").read()
    src = ensure_ext(src, "Resource", PATTERN_RES, PATTERN_RES_ID)
    src = ensure_ext(src, "Shader", SHADER, SH_ID)
    if stripe:
        src = ensure_ext(src, "Resource", LOOK, LOOK_ID)

    blocks = re.split(r"(?m)^(?=\[)", src)
    mat_ids = []
    changed = 0

    for bi, block in enumerate(blocks):
        head = re.match(r'\[node name="(Gfx_[^"]+)" type="Polygon2D" parent="([^"]+)"', block)
        if head is None:
            continue
        if not every and not is_ground(head.group(1)):
            print("  --  %s は地面ではないので飛ばす（--all で貼る）" % head.group(1))
            continue
        if "script = ExtResource" not in block:
            print("  --  %s は terrain_sprite.gd を持っていないので飛ばす" % head.group(1))
            continue
        m = re.search(r'(?m)^material = SubResource\("([^"]+)"\)$', block)
        if m:
            mat_ids.append(m.group(1))
        # 前の版の書きかた（ノードに直接書いた模様の値）は消す。
        # 残っていても .tres が優先されるが、読んで紛らわしい
        block = re.sub(r"(?m)^(pattern_enabled|pattern_size|mirror_tiling) = .*\n", "", block)
        # script より後ろに置く。前に置くと読み込み時に捨てられる
        block = set_line(block, "ground_pattern", 'ExtResource("%s")' % PATTERN_RES_ID,
                         after="script")
        if stripe:
            # 枠線の見た目を .tres に預ける。色も太さも縞の長さも、
            # その1枚を直せば貼ったブロック全部に効く
            block = set_line(block, "outline_look", 'ExtResource("%s")' % LOOK_ID,
                             after="ground_pattern")
        blocks[bi] = block
        changed += 1

    # マテリアルの側もシェーダーを入れ替える。入れ替えなくても
    # terrain_sprite.gd が起動時に直すが、.tscn を読んで分かるようにしておく
    for bi, block in enumerate(blocks):
        m = re.match(r'\[sub_resource type="ShaderMaterial" id="([^"]+)"\]', block)
        if m is None or m.group(1) not in mat_ids:
            continue
        block = set_line(block, "shader", 'ExtResource("%s")' % SH_ID)
        blocks[bi] = block

    io.open(path, "w", encoding="utf-8", newline="\n").write("".join(blocks))
    print("  ok  %s: 地面 %d 枚を模様にした" % (os.path.basename(path), changed))


def main():
    args = sys.argv[1:]
    every = "--all" in args
    stripe = "--stripe" in args
    names = [a for a in args if not a.startswith("--")] or DEFAULT_STAGES
    for name in names:
        p = os.path.join("scenes", "stages", "%s.tscn" % name)
        print("--- %s" % name)
        if not os.path.exists(p):
            print("  NG  %s が無い" % p)
            continue
        apply(p, every, stripe)


if __name__ == "__main__":
    main()
