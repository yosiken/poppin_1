class_name CreditsData
extends Resource
##
## クリア後に出すスタッフクレジットの中身。
##
## 内容はここ（resources/credits.tres）に置き、出し方は scripts/credits.gd が持つ。
## 人を1人足すのにシーンを開かなくて済むよう、イベント(CutsceneData)と同じ作りにしている
##

## 出す順。1件が1画面
@export var entries: Array[CreditEntry] = []
## 背景。null なら黒一色
@export var background: Texture2D
## 流す曲。null なら無音のまま
@export var bgm: AudioStream

@export_group("Timing")
## 1画面を出しておく秒数。出入りのフェードはこれとは別
@export_range(0.5, 10.0, 0.1) var hold := 2.4
## 文字が出る／消えるのにかける秒数
@export_range(0.0, 2.0, 0.05) var fade := 0.5
## 背景の明転・暗転にかける秒数
@export_range(0.0, 4.0, 0.1) var open_fade := 1.0
## 曲を消すのにかける秒数
@export_range(0.0, 6.0, 0.1) var bgm_fade := 2.0

@export_group("Closing")
## 最後に出す締めの一行。空なら出さない
@export var closing := "THANK YOU FOR PLAYING!"
## 締めを出しておく秒数
@export_range(0.0, 10.0, 0.1) var closing_hold := 3.0


## その画面を出しておく秒数
func hold_of(entry: CreditEntry) -> float:
	if entry and entry.hold > 0.0:
		return entry.hold
	return hold
