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

# ─────────────────────────────── 演出メモ
@export_group("Note")
## 台本の〔演出：…〕。このコマで起きることの覚え書きで、ゲーム中には出ない。
## Cutscene の show_notes を立てたときだけ、確認用に画面へ表示する。
##
## 台本が正なので、ここに書いても次の再生成で上書きされる。
## 直すときは台本 (resources/dotonbori-isekai-scenario-v2.md) 側を直すこと
@export_multiline var note := ""

# ─────────────────────────────── 台本との突き合わせ用
@export_group("Merge")
## 台本には無い、CutsceneEditor で手を入れて挿したコマ。
##
## tools/make_cutscenes.gd は台本からコマを作り直すので、この印が無いコマは
## 台本に同じ本文が見つからなければ消える。印が付いたコマは台本の外のものとして、
## 「直前にあった台本のコマ」を手掛かりに元の位置へ戻される。
## 立ち絵や背景だけを変える無音の間や、台本に無い掛け合いを足すときに立てる
@export var inserted := false
