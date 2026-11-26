# -*- coding: utf-8 -*-
"""タイトルロゴの PSD から、ゲームで重ねて動かす PNG を書き出す。

    python tools/export_title_logo.py

読むのは resources/title/title.psd のレイヤー
「枠（白フチ）」「枠（線）」「飾り」「液体」「文字」。
書き出すのは resources/title/logo/ の次の5枚（どれもキャンバスと同じ大きさで、
重ねる位置をそろえる必要がない）。

    logo_backing.png  いちばん後ろ。ロゴの形を茶色で塗っただけの下地
    logo_liquid.png   液体（ビール・泡・粒）
    logo_text.png     文字
    logo_deco.png     飾り（集中線・キラキラ・麦）
    logo_frame.png    いちばん前。白フチと茶色の線

タイトル画面では、液体・文字・飾りを少しずつずらして奥行きを出す。
色の層は枠の後ろにあるので、ずらしても枠の外にははみ出さない。
ずらして空いたところが見えないよう、色の層は枠の線の下へ少し塗り広げてある
（GROW px。ずらす量は title_logo.gd の max_shift をこれより小さく保つ）。
広げた先で白フチに近づきすぎないよう、白フチから KEEP_AWAY px 以内には広げない。
それでも空いたところは、後ろの茶色の下地が見えるだけで、線が太く見える程度で済む。

書き出すときだけ、絵の汚れを2つ掃除する（PSD はそのまま）。
  - 絵の中の小さな透明の穴（背景を抜いたときの残り）を、まわりの色で埋める。
    ゲームでは後ろの空が点々と透けて見えるため
  - いちばん外側の 1〜2 px の暗い縁（黒い背景から抜いたときの残り）を消す。
    縮めて表示すると、白フチの外に黒いギザギザが出るため
それ以外は、ずらさずに重ねた絵が PSD と1画素も違わない（最後に確かめる）。
"""
import os
import sys

import numpy as np
from PIL import Image
from psd_tools import PSDImage
from scipy import ndimage as ndi

PSD = os.path.join("resources", "title", "title.psd")
OUT = os.path.join("resources", "title", "logo")
GROW = 12
KEEP_AWAY = 4
# これより小さい透明のかたまりは「穴」として埋める（ロゴの O の穴などは大きいので残る）
SPECK_MAX = 1000
# 外側から何 px までの暗い画素を「縁の汚れ」として消すか
MATTE_WIDTH = 3
MATTE_DARK = 140


def layer_rgba(psd, name):
    for l in psd:
        if l.name == name:
            full = Image.new("RGBA", psd.size, (0, 0, 0, 0))
            full.alpha_composite(l.topil().convert("RGBA"), (l.left, l.top))
            return np.asarray(full).copy()
    sys.exit("layer not found: " + name)


def grow_under(fill, line_mask, border):
    """fill の色を、線の下（line_mask）へ GROW px まで塗り広げる"""
    solid = fill[..., 3] > 0
    # ふちのにじんだ画素は色が暗いので、内側の画素の色を広げる
    core = ndi.binary_erosion(solid, iterations=2)
    core |= solid & ~ndi.binary_dilation(core, iterations=3)   # 細い部分は消さない
    dist, (iy, ix) = ndi.distance_transform_edt(~core, return_indices=True)
    away = ndi.distance_transform_edt(~border) > KEEP_AWAY
    target = line_mask & ~solid & away & (ndi.distance_transform_edt(~solid) <= GROW)
    out = fill.copy()
    out[target] = fill[iy[target], ix[target]]
    out[target, 3] = 255
    return out


def clean(layers):
    """穴を埋め、外側の暗い縁を消す。どこを変えたか（マスク）を返す"""
    alive = np.stack([l[..., 3] > 0 for l in layers])
    union = alive.any(0)
    lab, n = ndi.label(~union)
    sizes = ndi.sum(~union, lab, range(1, n + 1))
    specks = np.isin(lab, 1 + np.nonzero(sizes < SPECK_MAX)[0])
    outer = ~union & ~specks
    # 穴の画素は、いちばん近い不透明の画素（とその層）をまねる
    _, (iy, ix) = ndi.distance_transform_edt(~union, return_indices=True)
    for k, l in enumerate(layers):
        take = specks & alive[k][iy, ix]
        l[take] = l[iy[take], ix[take]]
    # 外側の暗い縁
    dist = ndi.distance_transform_edt(~outer)
    union = np.stack([l[..., 3] > 0 for l in layers]).any(0)
    color = np.zeros(union.shape + (3,), int)
    for l in layers:
        on = l[..., 3] > 0
        color[on] = l[on][:, :3]
    matte = union & (dist <= MATTE_WIDTH) & (color.max(-1) < MATTE_DARK)
    for l in layers:
        l[matte] = 0
    return specks | matte


def main():
    psd = PSDImage.open(PSD)
    white = layer_rgba(psd, "枠（白フチ）")
    line = layer_rgba(psd, "枠（線）")
    deco = layer_rgba(psd, "飾り")
    liquid = layer_rgba(psd, "液体")
    text = layer_rgba(psd, "文字")
    ref = Image.new("RGBA", psd.size, (0, 0, 0, 0))
    for img in (white, line, deco, liquid, text):
        ref.alpha_composite(Image.fromarray(img))
    changed = clean([white, line, deco, liquid, text])

    line_mask = line[..., 3] > 0
    border = white[..., 3] > 0

    frame = white.copy()
    frame[line_mask] = line[line_mask]

    # 下地：白フチの内側を、線の色で塗る
    inside = line_mask | (deco[..., 3] > 0) | (liquid[..., 3] > 0) | (text[..., 3] > 0)
    brown = np.median(line[line_mask][:, :3], axis=0).astype(np.uint8)
    backing = np.zeros_like(frame)
    backing[inside] = (*brown, 255)

    layers = {
        "logo_backing": backing,
        "logo_liquid": grow_under(liquid, line_mask, border),
        "logo_text": grow_under(text, line_mask, border),
        "logo_deco": grow_under(deco, line_mask, border),
        "logo_frame": frame,
    }

    # ずらさずに重ねたとき、掃除したところ以外は PSD の見た目と同じか
    comp = Image.new("RGBA", psd.size, (0, 0, 0, 0))
    for img in layers.values():
        comp.alpha_composite(Image.fromarray(img))
    c = np.asarray(comp).astype(int)
    r = np.asarray(ref).astype(int)
    same = ~changed
    vis = same & (r[..., 3] > 0)
    if (c[..., 3][same] != r[..., 3][same]).any() or np.abs(c[..., :3] - r[..., :3])[vis].max() > 0:
        sys.exit("composite differs from the PSD")

    os.makedirs(OUT, exist_ok=True)
    for name, img in layers.items():
        Image.fromarray(img).save(os.path.join(OUT, name + ".png"), optimize=True)
    print("wrote %d layers to %s (%dx%d), cleaned %d px" % (len(layers), OUT, *psd.size, changed.sum()))


if __name__ == "__main__":
    main()
