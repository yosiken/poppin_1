extends SceneTree
##
## resources/cutscene/scenario.json からイベントの .tres を生成する開発用ツール。
##
##   python tools/scenario_to_json.py resources/dotonbori-isekai-scenario-v2.md
##   godot --headless --path <project> --script res://tools/make_cutscenes.gd
##
## 台本が正なのは speaker / text / speaking の3つだけで、それ以外（背景・立ち絵・
## 間・スライドインなど、CutsceneEditor で入れる演出）は既存の .tres から引き継ぐ。
## なので台本を直したあとに何度流しても、作りこんだ演出は消えない。
##
## 引き継ぎはコマの本文を手掛かりに突き合わせる。台本側で本文を書き換えたコマは
## 相手が見つからないので演出が落ちる。実行後に出る「引き継げなかった」の警告を見て、
## そのイベントだけ CutsceneEditor で当て直すこと。
##
## CutsceneEditor で挿したコマ（CutsceneLine.inserted）は台本に相手が居ないので、
## 直前にあった台本のコマを手掛かりに元の位置へ戻す。
##
## uid も引き継ぐので、ステージシーン側の参照は張り直さなくてよい。
##

const JSON_PATH := "res://resources/cutscene/scenario.json"
const OUT_DIR := "res://resources/cutscene"

## OB（主人公）= 右、カニエナガ（ナビゲーター）= 左
const TEX_RIGHT := "res://resources/texture/OB_a.png"
const TEX_LEFT := "res://resources/texture/kanie_a.png"

## 突き合わせで決まった「前回のコマ j は今回の何番目か」。_inherit が埋め、_reinsert が使う
var _new_at: Dictionary[int, int] = {}


func _initialize() -> void:
	var file := FileAccess.open(JSON_PATH, FileAccess.READ)
	if file == null:
		push_error("scenario.json がありません。先に tools/scenario_to_json.py を実行してください")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("scenario.json を解釈できません")
		quit(1)
		return

	var left := load(TEX_LEFT)
	var right := load(TEX_RIGHT)
	var keys: Array = parsed.keys()
	keys.sort()

	for key in keys:
		var event: Dictionary = parsed[key]
		var data := CutsceneData.new()
		var lines: Array[CutsceneLine] = []
		for row in event["rows"]:
			var l := CutsceneLine.new()
			l.speaker = row.get("speaker", "")
			l.text = row.get("text", "")
			l.note = row.get("note", "")
			# side が left / right のどちらでもない話者（画面に流れるコメントなど）は
			# どちらの立ち絵も明るくしない
			var side: String = row.get("side", "")
			if side == "left":
				l.speaking = CutsceneLine.Side.LEFT
			elif side == "right":
				l.speaking = CutsceneLine.Side.RIGHT
			else:
				l.speaking = CutsceneLine.Side.NONE
			if row.get("show_left", false):
				l.left = left
			if row.get("show_right", false):
				l.right = right
			lines.append(l)

		var path := "%s/%s.tres" % [OUT_DIR, key]
		var old: CutsceneData = null
		if FileAccess.file_exists(path):
			old = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as CutsceneData
		var lost := _inherit(old, lines)
		lines = _reinsert(old, lines)

		data.lines = lines
		data.clear_on_finish = old.clear_on_finish if old else true
		# 保存し直すと uid が振り直され、ステージシーンの ext_resource 参照が
		# 古い uid を指したままになる。上書き前の uid を控えて書き戻す
		var old_uid := _read_uid(path)
		if old_uid == "":
			# 新規ぶんもここで uid を決めておく。エディタ任せにすると
			# 環境ごとに別の値が振られて .tscn の差分が揺れる
			old_uid = ResourceUID.id_to_text(ResourceUID.create_id())
		var err := ResourceSaver.save(data, path)
		if err == OK:
			_write_uid(path, old_uid)
		var note := "" if lost == 0 else "  ※演出を引き継げなかったコマ %d 件" % lost
		print("%-18s %2d コマ -> %s%s" % [key, lines.size(), error_string(err), note])

	print("--- 演出メモ（未実装。SE を足すときの手掛かり）---")
	for key in keys:
		var notes: Array = parsed[key].get("notes", [])
		for n in notes:
			print("  [%s] %s" % [key, n])
	quit()


