# -*- coding: utf-8 -*-
"""イベントの .tres に、仮の絵（背景・ポップアップ）を割り当てる。

    python tools/assign_event_art.py [--dry-run] [--force] [--only <イベント名>]

割り当ては資材リストのカット表どおり。本番の絵が来るまでの仮置きで、
どのコマに何が出るかを実際に動かして確かめられるようにするためのもの。

既に入っている指定は書き換えない。手で入れたものが消えないようにしてある。
--force を付けると対応表どおりに上書きする。手で入れた指定も消えるので、
「資材リストの状態に戻したい」ときだけ使うこと。
--only opening のように書くと、そのイベントだけを対象にする。
1箇所だけ直したいときに、他の手作業を巻き込まずに済む。
背景はイベントの先頭のコマに置く（Cutscene は「指定したものだけ変わる」方式なので、
一度置けばそのイベントの間ずっと出たままになる）。

コマの指定は台詞の本文で探す。台本を書き換えるとここも合わなくなるので、
そのときは対応表を直すこと。見つからなかった分は最後にまとめて報告する。
"""

import re
import sys
from pathlib import Path

CUT = Path("resources/cutscene")
BG = "res://resources/texture/BG/event/%s.png"
POP = "res://resources/texture/event/popup/%s.png"

# 背景。(イベント, 本文の一部 or None=先頭のコマ, 画像)
BACKGROUNDS = [
    ("opening",       None,                     "BG-01"),   # 自宅リビング・夜
    ("opening",       "ん……？　ここ……どこ？",   "BG-04"),   # 石畳の広場へ
    ("stage01_intro", None, "BG-05"), ("stage01_outro", None, "BG-05"),   # 酒蔵の林
    ("stage02_intro", None, "BG-06"), ("stage02_outro", None, "BG-06"),   # 泡の泉／氷の洞窟
    ("stage03_intro", None, "BG-07"), ("stage03_outro", None, "BG-07"),   # 港・浜辺
    ("stage04_intro", None, "BG-08"), ("stage04_outro", None, "BG-08"),   # 南国の音楽堂
    ("stage05_intro", None, "BG-09"), ("stage05_outro", None, "BG-09"),   # 本の塔・図書館
    ("stage06_intro", None, "BG-10"), ("stage06_outro", None, "BG-10"),   # ドット絵の遺跡
    ("stage07_intro", None, "BG-11"), ("stage07_outro", None, "BG-11"),   # 石造りのダンジョン
    ("stage08_intro", None, "BG-12"), ("stage08_outro", None, "BG-12"),   # 金貨の山・金庫室
    ("stage09_intro", None, "BG-13"), ("stage09_outro", None, "BG-13"),   # 山道
    ("stage10_intro", None, "BG-04"),                                     # 最初の広場へ戻る
    ("stage10_outro", None, "BG-04"),
    ("stage10_outro", "目の前に光のゲート",       "BG-14"),  # note 側にしか無い場合は拾えない
    ("ending",        None,                      "BG-03"),  # 寝室・ベッド
]

# ポップアップ。(イベント, 本文の一部, 画像)
# MISS-XX は誤答カットイン（赤枠）、POP-XX は実況ポップアップ（青枠）。
# 種別は画像名から決める。CutsceneEditor で選んだときと同じ扱いにするため、
# MISS には popup_kind = 1 も一緒に書き込む
POPUPS = [
    ("opening",       "あっ、ビールある",          "POP-01"),
    ("opening",       "いったぁぁぁぁぁぁぁ",       "POP-04"),
    ("opening",       "全部思い出したら、現世へ",   "POP-05"),
    ("stage01_intro", "……水？",                   "MISS-01"),
    ("stage01_outro", "『風の林』",                "POP-07"),
    ("stage02_intro", "……ジュース？",             "MISS-02"),
    ("stage02_outro", "…………これだ！",            "POP-09"),
    ("stage03_intro", "赤い。足が多い。殻がある",   "POP-11"),
    ("stage03_outro", "しかもタラバ",              "POP-12"),
    ("stage04_intro", "ギター？",                  "MISS-04"),
    ("stage04_outro", "名前も思い出した",          "POP-15"),
    ("stage05_intro", "……教科書？",               "MISS-05"),
    ("stage05_outro", "『葬送のオバーレン』！",     "POP-16"),
    ("stage06_intro", "ふーふー吹くやつや",        "POP-18"),
    ("stage06_outro", "求婚されたんだよ",          "POP-19"),
    ("stage07_intro", "どうなっても知らんで",      "POP-21"),
    ("stage07_outro", "ガブガブ",                  "POP-22"),
    ("stage07_outro", "暗いよー！怖いよー！",      "POP-23"),
    ("stage08_intro", "目が＄になっとるぞ",        "POP-24"),
    ("stage09_intro", "握る……おにぎり？",         "MISS-07"),
    ("stage09_outro", "OBやりとげました",          "POP-28"),
    ("stage10_outro", "…………え",                  "POP-29"),
    ("ending",        "いったぁぁぁぁぁ！！",       "POP-33"),
]

