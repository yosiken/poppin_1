# -*- coding: utf-8 -*-
"""収録したボイス（wav）を、ゲームで使う形に整える。

    python tools/process_voice.py [入力フォルダ] [出力フォルダ]

既定は resources/sound/OB_voice → resources/sound/voice。
元の wav には手を付けない。何度流しても同じ結果になる（出力を上書きする）。

やること（1本ずつ）:

1. モノラルにする
   届いた wav は左右がほぼ同じ（相関 0.9999 以上）なので、半分の容量で済む
2. 前後の無音を詰める
   声の出だしの 30ms 手前から、声の終わりの 150ms 後ろまでを残す。
   頭は 5ms、お尻は 60ms でフェードして、切り口でプツッと鳴らないようにする。
   「声がある」の判定は 10ms ごとの音量で、
   -45 dBFS と「その本のいちばん大きいところ − 35dB」の大きいほうを超えたら。
   収録の無音（ノイズ）は -52〜-62 dBFS だったので、これより十分上
3. 音量をそろえる
   聞こえる大きさ（ITU-R BS.1770 のラウドネス、LUFS）を TARGET_LUFS にそろえる。
   届いたままだと、ピークだけそろえてあって、聞こえる大きさは
   -16〜-6.6 LUFS とばらばらだった（叫び声ほど大きく聞こえる）。
   ただしピーク（4倍に細かくして測るトゥルーピーク）が PEAK_LIMIT を超えるときは、
   超えない所まで上げるのをやめる（音を潰さない）
4. 圧縮する
   Ogg Vorbis（品質 VORBIS_QUALITY）で書き出す。Godot がそのまま読める

ラウドネスの目安: ゲームの既存の音は、ためジャンプの声 jump_voice.mp3 が -12.2、
ゴールの音 goal1.mp3 が -12.8 LUFS（どちらもステレオで測った値）。
モノラルは左右に同じ音を出すので、ステレオで測ると +3dB 大きく出る。
TARGET_LUFS -17（モノラル）は、ステレオで測ると約 -14 で、既存の声より少し控えめ。
"""
import io
import os
import subprocess
import sys
import tempfile

import numpy as np
import soundfile as sf
from scipy.signal import lfilter, resample_poly

SRC = os.path.join("resources", "sound", "OB_voice")
DST = os.path.join("resources", "sound", "voice")

TARGET_LUFS = -17.0      # モノラルで測った値。ステレオ換算で約 -14
PEAK_LIMIT = -1.0        # dBTP。これを超えるほどには上げない
GATE_ABS = -45.0         # dBFS。これより小さい音は「無音」
GATE_REL = 35.0          # dB。その本の最大音量からこれだけ下までを「声」とみなす
KEEP_HEAD = 0.030        # 秒。出だしの手前に残す
KEEP_TAIL = 0.150        # 秒。終わりの後ろに残す（息や響きの消え際）
FADE_IN = 0.005
FADE_OUT = 0.060
VORBIS_QUALITY = "5"     # 0〜10。5 でモノラル 80kbps 前後。声なら十分きれい


# ─────────────────────────────── ラウドネス（BS.1770）

def k_weight(x, sr):
    """人の耳の感じ方に寄せる重み付け。係数は 48kHz 用（BS.1770 の表のまま）"""
    if sr != 48000:
        raise ValueError("48kHz の wav だけ扱える（%d Hz だった）" % sr)
    b1 = [1.53512485958697, -2.69169618940638, 1.19839281085285]
    a1 = [1.0, -1.69065929318241, 0.73248077421585]
    b2 = [1.0, -2.0, 1.0]
    a2 = [1.0, -1.99004745483398, 0.99007225036621]
    return lfilter(b2, a2, lfilter(b1, a1, x))


def loudness(x, sr):
    """モノラルの統合ラウドネス (LUFS)。400ms の区間を 100ms ずつずらして測り、
    -70 LUFS と「平均 − 10」より静かな区間は数えない（BS.1770 のゲート）。
    400ms より短い本は全体を1区間として測る"""
    y = k_weight(x, sr)
    blk, hop = int(0.4 * sr), int(0.1 * sr)
    if len(y) < blk:
        ms = np.array([np.mean(y ** 2)])
    else:
        ms = np.array([np.mean(y[i:i + blk] ** 2) for i in range(0, len(y) - blk + 1, hop)])
    lv = -0.691 + 10 * np.log10(np.maximum(ms, 1e-12))
    g = ms[lv > -70]
    if len(g) == 0:
        return -99.0
    rel = -0.691 + 10 * np.log10(g.mean()) - 10
    g = ms[(lv > -70) & (lv > rel)]
    return -0.691 + 10 * np.log10(g.mean())


