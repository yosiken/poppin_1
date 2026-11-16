extends SceneTree
##
## ステージBGM と イベント(ADV) の音の主導権を確かめる。
##
##   godot --headless --path . --script res://tools/check_stage_bgm.gd
##
## 決めごとは2つ。
##   - イベントが曲を止め忘れたまま終えても、ステージの最初はステージBGM になる
##   - 次のイベントが始まる前にステージBGM は止まる
##
## BGM プレイヤーは Game と Cutscene で共用しているので、イベントの
## 止めかけのフェードが後から効いて、鳴らし始めたステージBGM を消してしまう
## 事故が起きやすい。そこを重点的に見る。
##
## 音が出ているかそのものではなく、配線を見るためのもの。
##

var fails := 0


func _initialize() -> void:
	var save := get_root().get_node_or_null(^"SaveGame")
	if save:
		save.set("tutorial_requested", false)
		save.set("continue_requested", false)

	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	main.set("skip_cutscenes", true)         # 会話そのものはここでは関係ない
	main.set("stage_title_duration", 0.0)
	main.set("debug_shortcuts", false)
	get_root().add_child(main)

	var d := Driver.new()
	d.game = main
	d.owner_script = self
	get_root().add_child(d)


func _ng(msg: String) -> void:
	fails += 1
	print("  NG  %s" % msg)


func _ok(msg: String) -> void:
	print("  ok  %s" % msg)


func _report() -> void:
	print("")
	if fails == 0:
		print("=== ステージBGM の確認: 問題なし ===")
	else:
		print("=== ステージBGM の確認: %d 件の問題 ===" % fails)
	quit(1 if fails > 0 else 0)


class Driver extends Node:
	var game: Node
	var owner_script: SceneTree
	var step := 0
	var wait := 0.0
	var player: AudioStreamPlayer
	var cutscene: Node
	var stage_track: AudioStream
	var other_track: AudioStream

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _ng(m: String) -> void: owner_script.call("_ng", m)
	func _okm(m: String) -> void: owner_script.call("_ok", m)

	## 秒を数える。headless の fps に左右されないよう delta で待つ
	func _hold(sec: float, delta: float) -> bool:
		wait += delta
		if wait < sec:
			return false
		wait = 0.0
		return true

	func _process(delta: float) -> void:
		match step:
			0:
				player = game.get("bgm_player")
				cutscene = game.get("cutscene")
				var list: Array = game.get("stage_bgm")
				if player == null:
					_ng("Game に BgmPlayer が無い")
					_finish()
					return
				if list.is_empty():
					_ng("stage_bgm が空。ステージの曲が割り当てられていない")
					_finish()
					return
				stage_track = list[0]
				for t in list:
					if t != stage_track:
						other_track = t
						break
				step = 1
			1:
				# ステージ1を読み終えるまで待つ
				if not _hold(0.5, delta):
					return
				print("--- ステージを読み込んだ直後 ---")
				if player.playing and player.stream == stage_track:
					_okm("ステージBGM が鳴っている")
				else:
					_ng("ステージBGM が鳴っていない（stream=%s playing=%s）"
						% [player.stream, player.playing])
				step = 2
			2:
				print("--- イベントが曲を止め忘れたまま終わった場合 ---")
				# イベントが別の曲を鳴らしたまま、止めるフェードも動かしたまま抜けた状態
				cutscene.call("_start_bgm", other_track, 0.0)
				cutscene.call("_stop_bgm", 3.0)
				if not player.playing:
					_ng("下ごしらえに失敗（イベントの曲が鳴っていない）")
				game.call("_start_stage_bgm", 0)
				if player.playing and player.stream == stage_track:
					_okm("その場でステージBGM に戻った")
				else:
					_ng("ステージBGM に戻らない（stream=%s playing=%s）"
						% [player.stream, player.playing])
				step = 3
			3:
				# イベントのフェードが後から効いて消さないか。止まる尺より長く待つ
				if not _hold(3.5, delta):
					return
				if player.playing and player.stream == stage_track \
						and absf(player.volume_db) < 0.01:
					_okm("イベントのフェードに後から消されない")
				else:
					_ng("後から消された（stream=%s playing=%s volume=%.1fdB）"
						% [player.stream, player.playing, player.volume_db])
				step = 4
			4:
				print("--- 次のイベントが始まる前 ---")
				game.call("_stop_stage_bgm")
				step = 5
			5:
				if not _hold(2.0, delta):
					return
				if player.playing:
					_ng("イベントの前にステージBGM が止まらない（stream=%s）" % player.stream)
				else:
					_okm("ステージBGM が止まった")
				if absf(player.volume_db) < 0.01:
					_okm("音量が 0dB に戻っている（次に鳴らす曲が無音にならない）")
				else:
					_ng("音量が %.1fdB のまま。次に鳴らす曲が絞られる" % player.volume_db)
				_finish()

	func _finish() -> void:
		set_process(false)
		owner_script.call("_report")
