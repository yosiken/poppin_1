extends SceneTree
##
## クレジットの中身と流れを確かめる。
##
##   godot --headless --path . --script res://tools/check_credits.gd
##
## 見るもの:
##   - resources/credits.tres が読め、1画面ぶんずつ中身が入っているか
##   - Main.tscn の Game に割り当てられているか（割り当て漏れでED後に何も出ない）
##   - タイトル画面の CREDITS から流せるか
##   - 実際に最後まで流して、1人ずつ順に出るか
##
## 待ち時間は短くした複製で流す。文章と並び順を見るのが目的で、
## 本番の尺を測るものではない
##

const DATA_PATH := "res://resources/credits.tres"

var fails := 0


func _initialize() -> void:
	var data := load(DATA_PATH) as CreditsData
	if data == null:
		_ng("%s が読めない（CreditsData ではない）" % DATA_PATH)
		_report()
		return

	print("--- クレジットの中身 ---")
	if data.entries.is_empty():
		_ng("1件も入っていない")
	if data.background == null:
		print("  --  背景が未設定（黒一色で流れる）")
	if data.bgm == null:
		print("  --  曲が未設定（無音で流れる）")
	for i in data.entries.size():
		var e := data.entries[i]
		if e == null:
			_ng("%d 枚目が空" % (i + 1))
			continue
		if e.role.strip_edges() == "" and e.person.strip_edges() == "":
			_ng("%d 枚目に役割も名前も無い" % (i + 1))
		else:
			_ok("%2d  %s" % [i + 1, e.to_line()])

	_check_wired()
	_check_title(data)


## Main.tscn の Game に繋がっているか
func _check_wired() -> void:
	print("--- Main.tscn ---")
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		_ng("Main.tscn が読めない")
		return
	var state := packed.get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == "credits":
			var value: Variant = state.get_node_property_value(0, i)
			if value is CreditsData:
				_ok("Game.credits に割り当て済み")
			else:
				_ng("Game.credits の中身が CreditsData ではない")
			return
	_ng("Game.credits が未割り当て（ED のあと何も出ない）")


## タイトル画面の CREDITS から流せるか。
## ボタンを実際に押して、クレジットが始まってツリーが止まるところまで見る。
## 流し終わったら、続けて通しの確認(_play)へ渡す
func _check_title(data: CreditsData) -> void:
	print("--- タイトルの CREDITS ---")
	var packed := load("res://scenes/Title.tscn") as PackedScene
	if packed == null:
		_ng("Title.tscn が読めない")
		_play(data)
		return
	var title := packed.instantiate()
	get_root().add_child(title)

	# _initialize の時点ではまだツリーに入っていないので、メニューはまだ無い。
	# ボタン探しは最初のフレーム（TitleWatch）に回す
	var watch := TitleWatch.new()
	watch.title = title
	watch.data = data
	watch.owner_script = self
	get_root().add_child(watch)


## node 以下から、その文字そのままのボタンを探す
func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for c in node.get_children():
		var found := _find_button(c, text)
		if found:
			return found
	return null


