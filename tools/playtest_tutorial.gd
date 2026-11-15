extends SceneTree
##
## チュートリアル面の各区画を自動で遊んでみて、判定アイテムに届くかを確かめる。
##
##   godot --headless --path . --script res://tools/playtest_tutorial.gd
##
## 本物の地形の上で本物の PogoPlayer を決め打ちの入力で動かす。
## 人が遊んだときの感触までは分からないが、「そもそも届かない」寸法に
## なっていないかはこれで分かる。
##
## 入力の決め打ち:
##   hold_right   … 右を押しっぱなし（＝最大まで傾ける）
##   hold_charge  … SPACE 押しっぱなし
##   bounce_cycle … 0 以外なら、その回数に1回だけ右を押す
##                  （「同じ足場で跳ね直してから進む」を真似る）
##   tilt_cap     … 傾きの上限（度）。人は倒し切らないので、それを真似る
##

const STAGE_PATH := "res://scenes/stages/StageTutorial.tscn"

# 区画ごとの入力。区画の順番と同じ並び
#  [右押し, 溜め押し, 何回に1回右を押すか(0=常時), 傾き上限, 制限秒]
const PLAN := [
	[true, false, 0, 35.0, 40.0],     # 1 基本操作
	[true, true, 0, 35.0, 40.0],      # 2 ジャンプの練習
	[true, true, 0, 35.0, 60.0],      # 3 押しっぱなしで連続ジャンプ
	[true, true, 3, 20.0, 90.0],      # 4 溜めジャンプ（跳ね直してから進む）
	[true, true, 0, 25.0, 60.0],      # 5 跳ぶ場所で変わる
	[true, true, 0, 25.0, 60.0],      # 6 総合
]


func _initialize() -> void:
	var world := Node2D.new()
	get_root().add_child(world)

	var stage := (load(STAGE_PATH) as PackedScene).instantiate() as TutorialStage
	world.add_child(stage)

	var player := PogoPlayer.new()
	player.stats = load("res://resources/pogo_stats_default.tres")
	player.debug_draw = false
	world.add_child(player)

	var d := Driver.new()
	d.player = player
	d.stage = stage
	world.add_child(d)


class Driver extends Node:
	var player: PogoPlayer
	var stage: TutorialStage

	var idx := -1
	var frame := 0
	var start_frame := 0
	var bounces := 0
	var best := Vector2.ZERO
	var done := false
	var lines: Array = []
	var fails := 0

	var target := Vector2.ZERO
	var reach := 152.0           # アイテムの判定半径 + 体の分
	var floor_y := 0.0           # これより下は落下死あつかい
	var plan: Array = []


	func _ready() -> void:
		player.bounced.connect(func(_s: float, _n: Vector2) -> void: bounces += 1)
		_next()


	func _next() -> void:
		_release()
		idx += 1
		var sections := stage.get_sections()
		if idx >= sections.size():
			_report()
			return
		stage.activate(idx)
		var sec := sections[idx]
		var item := sec.get_item()
		if item == null:
			lines.append("NG   %d %s  判定アイテムが無い" % [idx + 1, sec.get_display_title()])
			fails += 1
			_next.call_deferred()
			return
		plan = PLAN[idx] if idx < PLAN.size() else [true, true, 0, 30.0, 60.0]
		target = item.global_position
		reach = item.radius + 72.0
		floor_y = stage.section_bounds(idx).end.y
		player.teleport(sec.get_spawn_position())
		best = sec.get_spawn_position()
		bounces = 0
		start_frame = frame
		done = false


	func _release() -> void:
		for a in [&"pogo_charge", &"pogo_right"]:
			if Input.is_action_pressed(a):
				Input.action_release(a)


	func _physics_process(_delta: float) -> void:
		if done or idx < 0 or plan.is_empty():
			return
		frame += 1
		_hold(&"pogo_charge", bool(plan[1]))
		var cycle := int(plan[2])
		var want_right: bool = bool(plan[0])
		if cycle > 0:
			# cycle 回のバウンドのうち最後の1回だけ傾ける＝その場で跳ね直してから進む
			want_right = want_right and (bounces % cycle == cycle - 1)
		_hold(&"pogo_right", want_right)
		player.tilt_deg = minf(player.tilt_deg, float(plan[3]))

		var pos := player.global_position
		if pos.x > best.x:
			best = pos
		if pos.distance_to(target) <= reach:
			_finish("届いた", true)
		elif pos.y > floor_y:
			_finish("落下死", false)
		elif float(frame - start_frame) / 60.0 > float(plan[4]):
			_finish("時間切れ", false)


	func _hold(action: StringName, want: bool) -> void:
		if want and not Input.is_action_pressed(action):
			Input.action_press(action)
		elif not want and Input.is_action_pressed(action):
			Input.action_release(action)


	func _finish(reason: String, ok: bool) -> void:
		done = true
		if not ok:
			fails += 1
		var sec := stage.get_sections()[idx]
		lines.append("%-4s %d %-16s %s  到達 (%.0f, %.0f) / アイテム (%.0f, %.0f)  (%.1f秒, %dバウンド)"
			% ["ok" if ok else "NG", idx + 1, sec.get_display_title(), reason,
				best.x, best.y, target.x, target.y,
				float(frame - start_frame) / 60.0, bounces])
		_next.call_deferred()


	func _report() -> void:
		print("")
		print("=== チュートリアル面の自動プレイ ===")
		for l in lines:
			print(l)
		print("")
		if fails == 0:
			print("すべての区画で判定アイテムに届いた")
		else:
			print("%d 区画が届かない" % fails)
		get_tree().quit(1 if fails > 0 else 0)
