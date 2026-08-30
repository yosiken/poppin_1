@tool
class_name Hazard
extends Area2D
##
## 触れると死亡する床。
##
## 形状は TerrainPolygon を子に置く。地形と同じ仕組みなので、
## エディタの「ポリゴンを編集」でそのまま形を作れて、
## 当たり判定と見た目が同じ頂点データになる（ズレようがない）。
##
## 構成:
##   Hazards (このスクリプト)
##   ├── TerrainPolygon
##   └── TerrainPolygon ...
##
## 色は地形と明確に変える。「触れたら死ぬ」ことが見て分かる必要があるため、
## 足場(緑) や 壁(茶) と混同しない赤系にしている。
##

## プレイヤーが触れた
signal touched(body: Node2D)

## 子の TerrainPolygon にまとめて反映する塗り色
@export var fill_color := Color(0.62, 0.16, 0.19, 1.0):
	set(value):
		fill_color = value
		_apply_color()


func _ready() -> void:
	# プレイヤーは collision_layer = 2。地形(1)には反応させない
	collision_mask = 2
	monitoring = true
	_apply_color()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_apply_color()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		touched.emit(body)


func _apply_color() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		if c is TerrainPolygon:
			var poly := c as TerrainPolygon
			if not poly.fill_color.is_equal_approx(fill_color):
				poly.fill_color = fill_color
