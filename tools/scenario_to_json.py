"""シナリオ台本 (Markdown) をイベントデータ用の JSON へ変換する。

    python tools/scenario_to_json.py resources/dotonbori-isekai-scenario-v2.md

出力: resources/cutscene/scenario.json
そのあと Godot 側で tools/make_cutscenes.gd を実行すると .tres が生成される。

変換ルール:
  - 「## 【...】」で場面を区切る。「STAGE 1」「ステージ1」どちらの書き方でも拾う
  - 「**話者**」の次の行以降を、その話者のセリフとして拾う
  - 〔演出：...〕はゲーム中のテキストにはせず、note として JSON に残す
  - 各ステージは「### スタート前」を intro（面に入る前）、
    「### ゴール・…取得後」を outro（クリア後）に割る。
    見出しが無い台本では「記憶が戻る〔演出〕」を境にする（旧版向けの保険）
  - 長すぎるセリフはテキストウインドウに収まる長さで複数コマに分割する
"""

import json
import re
import sys
from pathlib import Path

# テキストウインドウ1コマに入れる全角換算の目安
MAX_CHARS = 105

# 話者名 -> 立ち絵の位置。台本で名前を変えたらここも直すこと。
# "none" は立ち絵を持たない声（画面に流れるコメントなど）
SPEAKERS = {"OB": "right", "カニエナガ": "left", "オビラーたち": "none",
            "ミミック": "none"}

# ステージを intro / outro に割る見出し（「### 〜」で書く）
MARK_INTRO = "スタート前"
MARK_OUTRO_PREFIX = "ゴール・"


unknown_speakers = set()
unmatched_titles = []


def parse(md_path):
    text = md_path.read_text(encoding="utf-8")
    scenes = []
    current = None
    speaker = None
    # セリフが「」で閉じずに次の行へ続いているか。続きだけを1コマにまとめたい。
    # 話者名を書き直した別のセリフは、同じ話者でも別のコマとして残す
    continuing = False

    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("## 【"):
            title = line[3:].strip().strip("【】")
            current = {"title": title, "beats": []}
            scenes.append(current)
            speaker = None
            continuing = False
            continue
        if current is None or not line or line.startswith("---"):
            continue

        # 「### スタート前」「### ゴール・アイテム取得後」。intro / outro の境目
        if line.startswith("###"):
            current["beats"].append({"kind": "mark", "text": line.lstrip("#").strip()})
            speaker = None
            continuing = False
            continue

        # 〔演出：...〕
        if line.startswith("**〔") or line.startswith("〔"):
            note = line.strip("*").strip("〔〕")
            current["beats"].append({"kind": "note", "text": note})
            speaker = None
            continuing = False
            continue

        # **話者**
        m = re.fullmatch(r"\*\*(.+?)\*\*", line)
        if m:
            name = m.group(1)
            if name in SPEAKERS:
                speaker = name
                continuing = False      # 名前を書き直したら、そこから別のコマ
                continue
            # 台本側で名前が変わると黙って0件になるので拾っておく
            if len(name) <= 12 and "〔" not in name:
                unknown_speakers.add(name)
            continue

        if speaker:
            current["beats"].append({"kind": "line", "speaker": speaker,
                                     "text": _clean(line), "cont": continuing})
            # 同じ話者の複数行はそのまま続ける（閉じ括弧まで）
            if line.endswith("」"):
                speaker = None
                continuing = False
            else:
                continuing = True
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
    """「」で閉じずに折り返した続きの行を、元のセリフにつなぎ直す。

    話者名を書き直してある連続セリフは、同じ話者でも別のコマとして残す。
    台本では一呼吸ごとに名前を書き直しており、その区切りがそのまま
    テキストウインドウの送りになるため
    """
    out = []
    for b in beats:
        if b["kind"] == "line" and b.get("cont") and out and out[-1]["kind"] == "line":
            out[-1]["text"] = out[-1]["text"] + b["text"]
        else:
            out.append(dict(b))
    return out


