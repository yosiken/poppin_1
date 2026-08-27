@tool
class_name TerrainPolygon
extends CollisionPolygon2D
##
## コリジョン形状と見た目を同じ頂点データで描画する地形パーツ。
## Godotエディタの「ポリゴンを編集」ツール（ノード選択→ビューポート上で頂点をクリック/ドラッグ）
## でそのままコリジョン形状を調整でき、見た目（塗りつぶし）が自動追従する。
## 頂点データが1つしかないので、見た目とコリジョンがズレることがない。
##

@export var fill_color := Color(0.32, 0.5, 0.34, 1.0):
	set(value):
		fill_color = value
		queue_redraw()


func _ready() -> void:
	queue_redraw()


func _process(_delta: float) -> void:
	# エディタでポリゴンをドラッグ編集している間、見た目を追従させる
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if polygon.size() >= 3:
		draw_colored_polygon(polygon, fill_color)
