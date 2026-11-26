@tool
class_name VoiceBank
extends Resource
##
## プレイ中に鳴らすボイスの割り当て表。場面ごとに VoiceSet を1つ持つ。
##
## 置き場所は resources/voice_bank_ob.tres。エディタで開けば、場面ごとに
## 声を足したり外したり、確率や間隔を変えたりできる（コードは触らなくていい）。
## 空の場面は鳴らない。
##
## 長いセリフ（2秒を超えるもの）はプレイの邪魔になるのでここには入れず、
## イベント（カットシーン）で使う。
##

@export_group("ジャンプ")
## ためジャンプで飛んだとき
@export var jump: VoiceSet
## スーパージャンプで飛んだとき
@export var super_jump: VoiceSet

@export_group("失敗")
## ステージの外へ落ちたとき
@export var fall: VoiceSet
## 熱い板（落下床）に触れたとき
@export var hazard: VoiceSet
## 復帰地点に戻ったあと
@export var respawn: VoiceSet
## 急な壁に当たって滑り落ち始めたとき
@export var slip: VoiceSet

@export_group("進行")
## ステージが始まったとき（見出しが出るとき）
@export var stage_start: VoiceSet
## 復帰地点に着いたとき
@export var checkpoint: VoiceSet
## ゴールに触れたとき
@export var goal: VoiceSet
## 記憶を1つ取り戻したとき
@export var memory: VoiceSet
## 記憶が全部そろったとき（memory の代わりに鳴る）
@export var memory_last: VoiceSet

@export_group("チュートリアル")
## チュートリアルの始まり（最初の区画の見出しが出るとき。stage_start の代わりに鳴る）
@export var tutorial_start: VoiceSet
## チュートリアルを終えたとき。ゴールの声のあとに続ける
@export var tutorial_end: VoiceSet


## 場面の名前から VoiceSet を引く。無い名前・空の場面は null
func get_set(category: StringName) -> VoiceSet:
	if not category in self:
		return null
	return get(category) as VoiceSet
