@tool
class_name TutorialSection
extends Node2D
##
## チュートリアル1本ぶん。1つのステージの中にこれを6つ並べる。
##
## 構成:
##   Tutorial1 (このスクリプト)
##   ├── Spawn (Marker2D)            ← この区画の開始位置（必須）
##   ├── Item (TutorialItem)         ← 合格判定（必須）
##   ├── Bounds (Polygon2D)          ← 任意。無ければ 3x2 の割り当て区画がそのまま範囲
##   ├── RecoveryPoints (Node2D)     ← 任意。この区画だけの復帰地点
##   ├── Terrain (StaticBody2D)
##   ├── Hazards (Hazard)
##   └── Signs (Node2D)
##
## 範囲(get_bounds)はカメラの可動範囲と落下死の線を兼ねる。区画ごとに持つので、
## 隣の区画が画面に入り込んだり、落ちたときに隣へ落ちていったりしない
##

## 合格したときに飛ぶ
signal cleared(section: TutorialSection)

## 見出しに出す短い名前。例: "基本操作"
@export var title := ""

## 画面上へ出す操作説明の既定。空なら出さない。
## Hints の下に TutorialHint を置けば、その範囲に居る間だけ別の文章に切り替わる
@export_multiline var hint := ""

## 合格したときに出すメッセージ
@export_multiline var message := ""


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var item := get_item()
	if item:
		item.touched.connect(_on_item_touched)
	else:
		push_warning("TutorialSection: %s に Item(TutorialItem) がありません" % name)


func _on_item_touched(_body: Node2D) -> void:
	cleared.emit(self)


# ═══════════════════════════════ 問い合わせ

## 親の Tutorials の中で何番目か。0 始まり。見つからなければ -1
func get_order() -> int:
	var parent := get_parent()
	if parent == null:
		return -1
	return parent.get_children().find(self)


func get_spawn_position() -> Vector2:
	var marker := get_node_or_null(^"Spawn") as Marker2D
	if marker == null:
		push_warning("TutorialSection: %s に Spawn がありません" % name)
		return global_position
	return marker.global_position


func get_item() -> TutorialItem:
	for c in get_children():
		if c is TutorialItem:
			return c as TutorialItem
	return null


func get_recovery_points() -> Array[Marker2D]:
	var out: Array[Marker2D] = []
	var host := get_node_or_null(^"RecoveryPoints")
	if host == null:
		return out
	for c in host.get_children():
		if c is Marker2D:
			out.append(c as Marker2D)
	return out


## 任意の Bounds ポリゴンがあればその外接矩形。無ければサイズ0。
## サイズ0のときは TutorialStage が 3x2 の割り当て区画を使う
func get_declared_bounds() -> Rect2:
	var node := get_node_or_null(^"Bounds") as Polygon2D
	if node == null or node.polygon.size() < 3:
		return Rect2()
	var rect := Rect2(node.to_global(node.polygon[0]), Vector2.ZERO)
	for i in range(1, node.polygon.size()):
		rect = rect.expand(node.to_global(node.polygon[i]))
	return rect


## 説明を切り替える範囲の一覧。Hints の下に無くても、区画の中にあれば拾う
func get_hints() -> Array[TutorialHint]:
	var out: Array[TutorialHint] = []
	for node in find_children("*", "TutorialHint", true, false):
		var h := node as TutorialHint
		if h:
			out.append(h)
	return out


## その位置で出すべき説明。どの範囲にも入っていなければ既定の hint
func get_hint_at(point: Vector2) -> String:
	var best: TutorialHint = null
	for h in get_hints():
		if h.contains(point) and h.beats(best):
			best = h
	return best.text if best else hint


func get_display_title() -> String:
	return title if title != "" else name