## 前回の .tres に入っている演出を、台本から作り直したコマへ移す。
## 台本が正なのは speaker / text / speaking だけなので、それ以外を上書きする。
##
## 突き合わせはまず同じ位置、本文が違えば本文が一意に一致するコマを探す。
## 同じ本文が複数あるときは当てずっぽうを避けて引き継がない。
## 戻り値は、演出を持っていたのに移し先が無かったコマの数
func _inherit(old: CutsceneData, lines: Array[CutsceneLine]) -> int:
	_new_at.clear()
	if old == null:
		return 0
	var used: Dictionary[int, bool] = {}
	for i in lines.size():
		var at := _match(old, lines[i].text, i, used)
		if at < 0:
			continue
		used[at] = true
		_new_at[at] = i
		_copy_fx(old.lines[at], lines[i])

	var lost := 0
	for j in old.lines.size():
		var l := old.lines[j]
		if l and not l.inserted and not used.has(j) and _has_fx(l):
			lost += 1
	return lost


## CutsceneEditor で手を挿したコマ（inserted）を、元の並びのまま戻す。
##
## 置き場所は「直前にあった台本のコマ」で決める。台本にコマが増減しても、
## 隣り合っていた台本のコマに付いて動くので、挿したコマが迷子にならない。
## 台本の先頭より前にあったものは先頭へ戻す
func _reinsert(old: CutsceneData, lines: Array[CutsceneLine]) -> Array[CutsceneLine]:
	if old == null:
		return lines
	var buckets: Dictionary[int, Array] = {}
	var anchor := -1                      # -1 は「台本のコマより前」
	for j in old.lines.size():
		var l := old.lines[j]
		if l == null:
			continue
		if not l.inserted:
			if _new_at.has(j):
				anchor = _new_at[j]
			continue
		if not buckets.has(anchor):
			buckets[anchor] = []
		buckets[anchor].append(l)
	if buckets.is_empty():
		return lines

	var out: Array[CutsceneLine] = []
	for l: CutsceneLine in buckets.get(-1, []):
		out.append(l)
	for i in lines.size():
		out.append(lines[i])
		for l: CutsceneLine in buckets.get(i, []):
			out.append(l)
	return out


func _match(old: CutsceneData, text: String, index: int, used: Dictionary) -> int:
	# 手で挿したコマは台本に相手が居ない。突き合わせの対象から外す
	if index < old.lines.size() and old.lines[index] and not old.lines[index].inserted \
			and not used.has(index) and old.lines[index].text == text:
		return index
	var hit := -1
	for j in old.lines.size():
		if used.has(j) or old.lines[j] == null or old.lines[j].inserted:
			continue
		if old.lines[j].text != text:
			continue
		if hit >= 0:
			return -1               # 同じ本文が複数ある
		hit = j
	return hit


func _copy_fx(src: CutsceneLine, dst: CutsceneLine) -> void:
	dst.left = src.left
	dst.right = src.right
	dst.clear_left = src.clear_left
	dst.clear_right = src.clear_right
	dst.background = src.background
	dst.clear_background = src.clear_background
	dst.slide_in = src.slide_in
	dst.auto_advance = src.auto_advance
	dst.delay = src.delay


## 生成しただけの状態から手を入れてあるか。
## 立ち絵の左右はツールも入れるので、ここでは「手で足す類」だけを見る
func _has_fx(l: CutsceneLine) -> bool:
	return l.background != null or l.clear_background \
		or l.clear_left or l.clear_right or not l.slide_in \
		or l.auto_advance > 0.0 or l.delay > 0.0


## .tres の先頭行から uid="uid://..." を取り出す。無ければ空文字
func _read_uid(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var head := f.get_line()
	var re := RegEx.create_from_string('uid="(uid://[^"]+)"')
	var m := re.search(head)
	return m.get_string(1) if m else ""


## 保存直後の .tres の uid を、上書き前の値に差し替える
func _write_uid(path: String, uid: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return
	var head_end := text.find("\n")
	if head_end < 0:
		return
	var head := text.substr(0, head_end)
	var re := RegEx.create_from_string('uid="uid://[^"]+"')
	if re.search(head):
		head = re.sub(head, 'uid="%s"' % uid)
	else:
		# ResourceSaver は uid を持たないリソースには uid 属性ごと書かないので、
		# 閉じ括弧の手前に差し込む
		var close := head.rfind("]")
		if close < 0:
			return
		head = head.substr(0, close) + ' uid="%s"' % uid + head.substr(close)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(head + text.substr(head_end))
	f.close()
	var id := ResourceUID.text_to_id(uid)
	if ResourceUID.has_id(id):
		ResourceUID.set_id(id, path)
	else:
		ResourceUID.add_id(id, path)
