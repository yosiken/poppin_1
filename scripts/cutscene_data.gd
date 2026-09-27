@tool
class_name CutsceneData
extends Resource
##
## イベント1本ぶん。CutsceneLine を順に並べたもの。
## .tres として保存し、Stage の intro / outro や Game の opening / ending に差す。
##

## 表示順に並べたコマ
@export var lines: Array[CutsceneLine] = []

## イベント終了時に立ち絵と背景を消すか。
## OP/ED のように次が無い場面では true、ステージ開始前の会話などでは自然に消える
@export var clear_on_finish := true
