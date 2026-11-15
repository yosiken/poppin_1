extends SceneTree
##
## チュートリアル面の作りを機械的に確かめる。
##
##   godot --headless --path . --script res://tools/check_tutorial_stage.gd
##
## 見るもの:
##   - Main.tscn / Title.tscn が読めるか（スクリプトの構文崩れを拾う）
##   - 区画(TutorialSection)が6つあり、それぞれ Spawn と Item を持っているか
##   - 開始位置・判定アイテム・地形が、その区画の割り当て範囲に収まっているか
##   - 開始位置と復帰地点の真下に足場があるか（半径132px以内を通らないと記録されない）
##   - 落ちたときに死ぬ床が区画の中にあるか
##

const STAGE_PATH := "res://scenes/stages/StageTutorial.tscn"
const FALL_MARGIN := 400.0
const BOUNDS_SLACK := 64.0
const CHECKPOINT_RADIUS := 132.0
const WANT_SECTIONS := 6

var fails := 0


func _initialize() -> void:
	_check_loads()
	_check_stage()
	print("")
	if fails == 0:
		print("=== チュートリアル面の確認: 問題なし ===")
	else:
		print("=== チュートリアル面の確認: %d 件の問題 ===" % fails)
	quit(1 if fails > 0 else 0)


func _ng(msg: String) -> void:
	fails += 1
	print("  NG  %s" % msg)


func _ok(msg: String) -> void:
	print("  ok  %s" % msg)


func _check_loads() -> void:
	print("--- シーンが読めるか ---")
	for path in ["res://scenes/Main.tscn", "res://scenes/Title.tscn", STAGE_PATH]:
		var packed := load(path) as PackedScene
		if packed == null:
			_ng("%s が読めない" % path)
		else:
			_ok(path)


func _check_stage() -> void:
	print("--- チュートリアル面 ---")
	var packed := load(STAGE_PATH) as PackedScene
	if packed == null:
		return
	var stage := packed.instantiate() as TutorialStage
	if stage == null:
		_ng("ルートが TutorialStage ではない")
		return
	get_root().add_child(stage)

	var full: Rect2 = stage.full_bounds()
	if full.size.x <= 0.0 or full.size.y <= 0.0:
		_ng("CameraBounds が無い（区画の割り当てができない）")
		return
	_ok("ステージ全体 = (%.0f, %.0f, %.0f, %.0f) → 区画 %.0f x %.0f"
		% [full.position.x, full.position.y, full.size.x, full.size.y,
			full.size.x / TutorialStage.COLS, full.size.y / TutorialStage.ROWS])

	var sections := stage.get_sections()
	if sections.size() != WANT_SECTIONS:
		_ng("区画が %d 個（%d 個のはず）" % [sections.size(), WANT_SECTIONS])
	else:
		_ok("区画 %d 個" % sections.size())

	for i in sections.size():
		_check_section(stage, sections[i], i)