def _pack(title, beats):
    return {"title": title,
            # セリフと〔演出〕を台本の順のまま持つ。expand が〔演出〕を
            # 直後のコマへ結び付けるのに使う
            "beats": [b for b in beats if b["kind"] in ("line", "note")],
            "lines": [b for b in beats if b["kind"] == "line"],
            "notes": [b["text"] for b in beats if b["kind"] == "note"]}


def split_index(beats):
    """intro と outro の境目になる beats のインデックスを返す。

    台本に「### ゴール・アイテム取得後」の見出しがあればそこで割る。
    面に入る前の会話が intro、クリアしてアイテムを取ったあとが outro。
    """
    for i, b in enumerate(beats):
        if b["kind"] == "mark" and b["text"].startswith(MARK_OUTRO_PREFIX):
            return i
    return _split_index_legacy(beats)


def _split_index_legacy(beats):
    """見出しが無い台本向けの保険。

    旧版の台本では、ステージを攻略して記憶が戻る瞬間が〔演出：…〕で書かれていた。
    そこを境にして、〔演出〕自体は「思い出した」側の出来事なので outro に含める。
    場面の頭に置かれた雰囲気メモ（まだセリフが1つも無いうちの〔演出〕）は
    境目にしない。演出から始まる場面で intro が空になるため
    """
    seen_line = False
    for i, b in enumerate(beats):
        if b["kind"] == "line":
            seen_line = True
        elif b["kind"] == "note" and seen_line:
            return i

    # 〔演出〕でも割れない場合は、冒頭に続くナビゲーター（左側）の問いかけまでを intro に。
    # 名前で判定すると台本の改名で壊れるので、立ち絵の位置で見る
    i = 0
    while i < len(beats) and (beats[i]["kind"] != "line"
                              or SPEAKERS[beats[i]["speaker"]] == "left"):
        i += 1
    return i


def to_events(scenes):
    """場面を、ゲーム側のイベント単位（opening / stageNN_intro / ... / ending）へ割る"""
    events = {}
    for scene in scenes:
        title = scene["title"]
        beats = merge_multiline(scene["beats"])
        if not any(b["kind"] == "line" for b in beats):
            continue

        if "プロローグ" in title or title.startswith("OP"):
            events["opening"] = _pack(title, beats)
            continue
        if "エピローグ" in title or title.startswith("ED"):
            events["ending"] = _pack(title, beats)
            continue

        m = re.match(r"(?:ステージ|STAGE)\s*(\d+)", title, re.IGNORECASE)
        if not m:
            # 見出しの書き方が変わると黙って丸ごと落ちるので拾っておく
            unmatched_titles.append(title)
            continue
        num = int(m.group(1))

        at = split_index(beats)
        intro = _pack(title, beats[:at])
        outro = _pack(title, beats[at:])
        if intro["lines"]:
            events["stage%02d_intro" % num] = intro
        if outro["lines"]:
            events["stage%02d_outro" % num] = outro
    return events


def expand(events):
    """長いセリフを分割し、立ち絵と〔演出〕の指定を付ける。

    〔演出：…〕は「その直後のコマで起きること」として、次のコマに結び付ける。
    場面の最後に置かれていて続くコマが無いものは、最後のコマにまとめる
    """
    out = {}
    for key, ev in events.items():
        seen_left = False
        seen_right = False
        rows = []
        pending = []
        for beat in ev["beats"]:
            if beat["kind"] == "note":
                pending.append(beat["text"])
                continue
            side = SPEAKERS[beat["speaker"]]
            for i, chunk in enumerate(split_long(beat["text"])):
                row = {"speaker": beat["speaker"], "text": chunk, "side": side}
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
                # 〔演出〕は分割した1コマ目にだけ付ける
                if i == 0 and pending:
                    row["note"] = "\n".join(pending)
                    pending = []
                rows.append(row)
        if pending and rows:
            tail = [rows[-1]["note"]] if rows[-1].get("note") else []
            rows[-1]["note"] = "\n".join(tail + pending)
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
    if unmatched_titles:
        print("警告: ステージ番号を読めなかった見出し: %s" % "、".join(unmatched_titles))
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
