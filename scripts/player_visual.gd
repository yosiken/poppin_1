extends Sprite2D
class_name PlayerVisual
##
## 3Dプレイヤーモデルを SubViewport に描画し、その結果を2Dのスプライトとして貼る。
##
## 設計方針:
##   - ゲームは2D。3Dは見た目専用で、当たり判定も物理も PogoPlayer 側（2D）が持つ
##   - キャラクター自身に物理は持たせない。姿勢はアニメーション（手付け）か PogoPose で決める
##   - ビューポート・カメラ・ライトは実行時に組み立てる。シーンに積むノードを増やさない
##

# ─────────────────────────────── 設定
## モデルシーン (.glb など)
@export var model: PackedScene

## 基本ポーズ。モデルにアニメーションが入っていないときの静止姿勢。
## AnimationPlayer が見つかって再生できた場合はそちらが優先され、これは無視される
@export var pose: PogoPose:
	set(value):
		if pose and pose.changed.is_connected(_apply_pose):
			pose.changed.disconnect(_apply_pose)
		pose = value
		if pose and not pose.changed.is_connected(_apply_pose):
			pose.changed.connect(_apply_pose)
		_apply_pose()

## 見た目の調整パラメータ一式。PogoTuner から実行中に触れる。
## 未設定なら既定値の PogoVisualStats を自動で作る
@export var visual_stats: PogoVisualStats:
	set(value):
		if visual_stats and visual_stats.changed.is_connected(_apply_visual_stats):
			visual_stats.changed.disconnect(_apply_visual_stats)
		visual_stats = value
		if visual_stats and not visual_stats.changed.is_connected(_apply_visual_stats):
			visual_stats.changed.connect(_apply_visual_stats)
		_apply_visual_stats()

@export_group("View")
## SubViewport の解像度 (px)
@export var view_size := Vector2i(256, 256)

@export_group("Flail")
## 振り回すボーンと、その配分倍率。減衰振動を前後スイング(ローカルX)に加える。
##
## 回転は親から子へ積み上がるので、チェーンの先まで同じ倍率にすると
## 足先が基準から (親+子) ぶん回ってしまい、関節が反対側へ折れる（フリップする）。
## 先へ行くほど倍率を下げること。
@export var flail_bones: Dictionary[StringName, float] = {
	&"DEF-upper_arm.L": 1.0, &"DEF-forearm.L": 1.0,
	&"DEF-upper_arm.R": 1.0, &"DEF-forearm.R": 1.0,
	&"DEF-thigh.L": 0.6, &"DEF-shin.L": 0.35,
	&"DEF-thigh.R": 0.6, &"DEF-shin.R": 0.35,
	&"DEF-spine.004": 0.4, &"DEF-spine.005": 0.25,
	# 頭は首(DEF-spine)チェーンの子ではなく、Rigifyのコントロール側にぶら下がった
	# 別系統のボーン。コンストレイントは取り込まれないので首を回しても付いてこない。
	# ここだけは積み上がらないので、首につながって見えるよう
	# 上の首ボーンの合計(0.4+0.25)と同じ値を入れる
	&"head.001": 0.65,
}

@export_group("Ball")
## ボール（跳ねる玉）を動かすボーン名。
## ボールはキャラクター本体とは別のスケルトンに1本だけ入っており、
## このボーンを持つスケルトンをボール用、そうでない方をキャラクター本体として扱う
@export var ball_bone: StringName = &"ball"

@export_group("Animation")
## 再生するアニメーション名。空ならモデルが持つ最初のアニメーションを使う。
## モデルにアニメーションが無い場合は pose が使われる
@export var idle_animation: StringName = &""

@export_group("Toon")
## この名前のマテリアルはトゥーンを掛けず、陰影なし(unlit)で描く。
## ライトの向きで暗くなってほしくない部分（白目やハイライトなど）に使う
@export var unlit_materials: Array[StringName] = [&"white_unlit"]

const TOON_SHADER := preload("res://resources/shader/toon_character.gdshader")
const OUTLINE_SHADER := preload("res://resources/shader/sprite_outline.gdshader")

