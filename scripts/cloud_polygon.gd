@tool
class_name CloudPolygon
extends Polygon2D
##
## 雲形のポリゴン。中で雲の絵がゆっくり流れ、ふちは透明に溶けてBGになじむ。
##
## 使いかた:
##   1. 中景（Background.tscn の Mid）の子に Polygon2D を足し、このスクリプトを付ける
##      （ノードを足すときに「CloudPolygon」を選んでもいい）
##   2. 「ポリゴンを編集」で雲の形に頂点を打つ。頂点はいくつでもいい
##   3. マテリアルは空なら resources/cloud_flow_material.tres が自動で入る
##
## ふちを透明にするには「ポリゴンのふちからの距離」が要るが、シェーダーは
## ポリゴンの形を知らない。そこでこのスクリプトが形から小さなマスク画像を作り
## （内側が白、ふちへ向かって黒）、ノードのテクスチャとして渡している。
## 形を直すたびに作り直す。マスクと UV は実行時に作るので .tscn には保存しない。
##
## 雲の絵・流れる速さ・濃さはマテリアル側（cloud_flow_material.tres）で決める。
## 同じ .tres を見ている雲は全部いっしょに変わる。
##

const DEFAULT_MATERIAL := "res://resources/cloud_flow_material.tres"

## マスク画像の細かさの上限（長い辺のマス数）。大きいほどふちが正確だが、
## 形を直すたびの作り直しが重くなる。ふちはぼかすので粗くても目立たない
const MAX_CELLS := 128

## ふちのぼかし幅 (px)。ポリゴンのふちから内側へこの距離で 透明 → 不透明 になる
@export_range(0.0, 600.0, 1.0) var feather := 80.0:
	set(value):
		feather = value
		_rebuild()


func _ready() -> void:
	if material == null:
		material = load(DEFAULT_MATERIAL)
	if polygon.is_empty() and Engine.is_editor_hint():
		polygon = _default_shape()
	_rebuild()


func _set(property: StringName, _value: Variant) -> bool:
	# 頂点を動かしたらマスクを作り直す。値はそのまま組み込みに任せる
	if property == &"polygon":
		_rebuild.call_deferred()
	return false


## マスクと UV は実行時に作るもの。インスペクタに出さず、保存もしない。
## 保存すると画像が .tscn に埋め込まれて重くなるうえ、形を直したときに古いものが残る
func _validate_property(property: Dictionary) -> void:
	if property.name in [&"texture", &"uv", &"texture_offset", &"texture_scale",
			&"texture_rotation", &"texture_filter", &"texture_repeat"]:
		property.usage = PROPERTY_USAGE_NONE


## 形からふちのマスクを作り、テクスチャと UV に入れる。
##
## 1. ポリゴンを囲む四角を、最大 MAX_CELLS マスの格子に切る
## 2. 各マスの中心がポリゴンの内側かを調べる
## 3. 内側のマスごとに「いちばん近い外側のマスまでの距離」を求める
##    （前から1回・後ろから1回なめる、よくある近似の距離計算）
## 4. 距離を feather で 0〜1 に直して画像にする
func _rebuild() -> void:
	if not is_inside_tree():
		return
	var pts := polygon
	if pts.size() < 3:
		texture = null
		return

	var rect := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		rect = rect.expand(p)
	var cell := maxf(maxf(rect.size.x, rect.size.y) / float(MAX_CELLS), 1.0)
	# 外周に1マスずつ余白を足す。ふちのマスが必ず「外側」になるように
	var w := int(ceil(rect.size.x / cell)) + 2
	var h := int(ceil(rect.size.y / cell)) + 2
	var origin := rect.position - Vector2(cell, cell)

	var far := 1e9
	var dist := PackedFloat32Array()
	dist.resize(w * h)
	for y in h:
		for x in w:
			var c := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell
			dist[y * w + x] = far if Geometry2D.is_point_in_polygon(c, pts) else 0.0

	# 距離（マス単位）。斜めは √2
	const D1 := 1.0
	const D2 := 1.41421356
	for y in h:
		for x in w:
			var i := y * w + x
			var d := dist[i]
			if d == 0.0:
				continue
			if x > 0: d = minf(d, dist[i - 1] + D1)
			if y > 0:
				d = minf(d, dist[i - w] + D1)
				if x > 0: d = minf(d, dist[i - w - 1] + D2)
				if x < w - 1: d = minf(d, dist[i - w + 1] + D2)
			dist[i] = d
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			var d := dist[i]
			if d == 0.0:
				continue
			if x < w - 1: d = minf(d, dist[i + 1] + D1)
			if y < h - 1:
				d = minf(d, dist[i + w] + D1)
				if x < w - 1: d = minf(d, dist[i + w + 1] + D2)
				if x > 0: d = minf(d, dist[i + w - 1] + D2)
			dist[i] = d

	var bytes := PackedByteArray()
	bytes.resize(w * h)
	var fade := maxf(feather, 0.001)
	for i in w * h:
		# マスの中心から外側のマスの中心までなので、半マス引くとふちからの距離になる
		var px := maxf(dist[i] - 0.5, 0.0) * cell
		var t := clampf(px / fade, 0.0, 1.0)
		bytes[i] = int(round(t * t * (3.0 - 2.0 * t) * 255.0))
	var img := Image.create_from_data(w, h, false, Image.FORMAT_L8, bytes)
	texture = ImageTexture.create_from_image(img)

	# UV はマスク画像のピクセル座標で渡す（Polygon2D が画像の大きさで割る）
	var uvs := PackedVector2Array()
	uvs.resize(pts.size())
	for i in pts.size():
		uvs[i] = (pts[i] - origin) / cell
	uv = uvs
	texture_offset = Vector2.ZERO
	texture_scale = Vector2.ONE
	texture_rotation = 0.0
	texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	# マスクはなめらかに読む（プロジェクトの既定は Nearest で、段が出る）
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


## 新しく置いたときの形。もくもくした横長の雲
func _default_shape() -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := 28
	for i in n:
		var a := TAU * float(i) / float(n)
		var r := Vector2(420.0, 170.0)
		# 上側だけ大きくふくらませる（下は平らめ）
		var bump := 1.0 + 0.18 * sin(a * 5.0) * maxf(-sin(a), 0.0)
		var p := Vector2(cos(a) * r.x, sin(a) * r.y) * bump
		if p.y > 0.0:
			p.y *= 0.55
		out.append(p)
	return out
