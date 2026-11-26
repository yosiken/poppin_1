@tool
class_name TutorialHint
extends Node2D
##
## 画面上部の説明文を切り替える範囲。
##
## チュートリアルの区画の中に置き、プレイヤーがこの範囲に入っている間だけ
## text が画面上部に出る。どの範囲にも入っていなければ、区画の既定の説明
## （TutorialSection.hint）に戻る。
##
## 構成:
##   Tutorial1/Hints/Hint1 (このスクリプト)
##
## Area2D ではなく位置の比較で判定している:
##   - 当たり判定を増やさない（説明を出すために物理に仕事をさせたくない）
##   - 入った/出たの順番に左右されない。毎フレーム「今どこに居るか」で決まる
##
## 範囲が重なっているときは、優先度(priority)の高いほう。同じなら狭いほうが勝つ。
## 「広い範囲でざっくり説明し、その中の狭い範囲だけ別の説明にする」が書けるため
##

## 出す文章
@export_multiline var text := ""

## 範囲の大きさ (px)。ノードの位置が中心
@export var size := Vector2(600.0, 1200.0):
	set(value):
		size = value
		queue_redraw()

## 範囲が重なったときの強さ。大きいほうが勝つ
@export var priority := 0

## エディタでの枠の色。ゲーム中は描かない
@export var editor_color := Color(0.4, 0.8, 1.0, 0.5)


func _ready() -> void:
	queue_redraw()


## 範囲（世界座標）
func get_rect() -> Rect2:
	return Rect2(global_position - size * 0.5, size)


func contains(point: Vector2) -> bool:
	return get_rect().has_point(point)


## 重なったときの勝ち負け。self のほうが優先されるなら true
func beats(other: TutorialHint) -> bool:
	if other == null:
		return true
	if priority != other.priority:
		return priority > other.priority
	# 同じ優先度なら狭いほう＝より具体的な説明を採る
	return size.x * size.y < other.size.x * other.size.y


## 範囲はエディタでだけ見えるようにする。遊んでいるときに枠が見えては困る
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var rect := Rect2(-size * 0.5, size)
	draw_rect(rect, Color(editor_color.r, editor_color.g, editor_color.b, 0.08), true)
	draw_rect(rect, editor_color, false, 4.0)