# ─────────────────────────────── 内部状態
var _toon_materials: Array[ShaderMaterial] = []
var _outline_material: ShaderMaterial
var _viewport: SubViewport
var _rig: Node3D                       ## 傾き(Z)を与える外側。カメラ基準で回す
var _yaw: Node3D                       ## モデルの向き(Y)。傾きと軸が混ざらないよう内側に分ける
var _skeleton: Skeleton3D
var _cam: Camera3D
var _light: DirectionalLight3D
var _env: Environment
var _anim: AnimationPlayer
var _anim_name := ""                   ## 再生中のアニメーション名。空ならポーズ運用
var _player: PogoPlayer
var _flail_base: Dictionary[int, Quaternion] = {}   ## 振れを乗せる土台の姿勢
var _anim_driven: Dictionary[int, bool] = {}        ## アニメーションが毎フレーム上書きするボーン
var _flail_angle := 0.0
var _flail_vel := 0.0
var _ball_skeleton: Skeleton3D         ## ボール用（ボーン1本）のスケルトン
var _ball_bone_idx := -1
var _ball_base_scale := Vector3.ONE
var _ball_top_y := 0.0                 ## ボーン原点からボール上端までの高さ
var _char_base_y := 0.0                ## キャラクター側スケルトンの基準の高さ
var _squash := 1.0
var _facing_right := true              ## 直近の進行方向。デッドゾーン内では保持する
var _yaw_deg := 0.0                    ## 補間中の現在の向き
var _recover_t := 1.0                  ## 0=潰れきった直後, 1=元通り


# ═══════════════════════════════ ライフサイクル

func _ready() -> void:
	_player = get_parent() as PogoPlayer
	if _player == null:
		push_warning("PlayerVisual: 親が PogoPlayer ではありません")
	if model == null:
		push_warning("PlayerVisual: model が未設定です")
		return
	if visual_stats == null:
		visual_stats = PogoVisualStats.new()

	_build_viewport()
	_setup_animation()
	_apply_pose()
	# 初期の向きは補間の途中から始めないよう、右向きの角度で直接置く
	_yaw_deg = visual_stats.model_yaw_right_deg
	_yaw.rotation.y = deg_to_rad(_yaw_deg)
	_capture_flail_base()
	# アニメーションより後に走らせて、その上へ振れを重ねる
	process_priority = 100
	if _player:
		_player.bounced.connect(_on_bounced)


func _process(_delta: float) -> void:
	if _rig == null or _player == null:
		return
	# 2Dの傾き角をそのまま3Dへ。カメラが+Z側から見ているのでZ軸回りが2Dの回転に対応する
	_rig.rotation.z = -deg_to_rad(_player.tilt_deg)
	_update_facing(_delta)
	_update_squash(_delta)
	_update_flail(_delta)


# ═══════════════════════════════ 向き

## 進行方向を向かせる。左右の角度は補間するので、跳ねながらでも滑らかに振り向く
func _update_facing(delta: float) -> void:
	if _yaw == null or _player == null or delta <= 0.0:
		return

	# 停止間際は velocity.x の符号がばたつくので、デッドゾーン内では直前の向きを保つ
	var vx := _player.velocity.x
	if absf(vx) > _v(&"facing_deadzone"):
		_facing_right = vx > 0.0

	var target: float = _v(&"model_yaw_right_deg") if _facing_right else _v(&"model_yaw_left_deg")
	# フレームレートに依存しない指数補間
	_yaw_deg = lerpf(_yaw_deg, target, 1.0 - exp(-_v(&"model_yaw_turn_speed") * delta))
	_yaw.rotation.y = deg_to_rad(_yaw_deg)


# ═══════════════════════════════ ボールの潰れ

## モデルにはスケルトンが2つ入っている（キャラクター本体とボール）。
## 順番に依存すると取り違えるので、ball_bone を持つ方をボールとして選り分ける
func _resolve_skeletons() -> void:
	var found: Array[Node] = []
	_collect_nodes_of_type(_yaw, "Skeleton3D", found)
	for n in found:
		var skel := n as Skeleton3D
		var idx := _find_ball_bone(skel)
		if idx >= 0:
			_ball_skeleton = skel
			_ball_bone_idx = idx
			_ball_base_scale = skel.get_bone_pose_scale(idx)
		elif _skeleton == null:
			_skeleton = skel
	if _skeleton == null:
		push_warning("PlayerVisual: キャラクター本体の Skeleton3D が見つかりません")
	else:
		_char_base_y = _skeleton.position.y
	if _ball_skeleton == null:
		push_warning("PlayerVisual: ボール用ボーン '%s' を持つスケルトンが見つかりません" % ball_bone)
		return

	# キャラをボールの上端に乗せ続けるため、伸縮でどれだけ上端が動くかを測っておく。
	# ボーン原点を基準にスケールが掛かるので、原点から上端までの距離がそのまま倍率になる
	var ball_mesh := _find_node_of_type(_ball_skeleton, "MeshInstance3D") as MeshInstance3D
	if ball_mesh:
		_ball_top_y = maxf(ball_mesh.get_aabb().end.y
			- _ball_skeleton.get_bone_global_rest(_ball_bone_idx).origin.y, 0.0)


