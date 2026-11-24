class_name Voice
extends Node
##
## プレイ中のボイスを鳴らす係。Main（game.gd）が1つ作って子に置く。
##
## どこからでも Voice.say(&"fall") のように場面の名前で呼ぶ。
## 何をどの確率で鳴らすかは VoiceBank（resources/voice_bank_ob.tres）が決める。
##
## 決まりごと（resources/text/ボイスリスト案.md の設計どおり）:
##   - 声は重ねない。鳴っている最中に来たら、強さ（priority）が上なら上書き、
##     そうでなければ捨てる。wait_turn の場面だけは鳴り終わるのを待つ
##   - 同じ場面で直前と同じ声は選ばない
##   - 確率（chance）と間隔（cooldown）で、聞き飽きないようにする
##   - VOICE バスで鳴らす（OPTIONS の VOICE VOLUME で別に調整できる）
##
## 落下からの復帰中はツリーが止まるので、この係は止まらないようにしてある。
## 叫び声が暗転の途中で途切れないように。
##
## Main が居ない画面（タイトルなど）で呼んでも何も起きない。
##

const DEFAULT_BANK := "res://resources/voice_bank_ob.tres"
const BUS := &"VOICE"

## 割り当て表。空なら DEFAULT_BANK を読む
@export var bank: VoiceBank

static var _active: Voice

var _player: AudioStreamPlayer
var _playing_priority := 0
## 場面ごとの、直前に鳴らした声
var _last := {}
## 場面ごとの、次に鳴らしてよい時刻（秒）
var _ready_at := {}
## 鳴り終わりを待っている場面。1つだけ持つ（あとから来たものが勝つ）
var _queued: StringName = &""


## 場面 category の声を1本鳴らす。鳴らしたら true。
## 確率で外れた・間隔が空いていない・別の声に負けた、のときは false
static func say(category: StringName) -> bool:
	if _active == null or not is_instance_valid(_active):
		return false
	return _active._say(category)


## 声を鳴らせる状態か（Main の中に居るか）
static func available() -> bool:
	return _active != null and is_instance_valid(_active) and _active.bank != null


func _enter_tree() -> void:
	_active = self


func _exit_tree() -> void:
	if _active == self:
		_active = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if bank == null and ResourceLoader.exists(DEFAULT_BANK):
		bank = load(DEFAULT_BANK)
	_player = AudioStreamPlayer.new()
	_player.name = "VoicePlayer"
	# バスが無い（古い bus_layout）ときは効果音と同じ所で鳴らす
	_player.bus = BUS if AudioServer.get_bus_index(BUS) != -1 else &"SE"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)
	_player.finished.connect(_on_finished)


func _say(category: StringName) -> bool:
	if bank == null:
		return false
	var vs := bank.get_set(category)
	if vs == null or vs.streams.is_empty():
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now < float(_ready_at.get(category, 0.0)):
		return false
	if randf() > vs.chance:
		return false
	if _player.playing and vs.priority <= _playing_priority:
		if vs.wait_turn:
			_queued = category
			# 待つと決めた時点で間隔を数え始める。待っている間にもう一度
			# 呼ばれても二重に並ばないように
			_ready_at[category] = now + vs.cooldown
			return true
		return false
	_play(category, vs, now)
	return true


func _play(category: StringName, vs: VoiceSet, now: float) -> void:
	var stream := _pick(category, vs)
	if stream == null:
		return
	_player.stream = stream
	_player.play()
	_playing_priority = vs.priority
	_last[category] = stream
	_ready_at[category] = now + vs.cooldown
	# 上書きして鳴らした場合、待っていたものは捨てる（話が繋がらなくなるので）
	if _queued != category:
		_queued = &""


## 直前と同じものを避けて1本選ぶ
func _pick(category: StringName, vs: VoiceSet) -> AudioStream:
	var pool: Array[AudioStream] = []
	for s in vs.streams:
		if s != null and (vs.streams.size() == 1 or s != _last.get(category)):
			pool.append(s)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]


func _on_finished() -> void:
	_playing_priority = 0
	if _queued == &"":
		return
	var category := _queued
	_queued = &""
	var vs := bank.get_set(category) if bank else null
	if vs and not vs.streams.is_empty():
		_play(category, vs, Time.get_ticks_msec() / 1000.0)
