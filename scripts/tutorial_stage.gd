@tool
class_name TutorialStage
extends Stage
##
## チュートリアル面。1つのステージの中に区画(TutorialSection)を並べ、
## 1区画ずつ遊ばせる。
##
## 構成:
##   StageTutorial (このスクリプト)
##   ├── CameraBounds (Polygon2D)   ← ステージ全体の範囲。これを 3x2 に割る
##   ├── Spawn (Marker2D)           ← 保険。区画が無いときだけ使われる
##   └── Tutorials (Node2D)
##       ├── Tutorial1 (TutorialSection)
##       ├── ... Tutorial6
##
## 区画の割り当て:
##   CameraBounds を横3×縦2に等分し、並び順どおりに割り当てる。
##       0 1 2
##       3 4 5
##   区画に Bounds ポリゴンを置けばそちらが優先される（1区画だけ広く取りたいとき）。
##
## Stage の問い合わせ（開始位置・復帰地点・カメラ範囲）を今の区画のものに
## 差し替えているので、Game 側は今まで通りの呼び出しでチュートリアルを扱える
##

const COLS := 3
const ROWS := 2

## 今遊んでいる区画。-1 はまだどれも始めていない（ステージ全体が範囲）
var _active := -1


# ═══════════════════════════════ 区画

func get_sections() -> Array[TutorialSection]:
	var out: Array[TutorialSection] = []
	var host := get_node_or_null(^"Tutorials")
	if host == null:
		return out
	for c in host.get_children():
		if c is TutorialSection:
			out.append(c as TutorialSection)
	return out


func section_count() -> int:
	return get_sections().size()


func active_index() -> int:
	return _active


func get_active_section() -> TutorialSection:
	var list := get_sections()
	if _active < 0 or _active >= list.size():
		return null
	return list[_active]


## index の区画だけを有効にする。範囲外なら false
func activate(index: int) -> bool:
	var list := get_sections()
	if index < 0 or index >= list.size():
		push_warning("TutorialStage: 区画 %d は無い（この面は %d 区画）" % [index, list.size()])
		return false
	_active = index
	for i in list.size():
		var item := list[i].get_item()
		if item:
			item.set_active(i == index)
	return true


## ステージ全体の範囲。CameraBounds の外接矩形。
## 親の _camera_bounds() は区画優先に差し替えてしまったので、こちらで読み直す
func full_bounds() -> Rect2:
	var node := get_node_or_null(^"CameraBounds") as Polygon2D
	if node == null or node.polygon.size() < 3:
		push_warning("TutorialStage: %s に CameraBounds がありません" % name)
		return Rect2()
	var rect := Rect2(node.to_global(node.polygon[0]), Vector2.ZERO)
	for i in range(1, node.polygon.size()):
		rect = rect.expand(node.to_global(node.polygon[i]))
	return rect


## 3x2 の割り当て区画。CameraBounds が無ければサイズ0
func grid_cell(index: int) -> Rect2:
	var full := full_bounds()
	if full.size.x <= 0.0 or full.size.y <= 0.0:
		return Rect2()
	var cell := Vector2(full.size.x / float(COLS), full.size.y / float(ROWS))
	var col := index % COLS
	var row := int(index / COLS)
	return Rect2(full.position + Vector2(col * cell.x, row * cell.y), cell)


## 区画の範囲。Bounds ポリゴンがあればそれ、無ければ割り当て区画
func section_bounds(index: int) -> Rect2:
	var list := get_sections()
	if index < 0 or index >= list.size():
		return Rect2()
	var declared := list[index].get_declared_bounds()
	return declared if declared.size.x > 0.0 else grid_cell(index)


# ═══════════════════════════════ Stage の差し替え

## カメラの可動範囲の下端を、区画の下端からこれだけ切り上げる (px)。
##
## 区画は 1500px の高さだが、遊ぶ床は 1150 あたりで、その下は落下床だけの
## 死に地。切らないとカメラはそこまで下がれてしまい、
## 「カメラがプレイヤーの上下動をほぼ全部追う」＝画面の中でキャラが止まり
## 地面のほうが跳ねて見える状態になる。
## 本編のステージは床のすぐ下で範囲が終わっているので、この問題が出ない。
##
## 落下死の線は切り上げた下端のさらに fall_margin 下なので、
## 先に落下床(y 1380〜)が当たる。切っても死に方は変わらない
@export var camera_bottom_trim := 250.0

## カメラの可動範囲＝落下死の線。今の区画のものを返す
func _camera_bounds() -> Rect2:
	if _active >= 0:
		var r := section_bounds(_active)
		if r.size.x > 0.0:
			return _trim(r)
	return _trim(full_bounds())


## 下端を切り上げた範囲。切りすぎて潰れないよう、高さは半分までに留める
func _trim(r: Rect2) -> Rect2:
	if camera_bottom_trim <= 0.0 or r.size.y <= 0.0:
		return r
	r.size.y -= minf(camera_bottom_trim, r.size.y * 0.5)
	return r


func get_spawn_position() -> Vector2:
	var sec := get_active_section()
	if sec:
		return sec.get_spawn_position()
	var marker := get_node_or_null(^"Spawn") as Marker2D
	return marker.global_position if marker else global_position


func get_recovery_points() -> Array[Marker2D]:
	var sec := get_active_section()
	if sec:
		return sec.get_recovery_points()
	# 区画が決まる前にステージ直下を探すと、たまたま最初の区画のものを
	# 拾ってしまう。チュートリアル面では区画の外に復帰地点を置かない
	var out: Array[Marker2D] = []
	return out