## glTF取り込みでは、ボーン名が同名のノード（ボールのメッシュ）と衝突すると
## "ball_2" のように連番が付く。完全一致で見つからないときはその形も許容する
func _find_ball_bone(skel: Skeleton3D) -> int:
	var idx := skel.find_bone(ball_bone)
	if idx >= 0:
		return idx
	var prefix := String(ball_bone)
	for i in skel.get_bone_count():
		var rest := skel.get_bone_name(i).substr(prefix.length())
		if skel.get_bone_name(i).begins_with(prefix) and rest.begins_with("_") \
				and rest.substr(1).is_valid_int():
			return i
	return -1


func _update_squash(delta: float) -> void:
	if _ball_skeleton == null or delta <= 0.0:
		return

	if _player and _player.is_grounded():
		# 接地した瞬間に潰しきる。通常のバウンドではここは1フレームしか通らない
		_recover_t = 0.0
	elif _recover_t < 1.0:
		# 指定フレーム数ぶんの秒数をかけて戻す。表示レートに依らず尺を一定に保つため、
		# 物理レート(既定60)基準の秒数に直してから delta で進める
		var duration := float(_v(&"squash_recover_frames")) / float(Engine.physics_ticks_per_second)
		_recover_t = minf(1.0, _recover_t + delta / maxf(duration, 0.0001))

	# 着地でぺしゃんこ → 元に戻る → 空中では上下の速さに応じて縦に伸びる、の順。
	# 潰れが戻りきってから伸びを混ぜる。同時に掛けると着地の一瞬で打ち消し合って何も見えない
	_squash = lerpf(_v(&"ball_squash_y"), 1.0, _recover_t)
	if _player and _recover_t >= 1.0:
		var speed_ref: float = maxf(_v(&"stretch_speed_ref"), 1.0)
		var t := clampf(absf(_player.velocity.y) / speed_ref, 0.0, 1.0)
		_squash = lerpf(1.0, _v(&"ball_stretch_y"), t)

	# 縦に潰した分だけ横へ広げる。体積が変わって見えると跳ねではなく伸縮に見える
	var lateral := 1.0 / sqrt(maxf(_squash, 0.01))
	_ball_skeleton.set_bone_pose_scale(_ball_bone_idx,
		_ball_base_scale * Vector3(lateral, _squash, lateral))

	# キャラはボールの上に乗っているので、上端が沈んだ／伸びた分だけ一緒に上下させる。
	# ここを動かさないとボールだけが潰れてキャラが宙に浮いて見える
	if _skeleton:
		_skeleton.position.y = _char_base_y \
			+ _ball_top_y * (_squash - 1.0) * _v(&"body_follow_ball")


# ═══════════════════════════════ 手足の振れ

## アニメーションが実際にキーを持っているボーンを調べておく。
## そのボーンだけは毎フレーム基準を取り直してよい（アニメが上書きしてくれるため）。
## キーを持たないボーンで取り直すと、自分が書いた値を基準として読み戻してしまい、
## 角度が毎フレーム積み上がって関節が一方向へ流れていく
func _capture_flail_base() -> void:
	_flail_base.clear()
	_anim_driven.clear()
	if _skeleton == null or _anim == null or _anim_name == "":
		return
	var anim := _anim.get_animation(_anim_name)
	if anim == null:
		return
	for t in anim.get_track_count():
		var bone_name := String(anim.track_get_path(t).get_concatenated_subnames())
		var i := _skeleton.find_bone(bone_name)
		if i < 0:
			continue
		_anim_driven[i] = true
		# 土台はアニメーションから直接サンプリングして確定させる。
		# 生のポーズを読むと、AnimationPlayer が最初の1フレームを書く前か後かで
		# 結果が変わってしまう
		if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			_flail_base[i] = anim.rotation_track_interpolate(t, 0.0)


## 着地の瞬間に手足へ角速度を叩き込む。
## 速度の微分でも取れるが1フレームのスパイクになって不安定なので、
## ゲーム側が既に持っている bounced シグナルの反発量をそのまま使う
func _on_bounced(strength: float, _normal: Vector2) -> void:
	_flail_vel -= strength * _v(&"flail_gain")      # 接地の瞬間、手足は置いていかれる


