# -*- coding: utf-8 -*-
"""模様の絵を、並べても継ぎ目が出ない形に直す。

    python tools/make_seamless.py <入力.png> <出力.png> [帯の幅]

やりかた:

1. 絵をずらして、四辺に来る継ぎ目を選び直す。
   どこで切るかは絵まかせにせず、**縦横それぞれ一番繋がっている場所**を探して
   そこが端に来るようにずらす（真ん中あたりから選ぶ）。
   もとの四辺は内側へ回り、真ん中にあった柄は四隅へ回って、タイルをまたいで
   繋がる形になる

2. 内側へ回ったもとの四辺を、絵の別の場所から持ってきた帯で覆う。
   帯の真ん中ほど持ってきた絵、端へ行くほど元の絵にする。混ぜるのではなく
   画素ごとにどちらかを選ぶので、ドット絵がぼやけない。選びかたはなだらかな
   乱数（まだら模様）なので、境目がまっすぐな線にならず、草のむらに紛れる。
   鏡で折り返すやりかたは試したが、左右対称の柄が出て継ぎ目より目立った

混ぜない理由: このプロジェクトは既定のテクスチャフィルタが Nearest。
半透明で重ねてぼかすと、地面だけ眠い絵になってしまう。

直したあとは mirror_tiling（1マスごとに絵を反転）を切ってよい。
反転が要らなくなるので、左右対称の模様が出なくなる。
"""
import sys

import numpy as np
from PIL import Image

BAND = 72          # 継ぎ目を覆う帯の幅 (px)
CELL = 12          # まだら模様の粗さ (px)。大きいほど大きな塊で入れ替わる
SEED = 20261123    # 乱数。同じ絵からは毎回同じ結果を出す


def col_diffs(a):
    """隣り合う列どうしの差。i 番目は 列i と 列i+1 のあいだ"""
    f = a[:, :, :3].astype(np.float32)
    return np.abs(f[:, 1:] - f[:, :-1]).mean(axis=(0, 2))


def wrap_diff(a, axis):
    """端と端（巻いたときに隣り合うところ）の差"""
    f = a[:, :, :3].astype(np.float32)
    return (np.abs(f[:, 0] - f[:, -1]).mean() if axis == 1
            else np.abs(f[0, :] - f[-1, :]).mean())


def best_cut(d):
    """一番繋がっている切れ目を、真ん中あたりから選ぶ。
    端の近くで切ると、もとの四辺が内側へ回らず、直す意味が無くなる"""
    n = len(d)
    lo, hi = n // 4, n * 3 // 4
    return lo + int(np.argmin(d[lo:hi]))