## ボタンを押して、始まる→止まる→戻るまでを見る
class TitleWatch extends Node:
	var title: Node
	var data: CreditsData
	var owner_script: SceneTree
	var button: Button
	var frames := 0
	var pressed := false
	var saw_playing := false

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_delta: float) -> void:
		frames += 1
		if not pressed:
			pressed = true
			button = owner_script.call("_find_button", title, "CREDITS")
			if button == null:
				owner_script.call("_ng", "メニューに CREDITS のボタンが無い")
				_finish()
				return
			if button.disabled or button.focus_mode == Control.FOCUS_NONE:
				owner_script.call("_ng", "CREDITS のボタンが押せない（disabled / フォーカス不可）")
			else:
				owner_script.call("_ok", "メニューに CREDITS がある")
			button.pressed.emit()
			return

		var ui := title.get("_credits") as Credits
		if not saw_playing:
			if ui and ui.is_playing():
				saw_playing = true
				owner_script.call("_ok", "CREDITS を押したらクレジットが始まった")
				if not get_tree().paused:
					owner_script.call("_ng", "クレジット中もツリーが止まっていない")
				_skip_rest()
			elif frames > 300:
				owner_script.call("_ng", "CREDITS を押してもクレジットが始まらない")
				_finish()
			return

		if ui and not ui.is_playing():
			if get_tree().paused:
				owner_script.call("_ng", "クレジットのあともツリーが止まったまま")
			else:
				owner_script.call("_ok", "終わったらタイトルへ戻った")
			_finish()
		elif frames > 3000:
			owner_script.call("_ng", "Enter で飛ばしても終わらない")
			_finish()

	## 本物の尺(20秒ほど)を待つ必要は無いので Enter で飛ばす。
	## 飛ばしても暗転と曲の始末は通るので、戻りの確認はそのまま効く
	func _skip_rest() -> void:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ENTER
		ev.pressed = true
		get_tree().root.push_input(ev)

	func _finish() -> void:
		set_process(false)
		get_tree().paused = false
		title.queue_free()
		owner_script.call("_play", data)
		queue_free()


## 実際に最後まで流して、出た順を記録する
func _play(data: CreditsData) -> void:
	print("--- 通して流す ---")
	var fast := data.duplicate() as CreditsData
	fast.hold = 0.05
	fast.fade = 0.0
	fast.open_fade = 0.0
	fast.bgm_fade = 0.0
	fast.closing_hold = 0.05
	# 1枚ごとの指定も短くする。duplicate() は中の CreditEntry を共有するので
	# 本物を書き換えないよう、作り直して差し替える
	var copies: Array[CreditEntry] = []
	for e in data.entries:
		var c := e.duplicate() as CreditEntry
		c.hold = 0.0
		copies.append(c)
	fast.entries = copies

	var ui := Credits.new()
	get_root().add_child(ui)

	var watch := Watch.new()
	watch.ui = ui
	watch.want = data
	watch.fast = fast
	watch.owner_script = self
	get_root().add_child(watch)
	# 再生は最初のフレームから。_initialize の時点ではまだツリーに入っていない


class Watch extends Node:
	var ui: Credits
	var want: CreditsData
	var fast: CreditsData
	var owner_script: SceneTree
	var seen: Array[String] = []
	var frames := 0
	var started := false

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_delta: float) -> void:
		frames += 1
		if not started:
			started = true
			ui.play(fast)
			return
		if frames > 20000:
			owner_script.call("_ng", "流し終わらない（止まっている）")
			owner_script.call("_report")
			return
		var now := ui.current_text()
		if now != "" and (seen.is_empty() or seen[-1] != now):
			seen.append(now)
		if frames > 5 and not ui.is_playing():
			_done()

	func _done() -> void:
		set_process(false)
		var want_list: Array[String] = []
		for e in want.entries:
			want_list.append(e.person if e.person != "" else e.role)
		if want.closing.strip_edges() != "":
			want_list.append(want.closing)
		if seen == want_list:
			owner_script.call("_ok", "%d 画面が並び順どおりに出た" % seen.size())
		else:
			owner_script.call("_ng", "出た順が違う\n     出た: %s\n     はず: %s"
				% [", ".join(seen), ", ".join(want_list)])
		if get_tree().paused:
			owner_script.call("_ng", "流し終わってもツリーが止まったまま")
		owner_script.call("_report")


func _ng(msg: String) -> void:
	fails += 1
	print("  NG  %s" % msg)


func _ok(msg: String) -> void:
	print("  ok  %s" % msg)


func _report() -> void:
	print("")
	if fails == 0:
		print("=== クレジットの確認: 問題なし ===")
	else:
		print("=== クレジットの確認: %d 件の問題 ===" % fails)
	quit(1 if fails > 0 else 0)
