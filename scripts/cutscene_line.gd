@tool
class_name CutsceneLine
extends Resource
##
## イベント1コマぶんの指定。テキストと、そのコマで起きる見た目の変化をまとめる。
##
## 画像は「指定したものだけ変わる」方式。null のままなら前のコマの状態を引き継ぐので、
## 会話が続く間は同じ立ち絵を並べ直す必要がない。
## 消したいときは clear_left / clear_right を立てる。
##

enum Side { NONE, LEFT, RIGHT, BOTH }

# ─────────────────────────────── テキスト
## 話者名。空ならネームプレートを出さない
@export var speaker := ""
## 本文。BBCode が使える
@export_multiline var text := ""

# ─────────────────────────────── 立ち絵
@export_group("Portrait")
## どちら側が話しているか。話者側だけ明るくし、反対側は暗くする
@export var speaking := Side.NONE
## 左の立ち絵を差し替える。null なら変更しない
@export var left: Texture2D
## 左の立ち絵を消す
@export var clear_left := false
## 右の立ち絵を差し替える。null なら変更しない
@export var right: Texture2D
## 右の立ち絵を消す
@export var clear_right := false
## 差し替え時に外側からスライドインさせる
@export var slide_in := true

# ─────────────────────────────── 背景
@export_group("Background")
## 背景画像を差し替える。null なら変更しない
@export var background: Texture2D
## 背景を消す（暗転）
@export var clear_background := false

# ─────────────────────────────── 進行
@export_group("Timing")
## 0 なら入力待ち。0 より大きいとその秒数で自動的に次へ進む
@export_range(0.0, 10.0, 0.1) var auto_advance := 0.0
## このコマの前に挟む待ち時間 (秒)。演出の間合い調整用
@export_range(0.0, 5.0, 0.1) var delay := 0.0