def soft_noise(h, w, cell, rng):
    """なだらかな乱数の面 [0,1)。細かい点々ではなく、まだら模様になる。

    画素ごとにバラバラに選ぶ（白色雑音）と、帯の中が砂嵐のように荒れる。
    まだらにすると、ひとかたまりぶんは元の絵がそのまま残るので、
    草の粒立ちが保たれる"""
    small = rng.random((max(2, h // cell), max(2, w // cell)))
    # 端が反対の端と繋がるようにしてから伸ばす。こうしないと、帯が絵の端まで
    # 届いているとき、左端と右端（上端と下端）で別の側が選ばれて継ぎ目になる
    small = np.concatenate([small, small[:1, :]], axis=0)
    small = np.concatenate([small, small[:, :1]], axis=1)
    img = Image.fromarray((small * 255.0).astype(np.uint8), "L").resize((w, h), Image.BILINEAR)
    return np.asarray(img, dtype=np.float32) / 255.0


def mend_columns(a, x0, half, rng, cell):
    """x0 のところの縦の継ぎ目を、絵の別の場所から持ってきた帯で覆う。

    鏡で折り返すやりかた（左右から畳む）は、帯の端がぴったり合う代わりに
    左右対称の柄が出る。草のような絵だと蝶の羽のような形が目について、
    継ぎ目より悪くなる。ここでは**ずらして持ってくる**ので対称にならない。

    帯の真ん中ほど持ってきた絵、端へ行くほど元の絵。混ぜるのではなく
    画素ごとにどちらかを選び、選びかたはなだらかな乱数（まだら模様）にする。
    境目がまっすぐな線にならず、草のむらに紛れる"""
    h, w = a.shape[0], a.shape[1]
    lo, hi = x0 - half, x0 + half
    xs = np.arange(lo, hi)
    # 持ってくる場所。半分ずらしたあたりから、さらに少しばらす
    dx = w // 2 + int(rng.integers(-w // 8, w // 8))
    dy = int(rng.integers(0, h))
    patch = np.roll(a[:, (xs + dx) % w], dy, axis=0)
    # 帯の真ん中で 1、両端で 0
    t = 1.0 - np.abs(2.0 * (xs - lo) / float(hi - lo) - 1.0)
    take = soft_noise(h, hi - lo, cell, rng) < t[None, :]
    a[:, lo:hi] = np.where(take[..., None], patch, a[:, lo:hi])
    return a


def mend_seam_columns(a, x0, half, rng, cell, label, only_if_sharp=False):
    """もとの四辺だった線を1本だけ消す。

    「一番くっきりした線」を探して片っ端から消す作りにはしない。
    この絵は市松模様の土が入っていて、その境目も同じくらいくっきり出る。
    探して消すと、継ぎ目ではなく絵そのものを削ってしまう"""
    d = col_diffs(a)
    now = d[min(max(x0 - 1, 0), len(d) - 1)]
    if only_if_sharp and now < d.mean() * CENTER_SHARP:
        print("  ..  %s x=%d は継ぎ目として出ていない（%.1f / 平均 %.1f）。触らない"
              % (label, x0, now, d.mean()))
        return a
    print("  ..  %s x=%d を消す（%.1f / 平均 %.1f）" % (label, x0, now, d.mean()))
    return mend_columns(a, x0, half, rng, cell)


## 貼り合わせて作られた絵は、真ん中に線が入っていることがある
## （この草の絵は 256px のところに入っていた）。平均よりはっきり出ていたら、
## もとの四辺と同じように消す。探し回らず真ん中だけ見るのは、市松模様の土の
## 境目も同じくらいくっきり出るので、探すと絵そのものを削ってしまうため
CENTER_SHARP = 1.5


def center_seam(a, axis):
    """真ん中の線が継ぎ目なら、その位置（0 から数えた列/行）を返す。無ければ -1"""
    d = col_diffs(a if axis == 1 else np.swapaxes(a, 0, 1))
    n = len(d) + 1
    i = n // 2 - 1
    return n // 2 if d[i] > d.mean() * CENTER_SHARP else -1


def _inside(x, n, half):
    """帯が絵からはみ出さないところへ寄せる"""
    return int(min(max(x, half), n - half))


def make_seamless(src_path, out_path, band=BAND):
    img = Image.open(src_path).convert("RGBA")
    a = np.asarray(img).astype(np.uint8).copy()
    h, w = a.shape[0], a.shape[1]
    half = max(2, min(band, min(w, h) // 3) // 2)
    rng = np.random.default_rng(SEED)

    print("--- %s -> %s （帯 %d px）" % (src_path, out_path, half * 2))
    report(a, "もと  ")

    # 1. 一番繋がっている切れ目が端に来るようにずらす
    cx, cy = center_seam(a, 1), center_seam(a, 0)
    px = best_cut(col_diffs(a))
    py = best_cut(col_diffs(np.swapaxes(a, 0, 1)))
    print("  ..  切れ目を x=%d / y=%d に選んでずらす" % (px + 1, py + 1))
    shift_x, shift_y = w - 1 - px, h - 1 - py
    a = np.roll(a, (shift_y, shift_x), axis=(0, 1))

    # 2. 内側に残った継ぎ目（もとの四辺と、絵がもともと持っていた線）を消す
    # もとの四辺は、ずらしたぶんだけ内側へ回っている。そこを狙って消す
    a = mend_seam_columns(a, _inside(shift_x, w, half), half, rng, CELL, "縦")
    a = np.swapaxes(a, 0, 1)
    a = mend_seam_columns(a, _inside(shift_y, h, half), half, rng, CELL, "横")
    a = np.swapaxes(a, 0, 1)

    # 絵がもともと真ん中に持っていた線も、同じように消す
    if cx >= 0:
        a = mend_seam_columns(a, _inside((cx + shift_x) % w, w, half), half, rng,
                              CELL, "縦（もとからの線）", True)
    if cy >= 0:
        a = np.swapaxes(a, 0, 1)
        a = mend_seam_columns(a, _inside((cy + shift_y) % h, h, half), half, rng,
                              CELL, "横（もとからの線）", True)
        a = np.swapaxes(a, 0, 1)

    out = Image.fromarray(a, "RGBA")
    out.save(out_path)
    report(a, "直した")
    return out


def report(a, label):
    d = col_diffs(a)
    dr = col_diffs(np.swapaxes(a, 0, 1))
    print("  %s 端どうし 横 %.1f / 縦 %.1f ｜ 隣り合う画素 横 %.1f / 縦 %.1f ｜"
          " 一番くっきりした線 x=%d (%.1f) y=%d (%.1f)"
          % (label, wrap_diff(a, 1), wrap_diff(a, 0), d.mean(), dr.mean(),
             int(np.argmax(d)) + 1, d.max(), int(np.argmax(dr)) + 1, dr.max()))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return
    band = int(sys.argv[3]) if len(sys.argv) > 3 else BAND
    make_seamless(sys.argv[1], sys.argv[2], band)


if __name__ == "__main__":
    main()
