# -*- coding: utf-8 -*-
"""マトリックス雨シェーダー用の文字アトラスを作る。

    python tools/make_glyph_atlas.py

16 x 6 = 96 文字を 96px の枡に並べ、resources/texture/matrix_glyphs.png に書く。
文字は白、形は透明度(アルファ)で持つ。シェーダーはアルファだけを見る。

文字を変えるときは GLYPHS を書き換えて実行し直す。
書いたあと Godot に取り込み直すところまでやる（これをやらないと、
ゲームは前の画像のまま動く）。
数を変えるなら matrix_rain.gdshader の atlas_grid と glyph_count も合わせること。

フォントは Noto Sans JP（OFL、配布可）。Windows 同梱の MS ゴシックなどは
ゲームに同梱できないので使わない。
"""
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

COLS, ROWS = 16, 6
CELL = 96
FONT_SIZE = 90          # 枡(96px)いっぱいまで。余白は下の MARGIN ぶんだけ残す
## 枡の縁に残す透明の余白 (px)。0 にすると隣の枡の字がにじんで出る
MARGIN = 2
OUT = os.path.join("resources", "texture", "matrix_glyphs.png")

# 取り込み直しに使う Godot。上から順に探す
GODOT_CANDIDATES = [
    os.environ.get("GODOT", ""),
    r"D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
]

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\NotoSansJP-VF.ttf",
    os.path.join("resources", "font", "NotoSansJP-Subset.ttf"),
]

KATAKANA = "アイウエオカキクケコサシスセソタチツテトナＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹ"
DIGITS = "0123456789"
KANJI = "酒酔杯醸吟蔵麦泡樽酵食飯肉魚麺鍋焼煮味餅苺桃梨柿栗橘梅杏李柚遊戯歌舞笑踊祭賭旅泳"
GLYPHS = KATAKANA + DIGITS + KANJI


def load_font() -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if not os.path.exists(path):
            continue
        font = ImageFont.truetype(path, FONT_SIZE)
        try:                      # 可変フォントなら太めの字面にする
            font.set_variation_by_name("Bold")
        except Exception:
            pass
        print("font: %s" % path)
        return font
    raise SystemExit("NG  使えるフォントが無い: %s" % ", ".join(FONT_CANDIDATES))


def find_godot() -> str:
    for path in GODOT_CANDIDATES:
        if path and os.path.exists(path):
            return path
    return shutil.which("godot") or ""


## .png を置いただけでは Godot は古い取り込み結果を使い続ける。
## .godot/imported/*.ctex を作り直させて、はじめてゲームに出る
def reimport() -> None:
    godot = find_godot()
    if not godot:
        print("--  Godot が見つからないので取り込みは手元でお願いします:")
        print("    godot --headless --path . --import")
        return
    print("取り込み直し中 … %s" % godot)
    r = subprocess.run([godot, "--headless", "--path", ".", "--import"],
                       capture_output=True, text=True)
    if r.returncode == 0:
        print("取り込み直した（ゲームを起動し直せば新しい字が出る）")
    else:
        print("NG  取り込みに失敗（終了コード %d）" % r.returncode)
        print(r.stdout[-800:])


def main() -> int:
    if len(GLYPHS) != COLS * ROWS:
        raise SystemExit("NG  文字数が %d（%d のはず）" % (len(GLYPHS), COLS * ROWS))

    font = load_font()
    atlas = Image.new("RGBA", (COLS * CELL, ROWS * CELL), (255, 255, 255, 0))
    missing = []
    tight = []

    for i, ch in enumerate(GLYPHS):
        mask = Image.new("L", (CELL, CELL), 0)
        draw = ImageDraw.Draw(mask)
        box = draw.textbbox((0, 0), ch, font=font)
        w, h = box[2] - box[0], box[3] - box[1]
        draw.text(((CELL - w) * 0.5 - box[0], (CELL - h) * 0.5 - box[1]),
                  ch, font=font, fill=255)
        ink = mask.getbbox()
        if not ink:
            missing.append(ch)
        elif (ink[0] < MARGIN or ink[1] < MARGIN
                or ink[2] > CELL - MARGIN or ink[3] > CELL - MARGIN):
            tight.append(ch)
        cell = Image.new("RGBA", (CELL, CELL), (255, 255, 255, 0))
        cell.putalpha(mask)
        atlas.paste(cell, ((i % COLS) * CELL, (i // COLS) * CELL))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    atlas.save(OUT)
    print("%d 文字 -> %s (%dx%d)" % (len(GLYPHS), OUT, atlas.width, atlas.height))
    if missing:
        print("NG  フォントに無い文字: %s" % "".join(missing))
        return 1
    if tight:
        print("NG  枡からはみ出しそうな文字: %s （FONT_SIZE を下げる）"
              % "".join(tight))
        return 1
    reimport()
    return 0


if __name__ == "__main__":
    sys.exit(main())
