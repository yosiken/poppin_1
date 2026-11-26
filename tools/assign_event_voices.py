# -*- coding: utf-8 -*-
"""イベント（カットシーン）のコマに、OB の本物の声を割り当てる。

    python tools/assign_event_voices.py

コマは番号ではなく「話者と本文」で探す（CutsceneEditor でコマを挿したり
分けたりしても、ずれないように）。同じ本文が何度も出るコマ（「…………」など）は、
そのイベントの中で何回目かで指す。

声は resources/sound/voice の番号（ファイル名の頭2桁）で指す。
何度流しても同じ結果になる。表に無いコマの声には触らない。
割り当てを直すときは、この表を直して流し直すか、CutsceneEditor の「声」で選ぶ。

.tres はテキストのまま書き換える（声の行と ext_resource を足すだけ）。
Godot の ResourceSaver で保存し直すと、ほかの ext_resource から uid が外れて
差分が大きくなるため。

台本の本文と声のセリフは同じではない。声は「そのコマの気持ちに合う反応」として
選んである。ただし長いセリフ（17・38・39 など）は、2026-11-26 の調整で
声のとおりの本文のコマを台本に足してある（resources/text/シナリオ調整案.md）。
"""
import io
import os
import re
import sys

CUTSCENE_DIR = os.path.join("resources", "cutscene")
VOICE_DIR = os.path.join("resources", "sound", "voice")

# (イベント, 話者, 本文, 何回目(0から), 声の番号)
TABLE = [
    ("opening", "OB", "今日も一日お疲れ様でした〜", 0, "40"),
    ("opening", "OB", "……全然酔ってないんですけれどもね", 0, "49"),
    ("opening", "OB", "いったぁぁぁぁぁぁぁ！！", 0, "06"),
    ("opening", "OB", "……ん……？　ここ……どこ？", 0, "60"),
    ("opening", "OB", "……え？", 0, "25"),
    ("opening", "OB", "そんなことある？", 0, "47"),
    ("opening", "OB", "10個……？", 0, "26"),
    ("opening", "OB", "えっ、なんで？", 0, "59"),
    ("opening", "OB", "…………正論", 0, "64"),
    ("stage01_outro", "OB", "体が震える。これは絶対に私が好きなやつ！", 0, "41"),
    ("stage02_outro", "OB", "開けたんなら飲むしか無いよね。仕方ないよね！ね！", 0, "21"),
    ("stage03_intro", "OB", "えー", 0, "57"),
    ("stage03_intro", "OB", "早く行こう！", 0, "42"),
    ("stage03_outro", "OB", "…………", 0, "30"),
    ("stage04_intro", "OB", "うーん……こうかなー？", 0, "50"),
    ("stage04_outro", "OB", "田中は誰やねん", 0, "28"),
    ("stage05_outro", "OB", "ちょっと伸び伸びタイム〜", 0, "17"),
    ("stage06_intro", "OB", "ふーふーふーふーふー", 0, "22"),
    ("stage07_intro", "OB", "じゃあ問答無用で開ける！", 0, "44"),
    ("stage07_outro", "OB", "びゃあー！　まずいー！", 0, "58"),
    ("stage07_outro", "OB", "うわぁぁぁぁ", 0, "07"),
    ("stage08_intro", "OB", "わかった！　わかっちゃった！", 0, "46"),
    ("stage08_outro", "OB", "私は諦めの悪い女……！", 0, "12"),
    ("stage09_intro", "OB", "……まだだ、まだ慌てるような時間じゃない", 0, "11"),
    ("stage09_intro", "OB", "一旦深呼吸しますね", 0, "18"),
    ("stage09_intro", "OB", "すぅー……はぁー……", 0, "19"),
    ("stage09_outro", "OB", "越えたー！", 0, "20"),
    ("stage09_outro", "OB", "ふー、経験が生きたな", 0, "55"),
    ("stage09_outro", "OB", "カニエナガ、やっと帰れるよー！　宴会する？　飲み会する？", 0, "39"),
    ("stage10_outro", "OB", "全部思い出した", 0, "37"),
    ("stage10_outro", "OB", "やっと帰れる……帰れるよ、カニエナガ！", 0, "38"),
    ("ending", "OB", "いったぁぁぁぁぁ！！", 0, "06"),
]

