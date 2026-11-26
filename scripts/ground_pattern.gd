@tool
class_name GroundPattern
extends Resource
##
## 地面の模様（パララックス付き）をまとめて持つ。マテリアルのように
## ノードへドラッグするだけで使うためのもの。
##
## TerrainSprite（地形の Gfx_ ノード）の「模様」グループにある
## ground_pattern 欄へ、この .tres をドラッグすれば、そのブロックが模様で塗られる。
## ノードのテクスチャを差し替えたり、チェックを入れたりする必要はない。
##
## 同じ .tres を見ているブロックは全部いっしょに変わる。値を変えた瞬間に
## changed が飛ぶので、エディタの画面もその場で描き直る。
## 別の柄を使いたいときは、この .tres を複製してテクスチャを替える。
##
## 置き場所は resources/ground_pattern_grass.tres。
##

## 模様の絵。継ぎ目のない絵を使う（四辺が繋がっていないなら mirror_tiling を入れる）
@export var texture: Texture2D:
	set(value):
		texture = value
		emit_changed()

## 絵1枚ぶんをワールドの何 px で見せるか。
## 512px の絵を 1024 にすると「絵の1ドット = ワールド2px」、画面では約2.8px
@export var size := Vector2(1024.0, 1024.0):
	set(value):
		size = value
		emit_changed()

## 1枚ごとに絵を反転して貼る。四辺が繋がっていない絵でも継ぎ目が出ない
## 代わりに、左右対称の柄が出る。継ぎ目のない絵なら切っておく
@export var mirror_tiling := false:
	set(value):
		mirror_tiling = value
		emit_changed()


@export_group("パララックス")
## カメラが動いたぶん、模様をどれだけ連れていくか。
## 0.06 ならカメラが 100px 動いて模様が 6px ずれる。0 で動かない
@export_range(0.0, 0.5, 0.005) var parallax_strength := 0.06:
	set(value):
		parallax_strength = value
		emit_changed()

## 模様がカメラに追いつく速さ。小さいほどゆっくり追う。
## カメラは着地のたびに上下に揺れるので、鈍らせて模様が震えないようにしている
@export_range(0.5, 20.0, 0.5) var parallax_smoothing := 3.0:
	set(value):
		parallax_smoothing = value
		emit_changed()
