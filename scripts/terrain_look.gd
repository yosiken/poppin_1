@tool
class_name TerrainLook
extends Resource
##
## 地形の枠線の見た目をまとめて持つ。
##
## ブロック1枚ずつインスペクタを開かなくて済むように、ここを見るようにしてある。
## 同じ .tres を全ブロックに割り当てておけば、**1か所直すとステージ中の線が変わる**。
## 値を変えた瞬間に changed が飛ぶので、エディタの画面もその場で描き直る。
##
## 置き場所は resources/terrain_look_default.tres。
## ブロックごとに変えたいときは、そのノードの outline_look を空にすれば
## ノード側の値（outline_color など）が使われる。
##

## 線を引くか
@export var enabled := true:
	set(value):
		enabled = value
		emit_changed()

## 線の色。縞のときは1色目
@export var color := Color(0.09, 0.07, 0.05, 0.9):
	set(value):
		color = value
		emit_changed()

## 線の太さ (px)
@export_range(0.5, 40.0, 0.5) var width := 4.0:
	set(value):
		width = value
		emit_changed()


@export_group("縞")
## 2色の縞にする
@export var striped := false:
	set(value):
		striped = value
		emit_changed()

## 縞の2色目
@export var color2 := Color(0.95, 0.86, 0.35, 0.9):
	set(value):
		color2 = value
		emit_changed()

## 縞1本の長さ (px)。この長さで色が入れ替わる
@export_range(1.0, 200.0, 1.0) var stripe_length := 14.0:
	set(value):
		stripe_length = value
		emit_changed()