STR = r'"((?:[^"\\]|\\.)*)"'


def unescape(s):
    return re.sub(r'\\(.)', lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)


def voice_files():
    out = {}
    for name in sorted(os.listdir(VOICE_DIR)):
        if name.endswith(".ogg"):
            out.setdefault(name[:2], name)
    return out


def uid_of(path):
    imp = path + ".import"
    if os.path.exists(imp):
        m = re.search(r'(?m)^uid="([^"]+)"', io.open(imp, encoding="utf-8").read())
        if m:
            return m.group(1)
    return ""


def apply(event, rows, voices):
    path = os.path.join(CUTSCENE_DIR, event + ".tres")
    src = io.open(path, encoding="utf-8").read()
    blocks = re.split(r"(?m)^(?=\[)", src)

    # [resource] の lines の並び順（コマの順）
    res = next(b for b in blocks if b.startswith("[resource]"))
    order = re.findall(r'SubResource\("([^"]+)"\)', re.search(r"(?m)^lines = .*$", res).group(0))
    by_id = {}
    for i, b in enumerate(blocks):
        m = re.match(r'\[sub_resource type="Resource" id="([^"]+)"\]', b)
        if m:
            by_id[m.group(1)] = i

    def info(b):
        sp = re.search(r"(?m)^speaker = " + STR, b)
        tx = re.search(r"(?ms)^text = " + STR, b)
        return (unescape(sp.group(1)) if sp else "", unescape(tx.group(1)).strip() if tx else "")

    added_ext = []
    failed = 0
    for _, speaker, text, nth, num in rows:
        seen = 0
        target = None
        for sid in order:
            if sid not in by_id:
                continue
            sp, tx = info(blocks[by_id[sid]])
            if sp == speaker and tx == text:
                if seen == nth:
                    target = by_id[sid]
                    break
                seen += 1
        name = voices.get(num)
        if target is None or name is None:
            print("  NG  %s: %s" % (event, "line not found" if target is None else "voice %s missing" % num))
            failed += 1
            continue
        ext_id = "voice_%s" % num
        if 'id="%s"' % ext_id not in src and ext_id not in added_ext:
            added_ext.append(ext_id)
            res_path = "res://resources/sound/voice/" + name
            uid = uid_of(os.path.join(VOICE_DIR, name))
            line = '[ext_resource type="AudioStream"%s path="%s" id="%s"]\n' % (
                ' uid="%s"' % uid if uid else "", res_path, ext_id)
            # 最後の ext_resource の後ろに足す
            last_ext = max(i for i, b in enumerate(blocks) if b.startswith("[ext_resource"))
            blocks[last_ext] = blocks[last_ext].rstrip("\n") + "\n" + line + (
                "\n" if blocks[last_ext].endswith("\n\n") else "")
        b = blocks[target]
        v = 'voice = ExtResource("%s")' % ext_id
        if re.search(r"(?m)^voice = .*$", b):
            b = re.sub(r"(?m)^voice = .*$", v, b)
        else:
            body = b.rstrip("\n")
            tail = b[len(body):]
            b = body + "\n" + v + tail
        blocks[target] = b

    out = "".join(blocks)
    if added_ext:
        out = re.sub(r"load_steps=(\d+)", lambda m: "load_steps=%d" % (int(m.group(1)) + len(added_ext)), out, count=1)
    io.open(path, "w", encoding="utf-8", newline="\n").write(out)
    return len(rows) - failed, failed


def main():
    voices = voice_files()
    events = []
    for row in TABLE:
        if row[0] not in events:
            events.append(row[0])
    ok = ng = 0
    for ev in events:
        a, b = apply(ev, [r for r in TABLE if r[0] == ev], voices)
        ok += a
        ng += b
    print("assigned %d, failed %d" % (ok, ng))
    sys.exit(1 if ng else 0)


if __name__ == "__main__":
    main()
