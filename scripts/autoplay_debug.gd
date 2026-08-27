extends Node2D
## 右キーを押しっぱなしにして自動再生し、毎フレームの位置・速度を記録するデバッグ用ハーネス。
## `godot --headless --path <project> scenes/AutoplayDebug.tscn --quit-after N` のように直接実行して使う。

@onready var player: PogoPlayer = $Main/Player

var frame := 0
const MAX_FRAMES := 1800


func _ready() -> void:
	Input.action_press(&"pogo_right")


func _physics_process(_delta: float) -> void:
	frame += 1
	var pos := player.global_position
	var vel := player.velocity
	var ok := is_finite(pos.x) and is_finite(pos.y) and is_finite(vel.x) and is_finite(vel.y)

	if frame % 5 == 0 or not ok:
		print("f=%d pos=(%.1f,%.1f) vel=(%.1f,%.1f) speed=%.1f tilt=%.1f"
			% [frame, pos.x, pos.y, vel.x, vel.y, vel.length(), player.tilt_deg])

	if not ok:
		print("!!! NaN/Inf detected at frame %d" % frame)
		get_tree().quit(1)

	if frame >= MAX_FRAMES:
		print("DONE: reached max frames without NaN/Inf")
		get_tree().quit()
