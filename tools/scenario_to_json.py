"""シナリオ台本 (Markdown) をイベントデータ用の JSON へ変換する。

    python tools/scenario_to_json.py resources/dotonbori-isekai-scenario.md

出力: resources/cutscene/scenario.json
そのあと Godot 側で tools/make_cutscenes.gd を実行すると .tres が生成される。

変換ルール:
  - 「## 【...】」で場面を区切る
  - 「**話者**」の次の行以降を、その話者のセリフとして拾う
  - 〔演出：...〕はゲーム中のテキストにはせず、note として JSON に残す
  - 各ステージは「冒頭のナビゲーター（左側）の問いかけ」を intro、
    「主人公（右側）が答える以降」を outro に割る
  - 長すぎるセリフはテキストウインドウに収まる長さで複数コマに分割する
"""

import json
import re
import sys
from pathlib import Path

# テキストウインドウ1コマに入れる全角換算の目安
MAX_CHARS = 105

# 話者名 -> 立ち絵の位置。台本で名前を変えたらここも直すこと
SPEAKERS = {"OB": "right", "カニエナガ": "left"}


unknown_speakers = set()


def parse(md_path):
    text = md_path.read_text(encoding="utf-8")
    scenes = []
    current = None
    speaker = None

    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("## 【"):
            title = line[3:].strip().strip("【】")
            current = {"title": title, "beats": []}
            scenes.append(current)
            speaker = None
            continue
        if current is None or not line or line.startswith("---"):
            continue

        # 〔演出：...〕
        if line.startswith("**〔") or line.startswith("〔"):
            note = line.strip("*").strip("〔〕")
            current["beats"].append({"kind": "note", "text": note})
            speaker = None
            continue

        # **話者**
        m = re.fullmatch(r"\*\*(.+?)\*\*", line)
        if m:
            name = m.group(1)
            if name in SPEAKERS:
                speaker = name
                continue
            # 台本側で名前が変わると黙って0件になるので拾っておく
            if len(name) <= 12 and "〔" not in name:
                unknown_speakers.add(name)
            continue

        if speaker:
            current["beats"].append({"kind": "line", "speaker": speaker,
                                     "text": _clean(line)})
            # 同じ話者の複数行はそのまま続ける（閉じ括弧まで）
            if line.endswith("」"):
                speaker = None
    return scenes


def _clean(s):
    s = s.strip()
    # セリフを囲む鉤括弧は表示に不要
    if s.startswith("「") and s.endswith("」"):
        s = s[1:-1]
    elif s.startswith("「"):
        s = s[1:]
    elif s.endswith("」"):
        s = s[:-1]
    return s.strip()


def width(s):
    """全角を1、半角を0.5として数える"""
    total = 0.0
    for ch in s:
        total += 0.5 if ord(ch) < 0x2E80 else 1.0
    return total


def split_long(s):
    """長いセリフを句点などで分割する"""
    if width(s) <= MAX_CHARS:
        return [s]
    # まず改行らしき区切りで割り、それでも長ければ句読点で割る
    parts = []
    buf = ""
    for chunk in re.split(r"(?<=[。！？])", s):
        if not chunk:
            continue
        if buf and width(buf + chunk) > MAX_CHARS:
            parts.append(buf.strip())
            buf = chunk
        else:
            buf += chunk
    if buf.strip():
        parts.append(buf.strip())
    return parts or [s]


def merge_multiline(beats):
    """同じ話者の連続行を1つにまとめる"""
    out = []
    for b in beats:
        if (b["kind"] == "line" and out and out[-1]["kind"] == "line"
                and out[-1]["speaker"] == b["speaker"]):
            out[-1]["text"] = out[-1]["text"] + b["text"]
        else:
            out.append(dict(b))
    return out


def to_events(scenes):
    """場面を、ゲーム側のイベント単位（opening / stageNN_intro / ... / ending）へ割る"""
    events = {}
    for scene in scenes:
        title = scene["title"]
        beats = merge_multiline(scene["beats"])
        lines = [b for b in beats if b["kind"] == "line"]
        notes = [b["text"] for b in beats if b["kind"] == "note"]
        if not lines:
            continue

        if "プロローグ" in title or title.startswith("OP"):
            events["opening"] = {"title": title, "lines": lines, "notes": notes}
            continue
        if "エピローグ" in title or title.startswith("ED"):
            events["ending"] = {"title": title, "lines": lines, "notes": notes}
            continue

        m = re.match(r"ステージ(\d+)", title)
        if not m:
            continue
        num = int(m.group(1))

        # 冒頭に続くナビゲーター（左側）の問いかけを intro、そこから先を outro にする。
        # 主人公から始まる場面（ステージ10）は intro 無しで全部 outro に回す。
        # 名前で判定すると台本の改名で壊れるので、立ち絵の位置で見る
        split_at = 0
        while split_at < len(lines) and SPEAKERS[lines[split_at]["speaker"]] == "left":
            split_at += 1
        intro = lines[:split_at]
        outro = lines[split_at:]
        if intro:
            events["stage%02d_intro" % num] = {"title": title, "lines": intro, "notes": notes}
        if outro:
            events["stage%02d_outro" % num] = {"title": title, "lines": outro, "notes": notes}
    return events


def expand(events):
    """長いセリフを分割し、立ち絵の指定を付ける"""
    out = {}
    for key, ev in events.items():
        seen_left = False
        seen_right = False
        rows = []
        for line in ev["lines"]:
            side = SPEAKERS[line["speaker"]]
            for i, chunk in enumerate(split_long(line["text"])):
                row = {"speaker": line["speaker"], "text": chunk, "side": side}
                # その場面で初めて出る話者の立ち絵を出す
                if side == "left" and not seen_left:
                    row["show_left"] = True
                    seen_left = True
                if side == "right" and not seen_right:
                    row["show_right"] = True
                    seen_right = True
                # 分割した2コマ目以降は話者名を出さない
                if i > 0:
                    row["speaker"] = ""
                rows.append(row)
        out[key] = {"title": ev["title"], "notes": ev["notes"], "rows": rows}
    return out


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    md = Path(argv[0])
    scenes = parse(md)
    events = expand(to_events(scenes))

    if unknown_speakers:
        print("警告: SPEAKERS に無い話者名: %s" % "、".join(sorted(unknown_speakers)))
    if not events:
        print("エラー: イベントを1件も抽出できませんでした。")
        print("  台本の話者名が SPEAKERS (%s) と一致しているか確認してください。"
              % "、".join(SPEAKERS))
        return 1

    print("場面 %d 件 -> イベント %d 件" % (len(scenes), len(events)))
    out_dir = Path("resources/cutscene")
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "scenario.json"
    out_path.write_text(json.dumps(events, ensure_ascii=False, indent=1),
                        encoding="utf-8")

    for key in sorted(events):
        ev = events[key]
        longest = max((width(r["text"]) for r in ev["rows"]), default=0)
        print("  %-18s コマ%2d  最長%5.1f  %s"
              % (key, len(ev["rows"]), longest, ev["title"]))
    print("->", out_path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
