extends SceneTree
##
## ステージ6「風の森」を実測値から組み立てる開発用ツール。
##   godot --headless --path <project> --script res://tools/build_stage06.gd
##
## 狙い: 「落差を作ってからチャージすると高く飛べる」を教える回。
## 回り道は要求せず、飛び込み台が見えている状態にする。
##
## 根拠にした実測値:
##   チャージし続けて跳ぶ  傾き20度: 水平 426px / 高さ 359px
##                        傾き35度: 水平 628px / 高さ 308px
##   素で跳ぶ             傾き35度: 水平 174px / 高さ 108px
##   落差1600pxから着地チャージ: 真上なら 583px / 右へ最大まで倒すと 404px
##
## 寸法の決め方:
##   高台 = 床から 400px … 床でチャージし続けても 280px までしか上がらない
##   飛び込み台 = 床から 1600px … ここから落ちて溜めると
##       真上に跳べば 583px、右へ最大まで倒しても 404px 上がる
##   高台の縁は落下地点から水平 550px 付近（傾けたときの放物線の頂点）に置く
##

const OUT := "res://scenes/stages/Stage06.tscn"
const TERRAIN := "res://scripts/terrain_polygon.gd"
const GOAL := "res://scripts/goal.gd"
const HAZARD := "res://scripts/hazard.gd"
const FOODS := "res://resources/texture/foods.png"

const FLOOR_TOP := 1000.0
const GREEN := Color(0.32, 0.5, 0.34, 1.0)
const BROWN := Color(0.5, 0.36, 0.32, 1.0)

var _stage: Node2D
var _terrain: StaticBody2D


func _initialize() -> void:
	_stage = Node2D.new()
	_stage.name = "Stage06"
	_stage.set_script(load("res://scripts/stage.gd"))
	_stage.set("display_name", "風の森")
	_stage.set("camera_bounds", Rect2(-600, -2500, 5700, 4100))
	# シナリオから生成済みのイベントは差し替えずに引き継ぐ
	_stage.set("intro", load("res://resources/cutscene/stage06_intro.tres"))
	_stage.set("outro", load("res://resources/cutscene/stage06_outro.tres"))
	get_root().add_child(_stage)

	_marker("Spawn", Vector2(0, FLOOR_TOP - 200.0))

	_terrain = StaticBody2D.new()
	_terrain.name = "Terrain"
	_stage.add_child(_terrain)
	_terrain.owner = _stage

	# ── 床。全体の受け皿。失敗しても必ずここへ戻るので復帰コストが低い
	_block("Floor", -500.0, 4600.0, FLOOR_TOP, FLOOR_TOP + 200.0, GREEN)

	# ── 導入: 低い段を2つ。跳ねる感覚を取り戻すだけの区間
	_block("Intro1", 500.0, 900.0, FLOOR_TOP - 150.0, FLOOR_TOP, GREEN)
	_block("Intro2", 1100.0, 1500.0, FLOOR_TOP - 300.0, FLOOR_TOP, GREEN)

	# ── ひねり: たて穴を左右の段でジグザグに登る。
	#    1段 220px。動きながらチャージして跳べる高さが 280〜310px なので、
	#    70〜90px の余裕がある（300px 刻みだと余裕が無く、ほぼ登れない）。
	#    左右の段は x=1950〜2050 の 100px だけ空けて向かい合わせる。
	#    重ねると上の段の裏側が天井になって登れなくなり、離しすぎると
	#    踏み外したときに床まで落ちてしまう
	var steps := [
		["Step1", 2050.0, 2600.0, 220.0],
		["Step2", 1400.0, 1950.0, 440.0],
		["Step3", 2050.0, 2600.0, 660.0],
		["Step4", 1400.0, 1950.0, 880.0],
		["Step5", 2050.0, 2600.0, 1100.0],
		["Step6", 1400.0, 1950.0, 1320.0],
		["Step7", 2050.0, 2600.0, 1540.0],
	]
	for s in steps:
		_block(s[0], s[1], s[2], FLOOR_TOP - s[3], FLOOR_TOP - s[3] + 70.0, GREEN)

	# ── 核心: 飛び込み台。床から 1600px。岩壁に張り付いた棚なので、
	#    降りられるのは左側だけ。降りれば必ず真下の穴へ落ちる
	_block("DiveBoard", 2660.0, 2900.0, FLOOR_TOP - 1670.0, FLOOR_TOP - 1600.0, BROWN)

	# ── たて穴の右の岩壁。下端が床から 670px のところで切れていて、
	#    その下の 270px が唯一の通り道（窓）になる。
	#    上の段や飛び込み台から横に飛んでも、この壁に阻まれて窓には入れない
	_block("Wall", 2900.0, 3350.0, FLOOR_TOP - 2400.0, FLOOR_TOP - 670.0, BROWN)

	# ── 収束: 窓の先の高台。床から 400px。
	#    床でチャージし続けても 280px までしか上がらないので、ここには乗れない。
	#    飛び込み台から落ちて着地で溜めれば、傾けたままでも 404px 上がる
	_block("ExitTerrace", 3350.0, 4500.0, FLOOR_TOP - 400.0, FLOOR_TOP + 200.0, GREEN)

	_marker_group("RecoveryPoints", [
		Vector2(700.0, FLOOR_TOP - 200.0),
		Vector2(2200.0, FLOOR_TOP - 660.0),
		Vector2(2780.0, FLOOR_TOP - 1700.0),
	])

	_goal(Vector2(4000.0, FLOOR_TOP - 510.0))
	var packed := PackedScene.new()
	var err := packed.pack(_stage)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	print("Stage06 -> %s" % error_string(err))
	print("  高台 床から 400px / 窓 670〜400px / 飛び込み台 床から 1600px")
	quit()


func _block(n: String, x0: float, x1: float, y0: float, y1: float, col: Color) -> void:
	var poly := CollisionPolygon2D.new()
	poly.name = n
	var cx := (x0 + x1) * 0.5
	var cy := (y0 + y1) * 0.5
	poly.position = Vector2(cx, cy)
	var hx := (x1 - x0) * 0.5
	var hy := (y1 - y0) * 0.5
	poly.polygon = PackedVector2Array([
		Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)])
	poly.set_script(load(TERRAIN))
	poly.set("fill_color", col)
	_terrain.add_child(poly)
	poly.owner = _stage


func _marker(n: String, pos: Vector2) -> void:
	var m := Marker2D.new()
	m.name = n
	m.position = pos
	_stage.add_child(m)
	m.owner = _stage


func _marker_group(n: String, points: Array) -> void:
	var host := Node2D.new()
	host.name = n
	_stage.add_child(host)
	host.owner = _stage
	var i := 0
	for p in points:
		i += 1
		var m := Marker2D.new()
		m.name = "Point%d" % i
		m.position = p
		host.add_child(m)
		m.owner = _stage


func _goal(pos: Vector2) -> void:
	var g := Area2D.new()
	g.name = "Goal"
	g.position = pos
	g.z_index = -1
	g.collision_mask = 2
	g.set_script(load(GOAL))
	_stage.add_child(g)
	g.owner = _stage

	var sp := Sprite2D.new()
	sp.name = "Sprite"
	sp.texture = load(FOODS)
	sp.hframes = 3
	sp.vframes = 3
	sp.frame = 5              # 6面目 = 風の森
	g.add_child(sp)
	sp.owner = _stage
