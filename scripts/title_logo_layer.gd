class_name TitleLogoLayer
extends Sprite2D
##
## タイトルロゴの1枚（TitleLogo の Body の子に置く）。
## どの層もキャンバスと同じ大きさの絵なので、位置は全部 (0, 0) のままでそろう。
## 動かす量は TitleLogo が depth と lag から決める。
##

## ロゴがゆっくり揺れるとき、どれだけずれるか（TitleLogo.sway に掛ける）。
## 0 は枠と同じ面。正は手前、負は奥（逆向きにずれる）に見える
@export var depth := 0.0
## ジャンプの勢いにどれだけ遅れてついてくるか。0 はロゴと一緒に動く。
## 大きいほど、跳んだとき・着地したときに中で揺れる（液体は大きめ）
@export_range(0.0, 0.5, 0.01) var lag := 0.0

## ばねの今のずれと速さ（TitleLogo が使う。絵の px）
var spring := Vector2.ZERO
var spring_velocity := Vector2.ZERO
