class_name CreditEntry
extends Resource
##
## クレジットの1画面ぶん。
##
## 「役割」と「名前」を1人ずつ出す。同じ役割に複数人いるときは、
## その人数ぶん並べる（1画面に1人）。
##

## 名前の上に小さく出す肩書き。空なら出さない
@export var role := ""
## 画面の中央に大きく出す名前。空なら役割だけの見出しになる
@export var person := ""
## この画面だけ出しておく時間を変えたいとき (秒)。0 以下なら CreditsData の既定
@export var hold := 0.0


## 一覧やログに出すときの一行
func to_line() -> String:
	if role == "":
		return person
	if person == "":
		return "［%s］" % role
	return "%s … %s" % [role, person]