WS = re.compile(r"[\s　]")
dry = "--dry-run" in sys.argv
force = "--force" in sys.argv
# --only <イベント名>。指定が無ければ全イベントが対象
only = ""
if "--only" in sys.argv:
    at = sys.argv.index("--only")
    only = sys.argv[at + 1] if at + 1 < len(sys.argv) else ""
missing, added, kept, replaced = [], 0, 0, 0


def blocks(text):
    """[sub_resource ...] ごとに (開始位置, 終了位置, 本文) を返す"""
    out = []
    for m in re.finditer(r"\[sub_resource[^\]]*\]\n", text):
        start = m.end()
        nxt = text.find("\n[", start)
        end = len(text) if nxt < 0 else nxt + 1
        out.append((start, end, text[start:end]))
    return out


def ext_id(text, path):
    """その画像の ExtResource id。無ければ宣言を足して新しい id を返す"""
    m = re.search(r'\[ext_resource type="Texture2D"[^\]]*path="%s" id="([^"]+)"\]'
                  % re.escape(path), text)
    if m:
        return text, m.group(1)
    used = set(re.findall(r'id="([^"]+)"', text))
    n = 90
    while "%d_art" % n in used:
        n += 1
    new_id = "%d_art" % n
    decl = '[ext_resource type="Texture2D" path="%s" id="%s"]\n' % (path, new_id)
    last = list(re.finditer(r"\[ext_resource[^\]]*\]\n", text))[-1]
    return text[:last.end()] + decl + text[last.end():], new_id


def assign(path_tres, needle, img, prop):
    global added, kept, replaced
    was_replace = False
    text = path_tres.read_text(encoding="utf-8")
    bl = blocks(text)
    if not bl:
        return
    if needle is None:
        target = bl[0]
    else:
        key = WS.sub("", needle)
        target = next((b for b in bl if key in WS.sub("", b[2])), None)
        if target is None:
            missing.append("%s : %s (%s)" % (path_tres.stem, needle, img))
            return
    if re.search(r"^%s = " % prop, target[2], re.M):
        if not force:
            kept += 1
            return
        # 対応表どおりに差し替える。古い指定の行を落としてから入れ直す
        body = re.sub(r"^(%s|popup_kind) = .*\n" % prop, "", target[2], flags=re.M)
        text = text[:target[0]] + body + text[target[1]:]
        bl = blocks(text)
        target = bl[0] if needle is None else next(
            b for b in bl if WS.sub("", needle) in WS.sub("", b[2]))
        replaced += 1
        was_replace = True
    text, rid = ext_id(text, img)
    bl = blocks(text)
    target = bl[0] if needle is None else next(
        b for b in bl if WS.sub("", needle) in WS.sub("", b[2]))
    # ブロックの終わりには次の [sub_resource] との間の空行が含まれる。
    # そこへ入れると property が空行の後ろに来て読みにくいので、
    # 最後の行の直後まで戻してから挿す
    ins = target[1]
    while ins > 1 and text[ins - 1] == "\n" and text[ins - 2] == "\n":
        ins -= 1
    line = '%s = ExtResource("%s")\n' % (prop, rid)
    # 誤答カットインは赤枠。既定は青枠なので、MISS のときだけ種別も書く
    if prop == "popup" and Path(img).stem.startswith("MISS"):
        line += "popup_kind = 1\n"
    text = text[:ins] + line + text[ins:]
    if not was_replace:
        added += 1
    if not dry:
        path_tres.write_text(text, encoding="utf-8")


for event, needle, name in BACKGROUNDS:
    f = CUT / (event + ".tres")
    if f.exists() and (not only or only == event):
        assign(f, needle, BG % name, "background")
for event, needle, name in POPUPS:
    f = CUT / (event + ".tres")
    if f.exists() and (not only or only == event):
        assign(f, needle, POP % name, "popup")

print("追加 %d 件 / 差し替え %d 件 / 既に指定があり据え置き %d 件"
      % (added, replaced, kept))
if missing:
    print("\n本文が見つからず割り当てられなかったもの:")
    for m in missing:
        print("  ", m)
if dry:
    print("\n(--dry-run のためファイルは書き換えていない)")
