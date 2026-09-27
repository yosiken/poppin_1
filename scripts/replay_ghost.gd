class_name ReplayGhost
extends Node2D
##
## リプレイ再生用のゴースト表示。実際のプレイヤーモデルは使わず、
## 半透明の丸と傾き軸だけの簡易表示にする（軽量・見た目の混同防止）
##

@export var radius := 14.0
@export var fill_color := Color(1.0, 1.0, 1.0, 0.55)
@export var outline_color := Color(0.4, 0.85, 1.0, 0.9)
@export var axis_color := Color(1.0, 0.9, 0.3, 0.9)


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, fill_color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, outline_color, 2.0)
	draw_line(Vector2.ZERO, Vector2.UP * (radius + 14.0), axis_color, 3.0)