def true_peak(x):
    """4倍に細かくしてから測るピーク (dBTP)。サンプルの間で振り切れるのも拾う"""
    return 20 * np.log10(np.abs(resample_poly(x, 4, 1)).max() + 1e-12)


# ─────────────────────────────── 無音を詰める

def trim(x, sr):
    win = int(0.010 * sr)
    n = len(x) // win
    rms = np.sqrt(np.mean(x[:n * win].reshape(n, win) ** 2, axis=1))
    db = 20 * np.log10(rms + 1e-12)
    gate = max(GATE_ABS, db.max() - GATE_REL)
    on = np.nonzero(db > gate)[0]
    if len(on) == 0:
        return x, 0.0, 0.0
    start = max(0, on[0] * win - int(KEEP_HEAD * sr))
    end = min(len(x), (on[-1] + 1) * win + int(KEEP_TAIL * sr))
    y = x[start:end].copy()
    fi = min(int(FADE_IN * sr), len(y))
    fo = min(int(FADE_OUT * sr), len(y))
    y[:fi] *= np.linspace(0.0, 1.0, fi)
    y[len(y) - fo:] *= np.linspace(1.0, 0.0, fo)
    return y, start / sr, (len(x) - end) / sr


# ─────────────────────────────── 1本ぶん

def out_name(src_name):
    """「39-無題.wav.wav」のように拡張子が2重のものも、拡張子を1つにする"""
    base = src_name
    while base.lower().endswith(".wav"):
        base = base[:-4]
    return base + ".ogg"


def process(src, dst):
    x, sr = sf.read(src, dtype="float64", always_2d=True)
    mono = x.mean(axis=1)
    before_lufs = loudness(mono, sr)
    y, cut_head, cut_tail = trim(mono, sr)

    lufs = loudness(y, sr)
    gain = TARGET_LUFS - lufs
    peak_after = true_peak(y) + gain
    capped = peak_after > PEAK_LIMIT
    if capped:
        gain -= peak_after - PEAK_LIMIT
    y = y * (10 ** (gain / 20))

    fd, tmp = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    try:
        sf.write(tmp, y.astype(np.float32), sr, subtype="FLOAT")
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", tmp,
                        "-c:a", "libvorbis", "-q:a", VORBIS_QUALITY, dst], check=True)
    finally:
        os.remove(tmp)

    return {
        "before_sec": len(mono) / sr, "after_sec": len(y) / sr,
        "cut_head": cut_head, "cut_tail": cut_tail,
        "before_lufs": before_lufs, "after_lufs": loudness(y, sr),
        "peak": true_peak(y), "capped": capped,
        "src_bytes": os.path.getsize(src), "dst_bytes": os.path.getsize(dst),
    }


def main():
    src_dir = sys.argv[1] if len(sys.argv) > 1 else SRC
    dst_dir = sys.argv[2] if len(sys.argv) > 2 else DST
    os.makedirs(dst_dir, exist_ok=True)
    rows = []
    for name in sorted(os.listdir(src_dir)):
        if not name.lower().endswith(".wav"):
            continue
        r = process(os.path.join(src_dir, name), os.path.join(dst_dir, out_name(name)))
        r["name"] = out_name(name)
        rows.append(r)

    # 結果の一覧（UTF-8 で書く。Windows の端末は日本語が化けるので、画面には数字だけ出す）
    report = os.path.join(dst_dir, "_report.tsv")
    with io.open(report, "w", encoding="utf-8", newline="\n") as f:
        f.write("file\tsec_before\tsec_after\tcut_head\tcut_tail\tlufs_before\tlufs_after\tpeak_dbtp\tpeak_capped\tkb_before\tkb_after\n")
        for r in rows:
            f.write("%s\t%.2f\t%.2f\t%.2f\t%.2f\t%.1f\t%.1f\t%.1f\t%s\t%d\t%d\n" % (
                r["name"], r["before_sec"], r["after_sec"], r["cut_head"], r["cut_tail"],
                r["before_lufs"], r["after_lufs"], r["peak"], "yes" if r["capped"] else "",
                r["src_bytes"] // 1024, r["dst_bytes"] // 1024))
    src_mb = sum(r["src_bytes"] for r in rows) / 1048576
    dst_mb = sum(r["dst_bytes"] for r in rows) / 1048576
    print("files %d  size %.1f MB -> %.2f MB" % (len(rows), src_mb, dst_mb))
    print("report: %s" % report)


if __name__ == "__main__":
    main()
