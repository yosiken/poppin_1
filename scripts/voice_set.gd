@tool
class_name VoiceSet
extends Resource
##
## 1つの場面で鳴らすボイスのまとまり（例: 落下したとき）。
## VoiceBank の中で場面ごとに1つずつ持つ。
##
## 鳴らすたびにこの中から1本を選ぶ。直前に鳴らしたものは選ばない
## （1本しか無いときは同じものを鳴らす）。
##

## 鳴らす候補
@export var streams: Array[AudioStream] = []

## 鳴らす確率。何度も起きる場面（ためジャンプなど）は下げて、聞き飽きないようにする
@export_range(0.0, 1.0, 0.05) var chance := 1.0

## 一度鳴らしたら、この秒数は同じ場面で鳴らさない
@export_range(0.0, 60.0, 0.5) var cooldown := 0.0

## 強さ。別の声が鳴っている最中に来たとき、こちらが強ければ上書きし、
## 同じか弱ければ鳴らさない（声は重ねない）
@export_range(0, 10) var priority := 1

@export_group("ふつう")
## ボイスの量が「ふつう」のときの確率。-1 なら chance と同じ（減らさない）。
## 何度も起きる場面は 0 にして黙らせる
@export_range(-1.0, 1.0, 0.05) var normal_chance := -1.0
## 「ふつう」のときの間隔（秒）。-1 なら cooldown と同じ
@export_range(-1.0, 120.0, 0.5) var normal_cooldown := -1.0
@export_group("")

## 別の声が鳴っていて上書きできないとき、捨てずに鳴り終わるのを待ってから鳴らす。
## 落下の叫びのあとに「あれれー？」と続けるような、続けて聞かせたい場面に使う
@export var wait_turn := false


## ボイスの量（Settings.VoiceMode）に合わせた確率
func chance_for(mode: int) -> float:
	if mode == 2:          # OFF
		return 0.0
	if mode == 1 and normal_chance >= 0.0:
		return normal_chance
	return chance


## ボイスの量に合わせた間隔
func cooldown_for(mode: int) -> float:
	if mode == 1 and normal_cooldown >= 0.0:
		return normal_cooldown
	return cooldown