func _check_section(stage: TutorialStage, sec: TutorialSection, index: int) -> void:
	var cell: Rect2 = stage.section_bounds(index)
	var allowed := cell.grow(BOUNDS_SLACK)
	var death_line := cell.end.y + FALL_MARGIN
	print("--- %d. %s (%s) 区画 x %.0f..%.0f / y %.0f..%.0f ---"
		% [index + 1, sec.get_display_title(), sec.name,
			cell.position.x, cell.end.x, cell.position.y, cell.end.y])

	if sec.message.strip_edges() == "":
		_ng("メッセージが空（触れても何も出ない）")
	if sec.hint.strip_edges() == "":
		_ng("操作説明が空")

	# ── 地形。足場の上辺を集めながら範囲も見る
	var tops: Array[Rect2] = []
	var terrain_count := 0
	for node in sec.find_children("*", "CollisionPolygon2D", true, false):
		var poly := node as CollisionPolygon2D
		if poly == null or poly.polygon.size() < 3:
			continue
		var r := Rect2(poly.to_global(poly.polygon[0]), Vector2.ZERO)
		for k in range(1, poly.polygon.size()):
			r = r.expand(poly.to_global(poly.polygon[k]))
		if not allowed.encloses(r):
			_ng("%s が区画の外にはみ出している（x %.0f..%.0f / y %.0f..%.0f）"
				% [poly.name, r.position.x, r.end.x, r.position.y, r.end.y])
		# 落下床は足場ではないので、立てる面としては数えない
		if poly.get_parent() is Hazard:
			continue
		terrain_count += 1
		tops.append(r)
	_ok("地形 %d 枚" % terrain_count)

	var hazards := 0
	for node in sec.get_children():
		if node is Hazard:
			hazards += 1
	if hazards == 0:
		_ng("落下床が無い（落ちても死なず、隣の区画へ落ちていく）")

	# ── 開始位置
	var spawn: Vector2 = sec.get_spawn_position()
	if not cell.has_point(spawn):
		_ng("開始位置 (%.0f, %.0f) が区画の外" % [spawn.x, spawn.y])
	elif spawn.y > death_line:
		_ng("開始位置 y=%.0f が落下死の線 y=%.0f より下" % [spawn.y, death_line])
	elif not _supported(spawn, tops):
		_ng("開始位置 (%.0f, %.0f) の真下 %.0fpx 以内に足場が無い"
			% [spawn.x, spawn.y, CHECKPOINT_RADIUS])
	else:
		_ok("開始位置 (%.0f, %.0f)" % [spawn.x, spawn.y])

	# ── 判定アイテム
	var item := sec.get_item()
	if item == null:
		_ng("Item(TutorialItem) が無い（クリアできない）")
	elif not cell.has_point(item.global_position):
		_ng("判定アイテム (%.0f, %.0f) が区画の外"
			% [item.global_position.x, item.global_position.y])
	else:
		_ok("判定アイテム (%.0f, %.0f)" % [item.global_position.x, item.global_position.y])

	# ── 復帰地点
	var points := sec.get_recovery_points()
	if points.is_empty():
		_ng("復帰地点が無い（落ちると開始位置まで戻る）")
	for p in points:
		var pos: Vector2 = p.global_position
		if not cell.has_point(pos):
			_ng("復帰地点 %s (%.0f, %.0f) が区画の外" % [p.name, pos.x, pos.y])
		elif pos.y > death_line:
			_ng("復帰地点 %s が落下死の線より下" % p.name)
		elif not _supported(pos, tops):
			_ng("復帰地点 %s (%.0f, %.0f) の真下 %.0fpx 以内に足場が無い"
				% [p.name, pos.x, pos.y, CHECKPOINT_RADIUS])
		else:
			_ok("復帰地点 %s (%.0f, %.0f)" % [p.name, pos.x, pos.y])

	# ── 場所で切り替わる説明
	var at_spawn: String = sec.get_hint_at(spawn)
	if at_spawn.strip_edges() == "":
		_ng("開始位置で出す説明が無い")
	for h in sec.get_hints():
		var r := h.get_rect()
		if not allowed.encloses(r):
			_ng("説明の範囲 %s が区画の外にはみ出している" % h.name)
		if h.text.strip_edges() == "":
			_ng("説明の範囲 %s の文章が空" % h.name)
			continue
		# 他の範囲に覆われていて、その文章が一度も出ないことがないか
		var won: String = sec.get_hint_at(r.get_center())
		if won != h.text:
			_ng("説明の範囲 %s は中心でも別の文章が勝つ（%s）" % [h.name, won])
		else:
			_ok("説明 %s  %s" % [h.name, h.text])


## 真下に足場があるか。無ければ宙に浮いたまま再開することになる
func _supported(pos: Vector2, tops: Array[Rect2]) -> bool:
	for rect in tops:
		if pos.x >= rect.position.x and pos.x <= rect.end.x \
				and rect.position.y >= pos.y \
				and rect.position.y - pos.y <= CHECKPOINT_RADIUS:
			return true
	return false