## 叩かれた角速度をばね-ダンパで基本姿勢へ戻す。
## 物理エンジンは使わない（Godot 4.7.2 では PhysicalBone3D / SpringBone とも
## スクリプトからはボーンに束縛されず、姿勢が一切変化しないため）
func _update_flail(delta: float) -> void:
	if _skeleton == null or delta <= 0.0 or flail_bones.is_empty():
		return

	var limit: float = _v(&"flail_max_deg")

	# 基本姿勢（＝アニメーションが決めた角度）へ戻す通常のばね-ダンパ
	var accel: float = -_v(&"flail_stiffness") * _flail_angle - _v(&"flail_damping") * _flail_vel

	# ── ソフトリミット。
	#    上限で角度を切り落とすと、そこに張り付いたあと鞭のように戻って関節が抜ける。
	#    代わりに、外側へ行くほど基本姿勢へ戻す力を強くして手前で止める
	var over: float = absf(_flail_angle) - _v(&"flail_soft_deg")
	if over > 0.0:
		var barrier: float = _v(&"flail_barrier")
		var dir := signf(_flail_angle)
		accel -= dir * barrier * over
		# 外向きの速度だけ強く殺す。戻る方向は邪魔しないので復帰は鈍らない。
		# 減衰係数は追加ばねに対する臨界減衰 2*sqrt(k) を使う
		if signf(_flail_vel) == dir:
			accel -= _flail_vel * 2.0 * sqrt(barrier)

	_flail_vel += accel * delta
	var max_speed: float = _v(&"flail_max_speed")
	_flail_vel = clampf(_flail_vel, -max_speed, max_speed)
	# ここでの clamp は保険。ソフトリミットが効いていれば通常は到達しない
	_flail_angle = clampf(_flail_angle + _flail_vel * delta, -limit, limit)

	for bone_name in flail_bones:
		var i := _skeleton.find_bone(bone_name)
		if i < 0:
			continue
		# ボーンごとに配分し、そのうえで自身の上限で頭打ちにする
		var weight: float = flail_bones[bone_name]
		var angle := clampf(_flail_angle * weight, -limit * absf(weight), limit * absf(weight))
		var offset := Quaternion.from_euler(Vector3(deg_to_rad(angle), 0.0, 0.0))
		# 土台の取り直しは「まだ持っていない」か「アニメーションが毎フレーム
		# このボーンを上書きしている」ときだけ。それ以外で取り直すと積み上がる
		if not _flail_base.has(i) or (_anim_driven.has(i) and _anim != null and _anim.is_playing()):
			_flail_base[i] = _skeleton.get_bone_pose_rotation(i)
		_skeleton.set_bone_pose_rotation(i, _flail_base[i] * offset)


# ═══════════════════════════════ ビューポート構築

func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "View3D"
	_viewport.size = view_size
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true          # 2Dの本編ワールドと混ざらないように隔離する
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	# 傾きと向きを同じノードでやると、Godot の既定オイラー順(YXZ)で軸が混ざり、
	# 真横を向かせた瞬間に傾きが奥行き方向へ倒れてしまう。2段に分けて分離する
	_rig = Node3D.new()
	_rig.name = "Rig"
	_viewport.add_child(_rig)

	_yaw = Node3D.new()
	_yaw.name = "Yaw"
	_rig.add_child(_yaw)
	var model_instance := model.instantiate()
	_yaw.add_child(model_instance)
	_apply_toon_shading(model_instance)

	_resolve_skeletons()

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_cam)

	_light = DirectionalLight3D.new()
	_viewport.add_child(_light)

	# own_world_3d なので環境も自前で持つ。これが無いと環境光が一切入らず影が黒く潰れる。
	# world_3d へ直接差すと生成タイミングによって null を掴むので、
	# WorldEnvironment ノードとして置く。own_world_3d なのでこの中だけに効く
	_env = Environment.new()
	_env.background_mode = Environment.BG_CLEAR_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	_viewport.add_child(world_env)

	# SubViewport の描画結果をこのスプライトの絵にする
	texture = _viewport.get_texture()

	# 輪郭線は3Dではなく、焼き上がったテクスチャのアルファを膨らませて描く
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	material = _outline_material

	_apply_visual_stats()


