extends SceneTree
##
## チュートリアルの進行（区画1→6→本編）を通して確かめる。
##
##   godot --headless --path . --script res://tools/check_tutorial_flow.gd
##
## 本物の Main.tscn を動かし、各区画を強制クリア（判定アイテムに触れたのと
## 同じ経路）してメッセージ→選択→次の区画、という流れを踏ませる。
## 途中で1回「もう一度やる」も選び、同じ区画へ戻ることを見る。
## 最後は区画6のあとに本編のステージ1が読み込まれるところまで。
##
## 遊んで越えられるかは別の話（tools/playtest_tutorial.gd）。ここで見るのは
## 進行の配線だけ。

func _initialize() -> void:
	# タイトルの TUTORIAL から入ったのと同じ状態にする。
	# --script で走らせたこのスクリプトは自動読み込み(autoload)より先に
	# 読まれるので、SaveGame という名前では引けない。ノードとして取る
	var save := get_root().get_node_or_null(^"SaveGame")
	if save == null:
		print("NG  SaveGame が見つからない")
		quit(1)
		return
	save.set("tutorial_requested", true)
	save.set("continue_requested", false)

	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	# 会話と見出しは進行の確認には不要。見出しはツリーを止めるので外す
	main.set("skip_cutscenes", true)
	main.set("stage_title_duration", 0.0)
	main.set("debug_shortcuts", false)
	get_root().add_child(main)

	var d := Driver.new()
	d.game = main
	get_root().add_child(d)


