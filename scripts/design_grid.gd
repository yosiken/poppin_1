@tool
class_name DesignGrid
extends Node2D
##
## レベルデザイン用の方眼。カメラに映っている範囲だけを毎フレーム描く。
##
## 既定のマス目は 250px。この寸法は実測に基づく:
##   - 普通に跳んでチャージで届く高さ = 282px（約1マス）
##   - 飛び込み台を使って届く高さ = 最大 568px（約2.3マス）
## つまり「1マス強＝普通の限界」「2マス＝落差が要る」の目安になる。
##
## 実行中は F4 で切り替え。エディタで編集しているときは
## addons/design_grid のプラグインが同じものを 2Dビューに重ねる。
##

## 既定値。エディタ用のプラグインと共有する。実行中と編集中で
## 見た目がずれないよう、数値はここ1か所にまとめておく
const DEFAULT_CELL := 250.0
const DEFAULT_MAJOR := 4
const LINE_COLOR := Color(1.0, 1.0, 1.0, 0.07)
const MAJOR_COLOR := Color(0.55, 0.85, 1.0, 0.16)
const AXIS_COLOR := Color(1.0, 0.6, 0.3, 0.35)
const LABEL_COLOR := Color(0.7, 0.85, 1.0, 0.5)
const LABEL_SIZE := 16
## 縦横どちらかがこの本数を超えるなら描かない（ズームアウトしすぎ）
const MAX_LINES := 400

## マス目の大きさ (px)
@export var cell_size := DEFAULT_CELL:
	set(value):
		cell_size = maxf(value, 8.0)
		queue_redraw()

## 何マスごとに太線にするか
@export_range(1, 20, 1) var major_every := DEFAULT_MAJOR:
	set(value):
		major_every = value
		queue_redraw()

## 地形より手前に描く。座標ラベルが地形に隠れなくなる代わりに、
## 方眼がゲーム画面に重なる
@export var draw_on_top := false:
	set(value):
		draw_on_top = value
		z_index = 100 if draw_on_top else -100

@export_group("Look")
@export var line_color := LINE_COLOR
@export var major_color := MAJOR_COLOR
@export var axis_color := AXIS_COLOR
## 太線の交点に座標を表示する
@export var show_coords := true


func _ready() -> void:
	z_index = 100 if draw_on_top else -100


func _process(_delta: float) -> void:
	# カメラが動くので毎フレーム引き直す
	if visible:
		queue_redraw()


## カメラに映っているワールド座標の範囲
func _visible_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2()
	var ct := vp.get_canvas_transform()
	var zoom := ct.get_scale()
	if zoom.x == 0.0 or zoom.y == 0.0:
		return Rect2()
	var top_left := -ct.origin / zoom
	var size := Vector2(vp.get_visible_rect().size) / zoom
	return Rect2(top_left, size).grow(cell_size)


func _draw() -> void:
	var rect := _visible_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	# 画面外まで引くと重いので、映っている範囲のマスだけに絞る
	var x0 := int(floor(rect.position.x / cell_size))
	var x1 := int(ceil(rect.end.x / cell_size))
	var y0 := int(floor(rect.position.y / cell_size))
	var y1 := int(ceil(rect.end.y / cell_size))
	if (x1 - x0) > MAX_LINES or (y1 - y0) > MAX_LINES:
		return          # 引きすぎ（ズームアウトしすぎ）のときは描かない

	var font := ThemeDB.fallback_font
	for ix in range(x0, x1 + 1):
		var x := ix * cell_size
		var is_major := ix % major_every == 0
		var col := axis_color if ix == 0 else (major_color if is_major else line_color)
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), col,
			2.0 if is_major else 1.0)

	for iy in range(y0, y1 + 1):
		var y := iy * cell_size
		var is_major := iy % major_every == 0
		var col := axis_color if iy == 0 else (major_color if is_major else line_color)
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), col,
			2.0 if is_major else 1.0)

	if not show_coords or font == null:
		return
	for ix in range(x0, x1 + 1):
		if ix % major_every != 0:
			continue
		for iy in range(y0, y1 + 1):
			if iy % major_every != 0:
				continue
			draw_string(font, Vector2(ix * cell_size + 6.0, iy * cell_size + 20.0),
				"%d, %d" % [ix * int(cell_size), iy * int(cell_size)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, LABEL_COLOR)