## リソース側の値をノードへ反映する。changed で呼ばれるので実行中の変更が即座に効く
func _apply_visual_stats() -> void:
	if visual_stats == null or _cam == null or _light == null:
		return          # ビューポート構築前に setter から呼ばれた場合は何もしない
	_cam.size = visual_stats.camera_view_units
	_cam.position = Vector3(0.0, visual_stats.camera_height, 6.0)
	_light.rotation_degrees = Vector3(visual_stats.light_pitch_deg,
		visual_stats.light_yaw_deg, 0.0)
	_light.light_energy = visual_stats.light_energy
	_light.light_color = visual_stats.light_color
	if _env:
		_env.ambient_light_color = visual_stats.ambient_color
		_env.ambient_light_energy = visual_stats.ambient_energy
	var s := visual_stats.world_height_px / float(view_size.y)
	scale = Vector2(s, s)
	for mat in _toon_materials:
		mat.set_shader_parameter(&"band_count", visual_stats.toon_band_count)
		mat.set_shader_parameter(&"shadow_floor", visual_stats.toon_shadow_floor)
	if _outline_material:
		_outline_material.set_shader_parameter(&"outline_color", visual_stats.outline_color)
		_outline_material.set_shader_parameter(&"outline_width", visual_stats.outline_width)


# ═══════════════════════════════ トゥーンシェーディング

## モデル内の全メッシュに、元の色/テクスチャは保ったまま段階式トゥーンの
## シェーダーを上書きする。モデルを差し替えても毎回自動で効く
func _apply_toon_shading(root: Node) -> void:
	if root is MeshInstance3D:
		_apply_toon_to_mesh(root as MeshInstance3D)
	for c in root.get_children():
		_apply_toon_shading(c)


func _apply_toon_to_mesh(mesh_instance: MeshInstance3D) -> void:
	var mesh := mesh_instance.mesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var src := mesh_instance.get_active_material(i)
		# 色/テクスチャの引き継ぎ元が読めないときは上書きしない。
		# ここで灰色のマテリアルへ差し替えてしまうと、原因(モデル側の問題)が
		# シェーダーのバグに見えてしまうため
		if not (src is BaseMaterial3D):
			push_warning("PlayerVisual: トゥーン非対応のマテリアル(%s)のため元のまま表示: %s [%d]"
				% [src.get_class() if src else "null", mesh_instance.name, i])
			continue
		var base := src as BaseMaterial3D
		if unlit_materials.has(StringName(base.resource_name)):
			# 取り込んだマテリアルはモデルを複数出したときに共有されるので、
			# 直に書き換えず複製したものを被せる
			var flat := base.duplicate() as BaseMaterial3D
			flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh_instance.set_surface_override_material(i, flat)
			continue
		if base.albedo_texture == null:
			push_warning("PlayerVisual: %s [%d] にテクスチャが無い(ベースカラーのみ)"
				% [mesh_instance.name, i])
		var mat := ShaderMaterial.new()
		mat.shader = TOON_SHADER
		mat.set_shader_parameter(&"albedo_color", base.albedo_color)
		if base.albedo_texture:
			mat.set_shader_parameter(&"albedo_texture", base.albedo_texture)
			mat.set_shader_parameter(&"use_texture", true)
		mat.set_shader_parameter(&"band_count", visual_stats.toon_band_count)
		mat.set_shader_parameter(&"shadow_floor", visual_stats.toon_shadow_floor)
		mesh_instance.set_surface_override_material(i, mat)
		_toon_materials.append(mat)


## 見た目パラメータの取得
func _v(param: StringName) -> Variant:
	return visual_stats.get(param)


func _find_node_of_type(n: Node, type_name: StringName) -> Node:
	if n.is_class(type_name):
		return n
	for c in n.get_children():
		var found := _find_node_of_type(c, type_name)
		if found:
			return found
	return null


func _collect_nodes_of_type(n: Node, type_name: StringName, out: Array[Node]) -> void:
	if n.is_class(type_name):
		out.append(n)
	for c in n.get_children():
		_collect_nodes_of_type(c, type_name, out)


# ═══════════════════════════════ 基本姿勢（アニメーション / ポーズ）

## モデルにアニメーションがあればそれを基本姿勢にする。
## 手付けモーションを入れた glb に差し替えれば、pose を消さなくても自動で切り替わる
func _setup_animation() -> void:
	_anim = _find_node_of_type(_yaw, "AnimationPlayer") as AnimationPlayer
	_anim_name = ""
	if _anim == null:
		return
	var list := _anim.get_animation_list()
	if list.is_empty():
		return
	if idle_animation != &"":
		if not _anim.has_animation(idle_animation):
			push_warning("PlayerVisual: アニメーション '%s' がモデルにありません（候補: %s）"
				% [idle_animation, ", ".join(list)])
			return
		_anim_name = String(idle_animation)
	else:
		_anim_name = list[0]
	_anim.play(_anim_name)


func _apply_pose() -> void:
	if _skeleton == null:
		return          # ビューポート構築前に setter から呼ばれた場合は何もしない
	if _anim_name != "":
		return          # アニメーションが姿勢を握っているので触らない
	if pose:
		pose.apply_to(_skeleton)