class Driver extends Node:
	var game: Node
	var frame := 0
	var step := 0
	var waited := 0
	var fails := 0
	var lines: Array = []
	## 区画2では「もう一度やる」を選んで、同じ区画に戻るかを見る
	var retried := false
	## A / D で選択が動くかの確認は最初の1回だけ
	var focus_checked := false
	var loaded_stage := -99


	func _ready() -> void:
		game.stage_loaded.connect(func(index: int, _s: Node) -> void: loaded_stage = index)


	func _ng(msg: String) -> void:
		fails += 1
		lines.append("  NG  %s" % msg)


	func _ok(msg: String) -> void:
		lines.append("  ok  %s" % msg)


	func _stage() -> Node:
		return game.get("_stage")


	func _index() -> int:
		return int(game.get("_tutorial_index"))


	func _ui() -> Node:
		return game.get_node_or_null(^"TutorialUI")


	func _physics_process(_delta: float) -> void:
		frame += 1
		if frame < 10:
			return
		waited += 1
		if waited > 600:
			_ng("step %d で止まった（600フレーム待っても進まない）" % step)
			_report()
			return
		match step:
			0: _begin()
			1: _clear_current()
			2: _read_message()
			3: _choose()
			4: _after_choice()
			5: _check_main()


	func _next(to: int) -> void:
		step = to
		waited = 0


	## チュートリアル面が区画1で始まっているか
	func _begin() -> void:
		var stage := _stage()
		if stage == null:
			return
		if not (stage is TutorialStage):
			_ng("チュートリアル面が読み込まれていない（%s）" % stage.name)
			_report()
			return
		var tut := stage as TutorialStage
		if tut.section_count() != 6:
			_ng("区画が %d 個（6個のはず）" % tut.section_count())
		if _index() != 0 or tut.active_index() != 0:
			_ng("区画1から始まっていない（_tutorial_index=%d, active=%d）"
				% [_index(), tut.active_index()])
		else:
			_ok("区画1 '%s' から開始" % tut.get_active_section().get_display_title())
		# 有効なのは1つだけか
		_check_only_one_active(tut)
		_check_background(tut)
		step = 91          # 待ちの間、状態機械を止める
		_check_tutorial_screen(tut)


	## 背景と説明を続けて見る。どちらもプレイヤーを飛ばすので順番に行う
	func _check_tutorial_screen(tut: TutorialStage) -> void:
		await _check_bg_parallax(tut)
		_check_hint_switch(tut)


	## 画面上部の説明が、プレイヤーの居る場所で切り替わるか。
	## 区画1の説明範囲へプレイヤーを飛ばして、文章が変わることを見る
	func _check_hint_switch(tut: TutorialStage) -> void:
		var sec := tut.get_active_section()
		var ui := _ui()
		var player := game.get("player") as Node2D
		if sec == null or ui == null or player == null:
			_ng("説明の確認ができない（区画かUIかプレイヤーが無い）")
			_next(1)
			return
		var spawn: Vector2 = sec.get_spawn_position()
		await _settle()
		var at_spawn: String = ui.call("hint_text")
		if at_spawn != sec.hint:
			_ng("開始位置で既定の説明が出ていない（%s）" % at_spawn)
		else:
			_ok("開始位置: %s" % at_spawn)
		for h in sec.get_hints():
			player.call("teleport", h.get_rect().get_center())
			await _settle()
			var now: String = ui.call("hint_text")
			if now != h.text:
				_ng("%s の範囲に入っても説明が変わらない（%s）" % [h.name, now])
			else:
				_ok("%s の範囲: %s" % [h.name, h.text])
		player.call("teleport", spawn)
		await _settle()
		var back: String = ui.call("hint_text")
		if back != sec.hint:
			_ng("範囲から出ても既定の説明に戻らない（%s）" % back)
		else:
			_ok("範囲から出ると既定の説明に戻る")
		_next(1)


	## 位置を変えたあと、Game が説明を見直すまで待つ
	func _settle() -> void:
		await get_tree().physics_frame
		await get_tree().physics_frame


	## 背景。チュートリアル面は自前の背景(マトリックス雨)を持つので、
	## Main の共通背景は隠れていないといけない。出たままだと雨が見えない
	func _check_background(tut: TutorialStage) -> void:
		var world := game.get_node_or_null(^"Background") as Node2D
		if world == null:
			_ng("Main に共通背景(Background)が無い")
			return
		if world.visible:
			_ng("チュートリアル中なのに共通背景が出たまま")
		var rain := tut.get_node_or_null(^"MatrixBg/Rain") as ColorRect
		if rain == null:
			_ng("チュートリアル面に背景(MatrixBg/Rain)が無い")
		elif (rain.material as ShaderMaterial) == null:
			_ng("背景にシェーダーが入っていない")
		elif (rain.material as ShaderMaterial).get_shader_parameter("glyph_atlas") == null:
			_ng("背景の文字アトラス(glyph_atlas)が未設定")
		else:
			_ok("背景はマトリックス雨（共通背景は隠れている）")


	## 背景がカメラに連動してずれるか。
	## 背景は画面に貼り付いているので、ずれないと進んでも止まって見える
	func _check_bg_parallax(tut: TutorialStage) -> void:
		var rain := tut.get_node_or_null(^"MatrixBg/Rain") as ColorRect
		var player := game.get("player") as Node2D
		var sec := tut.get_active_section()
		if rain == null or player == null or sec == null:
			return
		var mat := rain.material as ShaderMaterial
		if mat == null:
			return
		waited = 0                       # 見張りの時計を止めておく（長めに掛かる）
		var home: Vector2 = player.global_position
		# 判定アイテムの上に飛ばすとその場でクリアになってしまうので、
		# 区画の右寄りの、何も無いところへ飛ばす
		var cell: Rect2 = tut.section_bounds(tut.active_index())
		var far := Vector2(cell.position.x + cell.size.x * 0.7, home.y)
		await _settle()
		var before: Vector2 = mat.get_shader_parameter("parallax_offset")
		player.call("teleport", far)
		var after := before
		for i in 600:                    # カメラの追従が落ち着くまで
			await get_tree().physics_frame
			after = mat.get_shader_parameter("parallax_offset")
			if absf(after.x - before.x) > 0.2:
				break
		waited = 0
		# 縦も見る。カメラが縦に動いたぶん、背景も縦に流れないといけない。
		# 流れないと「地面だけが跳ねている」ように見える。
		# ヘッドレスではカメラが枠の中央に固定されて縦に動かないので、
		# そのときは見送る（背景の問題ではない）
		var cam := player.get_node_or_null(^"Camera2D") as Camera2D
		var cam_before: float = cam.get_screen_center_position().y if cam else 0.0
		player.call("teleport", Vector2(home.x, home.y - 400.0))
		var up := before
		var cam_moved := 0.0
		for i in 600:
			await get_tree().physics_frame
			if cam:
				cam_moved = maxf(cam_moved,
					absf(cam.get_screen_center_position().y - cam_before))
			var now_y: Vector2 = mat.get_shader_parameter("parallax_offset")
			if absf(now_y.y - before.y) > absf(up.y - before.y):
				up = now_y
			if cam_moved > 40.0 and absf(up.y - before.y) > 0.3:
				break
		player.call("teleport", home)
		var span_y := float(rain.get("camera_span_y"))
		if span_y <= 0.0:
			span_y = float(rain.get("camera_span"))
		if cam_moved <= 1.0:
			lines.append("  --  この環境ではカメラが縦に動かないので、縦の確認は見送り")
		elif absf(up.y - before.y) < cam_moved / span_y * 0.3:
			_ng("カメラが縦に %.0f px 動いたのに背景が追わない（%.2f → %.2f）"
				% [cam_moved, before.y, up.y])
		else:
			_ok("カメラが縦に %.0f px 動き、背景も縦に流れた（%.2f → %.2f）"
				% [cam_moved, before.y, up.y])
		waited = 0
		# 右へ進んだら背景は左へ流れる＝ずれは小さくなる向き
		var moved: float = after.x - before.x
		if absf(moved) <= 0.2:
			_ng("右へ進んでも背景がずれない（%.2f → %.2f）" % [before.x, after.x])
		elif moved > 0.0:
			_ng("背景がカメラと同じ向きに流れている（%.2f → %.2f）" % [before.x, after.x])
		else:
			_ok("右へ進むと背景は左へ流れた（%.2f → %.2f）" % [before.x, after.x])
		await _settle()


	func _check_only_one_active(tut: TutorialStage) -> void:
		var on := 0
		var sections := tut.get_sections()
		for i in sections.size():
			var item := sections[i].get_item()
			if item and item.monitoring:
				on += 1
				if i != tut.active_index():
					_ng("区画 %d の判定アイテムが有効のまま" % (i + 1))
		if on != 1:
			_ng("判定アイテムが %d 個有効（1個のはず）" % on)


	## 今の区画を強制クリア（アイテムに触れたのと同じ経路）
	func _clear_current() -> void:
		var tut := _stage() as TutorialStage
		if tut == null:
			return
		_check_only_one_active(tut)
		game.call("clear_stage")
		_next(2)


	## メッセージボックスが出ているか
	func _read_message() -> void:
		var ui := _ui()
		if ui == null:
			return
		if not ui.call("is_open"):
			return
		_ok("区画 %d: メッセージが出た" % (_index() + 1))
		ui.call("advance")          # ボタンを押して選択へ
		_next(3)


	## 選択肢が出たら選ぶ
	func _choose() -> void:
		var ui := _ui()
		if ui == null or not ui.call("is_open"):
			_ng("選択の前にメッセージが閉じた")
			_report()
			return
		if not focus_checked:
			focus_checked = true
			step = 90          # 待ちの間、状態機械を止める
			_check_ad_focus()
			return
		var want_retry := _index() == 1 and not retried
		if want_retry:
			retried = true
		ui.call("choose", want_retry)
		_next(4)


	## A（pogo_left）/ D（pogo_right）で選択が動くか。
	## 矢印キーは ui_left / ui_right としてボタン側が拾うので、ここでは A D だけ見る
	func _check_ad_focus() -> void:
		await _tap(&"pogo_left")
		var left_focus := _focus_text()
		if left_focus != "もう一度やる":
			_ng("A で「もう一度やる」に移らない（今: %s）" % left_focus)
		else:
			_ok("A で「もう一度やる」へ移った")
		await _tap(&"pogo_right")
		var right_focus := _focus_text()
		if right_focus != "次へ進む":
			_ng("D で「次へ進む」に移らない（今: %s）" % right_focus)
		else:
			_ok("D で「次へ進む」へ移った")
		_next(3)


	## 押して離す。InputEventAction なら実際の入力と同じ道を通る
	func _tap(action: StringName) -> void:
		var down := InputEventAction.new()
		down.action = action
		down.pressed = true
		Input.parse_input_event(down)
		await get_tree().physics_frame
		var up := InputEventAction.new()
		up.action = action
		up.pressed = false
		Input.parse_input_event(up)
		await get_tree().physics_frame


	func _focus_text() -> String:
		var c := get_viewport().gui_get_focus_owner()
		if c is Button:
			return (c as Button).text
		return "(なし)"


	## 選んだ結果、狙った区画に移ったか
	func _after_choice() -> void:
		var ui := _ui()
		if ui and ui.call("is_open"):
			return                  # まだ閉じていない
		var tut := _stage() as TutorialStage
		if tut == null:
			# 本編へ移った
			_next(5)
			return
		var now := _index()
		if tut.active_index() != now:
			return                  # 切り替え中
		if retried and now == 1 and not lines.has("  ok  区画2: もう一度やるで同じ区画に戻った"):
			_ok("区画2: もう一度やるで同じ区画に戻った")
			_next(1)
			return
		_ok("区画 %d へ進んだ" % (now + 1))
		_next(1)


	## 区画6のあと、本編のステージ1が始まるか
	func _check_main() -> void:
		var stage := _stage()
		if stage == null:
			return
		if stage is TutorialStage:
			return
		if loaded_stage != 0:
			_ng("本編の1面ではなくステージ %d が読み込まれた" % (loaded_stage + 1))
		else:
			_ok("区画6のあと本編ステージ1へ繋がった（%s）" % stage.get_display_name())
		if bool(game.get("_in_tutorial")):
			_ng("本編に入ったのに _in_tutorial が true のまま")
		var world := game.get_node_or_null(^"Background") as Node2D
		if world and not world.visible:
			_ng("本編に戻ったのに共通背景が隠れたまま")
		elif world:
			_ok("本編では共通背景が戻った")
		_report()


	func _report() -> void:
		print("")
		print("=== チュートリアルの進行 ===")
		for l in lines:
			print(l)
		print("")
		if fails == 0:
			print("=== 進行の確認: 問題なし ===")
		else:
			print("=== 進行の確認: %d 件の問題 ===" % fails)
		get_tree().quit(1 if fails > 0 else 0)
