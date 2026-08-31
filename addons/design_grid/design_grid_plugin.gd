@tool
extends EditorPlugin
##
## 2Dエディタのビューポートに方眼を重ねる。
##
## 実行中の方眼（DesignGrid、F4で切替）と同じ寸法・同じ色で描く。
## 数値は DesignGrid の定数を参照しているので、編集しているときの見え方と
## 遊んでいるときの見え方がずれない。
##
## シーンにノードを足さないので、どのステージを開いていても出るし、
## ステージのデータには何も残らない。
##
## 操作:
##   2Dビュー上部のツールバーの「方眼」ボタンで切り替え。
##   状態はエディタ設定に残るので、開き直しても保たれる。
##

## エディタ設定に残すキー
const SETTING := "design_grid/visible"

var _button: Button
## 前回描いたときの視点。変わったときだけ引き直す
var _last_xform := Transform2D()
var _last_size := Vector2.ZERO


# ═══════════════════════════════ ライフサイクル

func _enter_tree() -> void:
	_button = Button.new()
	_button.toggle_mode = true
	_button.flat = true
	_button.text = "方眼"
	_button.tooltip_text = "2Dビューに %dpx の方眼を重ねる" % int(DesignGrid.DEFAULT_CELL)
	_button.button_pressed = _load_visible()
	_button.toggled.connect(_on_toggled)
	add_control_to_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU, _button)
	set_process(true)


func _exit_tree() -> void:
	if _button:
		remove_control_from_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU, _button)
		_button.queue_free()
		_button = null


## どのノードを選んでいても描きたいので、すべて受ける。
## メイン画面を持たないプラグインなので、他のエディタの邪魔にはならない
func _handles(_object: Object) -> bool:
	return true


func _process(_delta: float) -> void:
	# 視点が動いたときだけ引き直す。毎フレーム引くとエディタが重くなる
	var vp := EditorInterface.get_editor_viewport_2d()
	if vp == null:
		return
	var xform := vp.global_canvas_transform
	var size := vp.get_visible_rect().size
	if xform == _last_xform and size == _last_size:
		return
	_last_xform = xform
	_last_size = size
	update_overlays()


# ═══════════════════════════════ 描画

func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if _button == null or not _button.button_pressed:
		return
	var vp := EditorInterface.get_editor_viewport_2d()
	if vp == null:
		return
	# ワールド座標 → ビューポート座標。エディタのズーム・パンがそのまま入っている
	var xform := vp.global_canvas_transform
	var zoom := xform.get_scale()
	if zoom.x <= 0.0 or zoom.y <= 0.0:
		return

	var cell := DesignGrid.DEFAULT_CELL
	var major := DesignGrid.DEFAULT_MAJOR
	var inv := xform.affine_inverse()
	var top_left := inv * Vector2.ZERO
	var bottom_right := inv * overlay.size
	var x0 := int(floor(top_left.x / cell))
	var x1 := int(ceil(bottom_right.x / cell))
	var y0 := int(floor(top_left.y / cell))
	var y1 := int(ceil(bottom_right.y / cell))
	if (x1 - x0) > DesignGrid.MAX_LINES or (y1 - y0) > DesignGrid.MAX_LINES:
		return          # 引きすぎ（ズームアウトしすぎ）のときは描かない

	# 線の太さはビューポート座標で決める。ズームしても太さが変わらない
	for ix in range(x0, x1 + 1):
		var is_major := ix % major == 0
		var sx := (xform * Vector2(ix * cell, 0.0)).x
		overlay.draw_line(Vector2(sx, 0.0), Vector2(sx, overlay.size.y),
			_line_color(ix, is_major), 2.0 if is_major else 1.0)

	for iy in range(y0, y1 + 1):
		var is_major2 := iy % major == 0
		var sy := (xform * Vector2(0.0, iy * cell)).y
		overlay.draw_line(Vector2(0.0, sy), Vector2(overlay.size.x, sy),
			_line_color(iy, is_major2), 2.0 if is_major2 else 1.0)

	var font := overlay.get_theme_font(&"font", &"Label")
	if font == null:
		return
	for ix2 in range(x0, x1 + 1):
		if ix2 % major != 0:
			continue
		for iy2 in range(y0, y1 + 1):
			if iy2 % major != 0:
				continue
			var p := xform * Vector2(ix2 * cell, iy2 * cell)
			overlay.draw_string(font, p + Vector2(6.0, 20.0),
				"%d, %d" % [ix2 * int(cell), iy2 * int(cell)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, DesignGrid.LABEL_SIZE,
				DesignGrid.LABEL_COLOR)


func _line_color(index: int, is_major: bool) -> Color:
	if index == 0:
		return DesignGrid.AXIS_COLOR
	return DesignGrid.MAJOR_COLOR if is_major else DesignGrid.LINE_COLOR


# ═══════════════════════════════ 表示状態

func _load_visible() -> bool:
	var settings := EditorInterface.get_editor_settings()
	if settings and settings.has_setting(SETTING):
		return bool(settings.get_setting(SETTING))
	return true


func _on_toggled(on: bool) -> void:
	var settings := EditorInterface.get_editor_settings()
	if settings:
		settings.set_setting(SETTING, on)
	update_overlays()
