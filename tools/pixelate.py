# -*- coding: utf-8 -*-
"""絵のドットを粗くする（解像度を下げる）。ピクセルアート風にするため。

    python tools/pixelate.py <入力.png> <出力.png> [倍率] [--nearest]

倍率 4 なら 512px の絵が 128px になる。貼る大きさ（pattern_size）は変えないので、
**絵の1ドットが4倍の大きさで出る**。柄の大きさや繰り返しの間隔は変わらない。

  - 既定は平均（BOX）。4x4 の色を混ぜて1ドットにする。素直でムラが少ない
  - --nearest は左上の1点をそのまま取る。元の色だけが残り、粒立ちが強く出る

整数倍で縮めるので、継ぎ目の無い絵は縮めても継ぎ目が出ない
（tools/make_seamless.py のあとに通すこと）。

貼る側（TerrainSprite）のフィルタは Nearest なので、画面では四角いドットになる。
"""
import sys

from PIL import Image


def pixelate(src_path, out_path, factor=4, nearest=False):
    img = Image.open(src_path)
    w, h = img.size
    if w % factor or h % factor:
        print("  NG  %dx%d は %d で割り切れない" % (w, h, factor))
        return None
    small = img.resize((w // factor, h // factor),
                       Image.NEAREST if nearest else Image.BOX)
    small.save(out_path)
    print("--- %s -> %s  %dx%d -> %dx%d（%s）"
          % (src_path, out_path, w, h, small.size[0], small.size[1],
             "最近傍" if nearest else "平均"))
    return small


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    factor = int(args[2]) if len(args) > 2 else 4
    pixelate(args[0], args[1], factor, "--nearest" in sys.argv)


if __name__ == "__main__":
    main()
