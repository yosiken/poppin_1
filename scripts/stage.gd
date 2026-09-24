@tool
class_name Stage
extends Node2D
##
## 1ステージぶんの地形・ゴール・開始位置をまとめたもの。
##
## 構成:
##   Stage (このスクリプト)
##   ├── Terrain (StaticBody2D)
##   │   └── CollisionPolygon2D × N
##   ├── Goal (Area2D)
##   └── Spawn (Marker2D)   ← プレイヤーの開始位置
##
## Game 側がこれを読み込み、Spawn へプレイヤーを置いて Goal を監視する。
##

## ステージ選択に出す表示名。空ならシーン名が使われる
@export var display_name := ""

## カメラの可動範囲。シーン内の CameraBounds（4点のポリゴン）の外接矩形。
## エディタで頂点をドラッグすれば範囲が変わるので、数値を打ち込む必要がない。
## ノードが無い場合はサイズ0を返し、カメラ制限も落下判定も掛からなくなる
var camera_bounds: Rect2:
	get:
		return _camera_bounds()

@export_group("Event")
## ステージ開始時に再生するイベント
@export var intro: CutsceneData
## ゴール到達後に再生するイベント
@export var outro: CutsceneData
## クリアデモの後の「時間経過」に出す文言。空なら TimePassage の既定を使う
@export var time_passage_text := ""


## CameraBounds のポリゴンを囲む矩形を返す。
## 頂点は4点を想定しているが、回転や余分な頂点があっても外接矩形として扱う
func _camera_bounds() -> Rect2:
	var node := get_node_or_null(^"CameraBounds") as Polygon2D
	if node == null or node.polygon.size() < 3:
		push_warning("Stage: %s に CameraBounds（4点のポリゴン）がありません" % name)
		return Rect2()
	var rect := Rect2(node.to_global(node.polygon[0]), Vector2.ZERO)
	for i in range(1, node.polygon.size()):
		rect = rect.expand(node.to_global(node.polygon[i]))
	return rect


## 復帰地点の一覧。RecoveryPoints の下に Marker2D を進行順に並べる。
## 無ければ空。その場合は落下時に Spawn へ戻る
func get_recovery_points() -> Array[Marker2D]:
	var out: Array[Marker2D] = []
	# 直下とは限らない（Spawn の子に置かれているステージがある）ので探して回る。
	# 直下だけを見ていた頃は、そのステージだけ復帰地点が無い扱いになっていた
	var host := find_child("RecoveryPoints", true, false)
	if host == null:
		return out
	for c in host.get_children():
		if c is Marker2D:
			out.append(c as Marker2D)
	return out


## 触れると死亡する床の一覧
func get_hazards() -> Array[Hazard]:
	var out: Array[Hazard] = []
	_collect_hazards(self, out)
	return out


func _collect_hazards(n: Node, out: Array[Hazard]) -> void:
	if n is Hazard:
		out.append(n as Hazard)
	for c in n.get_children():
		_collect_hazards(c, out)


## プレイヤーの開始位置。Spawn が無ければ原点
func get_spawn_position() -> Vector2:
	var marker := get_node_or_null(^"Spawn") as Marker2D
	return marker.global_position if marker else global_position


## このステージのゴール。無ければ null
func get_goal() -> Goal:
	return _find_goal(self)


func _find_goal(n: Node) -> Goal:
	if n is Goal:
		return n as Goal
	for c in n.get_children():
		var found := _find_goal(c)
		if found:
			return found
	return null


func get_display_name() -> String:
	return display_name if display_name != "" else name
