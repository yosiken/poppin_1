@tool
class_name TitleCharacter
extends Node2D
##
## タイトル画面のマスコット(OB)。PSD原画から書き出したパーツ画像を
## 紙人形式に重ねて、瞬き・口パク・頭と腕の揺れ・呼吸をループさせる。
##
## パーツ画像は全て同じ座標系(581x1400)で切り出してあるので、位置合わせは
## シーン側の各ノードの position/offset だけで完結している。このスクリプトは
## 動き(回転・拡縮・上下)だけを持つ。
##
## 目パチは HeadOpen/HeadBlink の丸ごと差し替え(ブレンドモード付きの目を
## 単体でオーバーレイすると発色がおかしくなるため)。
## 口パクは Mouth だけを独立した子ノードにして拡縮している。
##

@export_group("瞬き")
@export_range(0.5, 10.0, 0.1) var blink_min_interval := 2.0
@export_range(0.5, 10.0, 0.1) var blink_max_interval := 5.0
@export_range(0.02, 0.4, 0.01) var blink_duration := 0.12

@export_group("口パク")
## オフにすると常に閉じた口のまま(揺れ・瞬きだけにしたいとき)
@export var mouth_talk_enabled := true
@export_range(0.5, 10.0, 0.1) var talk_min_interval := 2.5
@export_range(0.5, 10.0, 0.1) var talk_max_interval := 5.5
## 1回のパクパクにかける秒数
@export_range(0.05, 0.5, 0.01) var talk_flap_speed := 0.12
@export_range(1, 6, 1) var talk_flap_count := 4

@export_group("揺れ")
@export_range(0.0, 10.0, 0.1) var head_sway_deg := 1.5
@export_range(0.0, 15.0, 0.1) var arm_sway_deg := 5.0
@export_range(0.0, 20.0, 0.5) var breathe_amount := 4.0
@export_range(0.05, 3.0, 0.05) var sway_speed := 0.5

var _head: Node2D
var _head_open: Sprite2D
var _head_blink: Sprite2D
var _mouth_pivot: Node2D
var _arm_r: Node2D
var _arm_l: Node2D

var _t := 0.0
var _blink_wait := 0.0
var _blink_t := -1.0
var _talk_wait := 0.0
var _talking := false
var _talk_t := 0.0
var _base_y := 0.0


func _ready() -> void:
	_head = get_node_or_null(^"Body/Head")
	_head_open = get_node_or_null(^"Body/Head/HeadOpen")
	_head_blink = get_node_or_null(^"Body/Head/HeadBlink")
	_mouth_pivot = get_node_or_null(^"Body/Head/MouthPivot")
	_arm_r = get_node_or_null(^"Body/ArmR")
	_arm_l = get_node_or_null(^"Body/ArmL")
	_base_y = position.y

	if Engine.is_editor_hint():
		return
	_roll_blink_wait()
	_roll_talk_wait()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	_animate_sway()
	_animate_breathe()
	_animate_blink(delta)
	if mouth_talk_enabled:
		_animate_talk(delta)


# ═══════════════════════════════ 揺れ・呼吸

func _animate_sway() -> void:
	if _head:
		_head.rotation = deg_to_rad(sin(_t * sway_speed) * head_sway_deg)
	if _arm_r:
		_arm_r.rotation = deg_to_rad(sin(_t * sway_speed * 0.8 + 0.6) * arm_sway_deg)
	if _arm_l:
		_arm_l.rotation = deg_to_rad(sin(_t * sway_speed * 0.8 + 1.6) * -arm_sway_deg)


func _animate_breathe() -> void:
	position.y = _base_y - absf(sin(_t * sway_speed * 0.6)) * breathe_amount


# ═══════════════════════════════ 瞬き

func _animate_blink(delta: float) -> void:
	if _blink_t >= 0.0:
		_blink_t += delta
		if _blink_t >= blink_duration:
			_blink_t = -1.0
			_set_blinking(false)
			_roll_blink_wait()
		return
	_blink_wait -= delta
	if _blink_wait <= 0.0:
		_blink_t = 0.0
		_set_blinking(true)


func _set_blinking(on: bool) -> void:
	if _head_open:
		_head_open.visible = not on
	if _head_blink:
		_head_blink.visible = on


func _roll_blink_wait() -> void:
	_blink_wait = randf_range(blink_min_interval, blink_max_interval)


# ═══════════════════════════════ 口パク

func _animate_talk(delta: float) -> void:
	if _talking:
		_talk_t += delta
		var phase := sin(_talk_t / maxf(talk_flap_speed, 0.01) * TAU)
		if _mouth_pivot:
			_mouth_pivot.scale.y = lerpf(1.0, 0.45, maxf(0.0, -phase))
		if _talk_t >= talk_flap_speed * talk_flap_count:
			_talking = false
			if _mouth_pivot:
				_mouth_pivot.scale.y = 1.0
			_roll_talk_wait()
		return
	_talk_wait -= delta
	if _talk_wait <= 0.0:
		_talking = true
		_talk_t = 0.0


func _roll_talk_wait() -> void:
	_talk_wait = randf_range(talk_min_interval, talk_max_interval)
