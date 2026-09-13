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
	&"upper_arm.L": 1.0, &"forearm.L": 1.0,
	&"upper_arm.R": 1.0, &"forearm.R": 1.0,
	&"thigh.L": 0.6, &"shin.L": 0.35,
	&"thigh.R": 0.6, &"shin.R": 0.35,
	# 首。頭 (spine.006 とその子の face) はこのチェーンの子なので、
	# ここを回せば頭も一緒に振れる
	&"spine.004": 0.4, &"spine.005": 0.25,
}

@export_group("Secondary")
## 頭の動きに遅れて付いてくるボーンと配分倍率。
## 耳は硬いばね、髪は柔らかいばねで、別々のパラメータで揺れる。
## 回転は親から子へ積み上がるので、先へ行くほど倍率を下げること
@export var ear_bones: Dictionary[StringName, float] = {
	&"ear.L": 1.0, &"ear.L.001": 0.5,
	&"ear.R": 1.0, &"ear.R.001": 0.5,
}
## 毛先ほど遅れて見えるよう、根元から先へ倍率を下げていく
@export var hair_bones: Dictionary[StringName, float] = {
	&"hair": 1.0, &"hair.001": 0.8, &"hair.002": 0.65,
	&"hair.003": 0.5, &"hair.004": 0.4,
}
@export_group("Ball")
## ボール（跳ねる玉）のメッシュ名。
## ボールはキャラクター本体とは別のスケルトンに入っているので、
## このメッシュを持つ方をボール用、持たない方をキャラクター本体として扱う。
## ボーン名はモデルによって変わる（"ball" だったり "Bone" だったり）ので、
## 名前が安定しているメッシュ側で見分ける
@export var ball_mesh_name: StringName = &"ball"

## ボールを描画するか。タイトル画面のようにキャラクターだけ見せたいときは false
@export var show_ball := true

@export_group("Animation")
## 再生するアニメーション名。空ならモデルが持つ最初のアニメーションを使う。
## モデルにアニメーションが無い場合は pose が使われる
@export var idle_animation: StringName = &""

## ゴール演出など、一時的に全身を動かすアニメーションの供給元。
## プレイヤーのモデルと別物でもよく、ボーン名が一致していればそのまま流し込める
## （使うのは回転トラックだけなので、モデル間のスケール差は影響しない）。
## 未設定なら DEFAULT_CLIP_PATH を使う
@export var clip_source: PackedScene

## ゴール到達時に再生するアニメーション名。空なら clip_source の最初のものを使う
@export var goal_clip: StringName = &""

@export_group("Toon")
## この名前のマテリアルはトゥーンを掛けず、陰影なし(unlit)で描く。
## ライトの向きで暗くなってほしくない部分（白目やハイライトなど）に使う
@export var unlit_materials: Array[StringName] = [&"white_unlit"]

## clip_source 未設定のときに使う全身アニメーション。
## この素材はリポジトリに含めていない（.gitignore 参照）ので preload は使えない。
## preload は解析時に解決されるため、ファイルが無いとこのスクリプト自体が
## コンパイルできずゲームが起動しなくなる。実行時に読んで、無ければ諦める
const DEFAULT_CLIP_PATH := "res://resources/model/Northern Soul Spin.fbx"

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
var _clip_player: AnimationPlayer      ## clip_source から取り込んだ全身アニメーション用
var _clip_names: PackedStringArray = []
var _clip_playing := false
var _clip_saved_pose: Array[Transform3D] = []          ## 再生前のボーン姿勢（戻す用）
var _clip_root: Node3D                 ## 全身の向きを持つノード（キャラ側スケルトンの親）
var _clip_root_rest := Quaternion.IDENTITY
var _clip_zoom := 1.0                  ## 1.0 以外なら枠を広げている最中
## クリップ再生中に髪を揺らすための、頭ボーンの前フレーム位置
var _clip_head_pos := Vector3.ZERO
var _clip_head_ready := false
var _clip_head_time := 0.0             ## 前フレームの再生位置。ループの折り返し検出用
var _player: PogoPlayer
var _flail_base: Dictionary[int, Quaternion] = {}   ## 振れを乗せる土台の姿勢
var _anim_driven: Dictionary[int, bool] = {}        ## アニメーションが毎フレーム上書きするボーン
var _flail_angle := 0.0
var _flail_vel := 0.0
## 耳・髪の揺れ。x = 前後(ローカルX軸まわり)、y = 左右(ローカルZ軸まわり)
## _drive は均した移動速度 (1000px/s を 1.0 とする)
var _drive := Vector2.ZERO
var _ear_angle := Vector2.ZERO
var _ear_vel := Vector2.ZERO
## 髪は1本のばねではなく、段ごとに別のばねを持たせて順に伝える。
## 同じ角度を全段へ配るとゴムのように一体で動いてしまう
var _hair_chain: Array[int] = []          ## ボーン番号（根元から毛先の順）
var _hair_weight: Array[float] = []
var _hair_ang: Array[Vector2] = []
var _hair_vel: Array[Vector2] = []
var _secondary_base: Dictionary[int, Quaternion] = {}
var _secondary_pos_base: Dictionary[int, Vector3] = {}
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
	# 親が PogoPlayer ならプレイ中の見た目として振る舞う。
	# タイトル画面のように単体で置いたときは、モデルとアニメーションだけを描く
	# （傾き・振れ・ボールの伸縮はプレイヤーの状態が要るので動かない）
	_player = get_parent() as PogoPlayer
	if model == null:
		push_warning("PlayerVisual: model が未設定です")
		return
	if visual_stats == null:
		visual_stats = PogoVisualStats.new()

	_build_viewport()
	_setup_animation()
	_setup_clips()
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
	if _rig == null:
		return
	# プレイヤーの状態が要る処理。タイトル画面のように単体で置いたときは飛ばす
	if _player:
		# 2Dの傾き角をそのまま3Dへ。カメラが+Z側から見ているのでZ軸回りが2Dの回転に対応する
		_rig.rotation.z = -deg_to_rad(_player.tilt_deg)
		_update_facing(_delta)
		_update_squash(_delta)
		_update_flail(_delta)
	# 頭が動いた結果に遅れて付いてくるので、体の処理より後に回す。
	# クリップ再生中は頭ボーンの動きから揺らすので、プレイヤーが居なくても走らせる
	_update_secondary(_delta)


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
		if _ball_mesh_of(skel) and skel.get_bone_count() > 0:
			_ball_skeleton = skel
			_ball_bone_idx = 0          # ボールは根ボーン1本で動かす
			_ball_base_scale = skel.get_bone_pose_scale(0)
			skel.visible = show_ball
		elif _skeleton == null:
			_skeleton = skel
	if _skeleton == null:
		push_warning("PlayerVisual: キャラクター本体の Skeleton3D が見つかりません")
	else:
		_char_base_y = _skeleton.position.y
	if _ball_skeleton == null:
		push_warning("PlayerVisual: '%s' メッシュを持つスケルトンが見つかりません" % ball_mesh_name)
		return

	# キャラをボールの上端に乗せ続けるため、伸縮でどれだけ上端が動くかを測っておく。
	# ボーン原点を基準にスケールが掛かるので、原点から上端までの距離がそのまま倍率になる
	var ball_mesh := _ball_mesh_of(_ball_skeleton)
	if ball_mesh:
		_ball_top_y = maxf(ball_mesh.get_aabb().end.y
			- _ball_skeleton.get_bone_global_rest(_ball_bone_idx).origin.y, 0.0)


## そのスケルトンがボールのメッシュを持っていれば返す。
## glTF取り込みで名前に連番が付くことがあるので前方一致で見る
func _ball_mesh_of(skel: Skeleton3D) -> MeshInstance3D:
	for c in skel.get_children():
		if c is MeshInstance3D and String(c.name).begins_with(String(ball_mesh_name)):
			return c as MeshInstance3D
	return null


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
		_skeleton.position.y = _char_base_y + _v(&"body_offset_y") \
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
	if _clip_playing:
		return          # 全身アニメーション中は姿勢をそちらに明け渡す

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


# ═══════════════════════════════ 耳・髪の揺れ

## プレイヤーの移動に遅れて耳と髪を付いてこさせる。
##
## 駆動源は 2D 側の移動速度。3Dビューポートの中ではキャラは動かないので、
## 頭のボーンの動きを見ると傾き(A/D入力)だけが入力になってしまい、
## 「キーを押した瞬間に髪が動く」不自然な見え方になっていた。
## 実際に跳んだり落ちたりした速度で振らせると、ジャンプに遅れて付いてくる
func _update_secondary(delta: float) -> void:
	if _skeleton == null or delta <= 0.0:
		return
	_build_hair_chain()

	# 画面の右方向が +x、下方向が +y。髪は進行方向と逆へ流れるので符号を反転する。
	# 1000px/s でちょうど gain と同じ角度(度)になるようにしておく
	var v := Vector2.ZERO
	if _clip_playing:
		v = _clip_head_drive(delta)
	elif _player:
		v = _player.velocity / 1000.0
	else:
		return
	var smooth: float = _v(&"secondary_smoothing")
	_drive = _drive.lerp(v, 1.0 - exp(-smooth * delta))
	# x(左右の移動) → Z軸まわりの振れ、y(上下の移動) → X軸まわりの振れ
	var swing := Vector2(_drive.y, -_drive.x)
	var limit: float = _v(&"secondary_max_deg")

	# 目標の振れ角へ引き寄せる形にする。
	# ばね定数で割られないので、硬さを変えても振れ幅は変わらず、
	# 追従の速さと戻り方だけが変わる
	# 耳: 硬いばね。すぐ戻る。
	# クリップ側は耳にキーを持っているので、再生中はそちらに任せる。
	# 重ねると、キーのある耳と無い耳で左右が食い違って見える
	if not _clip_playing:
		var ear_push: Vector2 = swing * _v(&"ear_gain")
		_ear_vel += (_v(&"ear_stiffness") * (ear_push - _ear_angle)
			- _v(&"ear_damping") * _ear_vel) * delta
		_ear_angle = (_ear_angle + _ear_vel * delta).limit_length(limit)
		_apply_secondary(ear_bones, _ear_angle)

	# 髪: 段ごとに別のばね。根元は移動速度、2段目以降は「一つ前の段の今の角度」を
	# 目標にする。段を追うごとに遅れが積み重なり、毛先へ波が伝わっていく
	var follow: float = _v(&"hair_follow")
	var follow_ramp: float = _v(&"hair_follow_ramp")
	var soften: float = _v(&"hair_softening")
	var last := maxi(_hair_chain.size() - 1, 1)
	var stiffness: float = _v(&"hair_stiffness")
	var damping: float = _v(&"hair_damping")
	var hair_push: Vector2 = swing * _v(&"hair_gain")
	# 落下中に根元を倒す角度。ばねの連鎖には混ぜず、描くときに根元へだけ足す。
	# 子ボーンは親の回転を継いで一緒に持ち上がるので、段ごとに足すと多重に掛かる
	var lift_deg: float = _v(&"hair_fall_lift")
	var lift := clampf(_drive.y, 0.0, 1.0) * lift_deg
	for i in _hair_chain.size():
		# 段が下るほど親に強く引かれるようにする
		var target := hair_push * _hair_weight[i]
		if i > 0:
			target = _hair_ang[i - 1] * follow * pow(follow_ramp, float(i - 1))
		# 毛先へ行くほど柔らかくして、さらに遅れて付いてくるようにする
		var k := stiffness * pow(soften, float(i))
		var c := damping * pow(soften, float(i))
		_hair_vel[i] += (k * (target - _hair_ang[i]) - c * _hair_vel[i]) * delta
		_hair_ang[i] = (_hair_ang[i] + _hair_vel[i] * delta).limit_length(limit)
		# 位置ずらしは根元を0、毛先を最大にする。根元が動くと付け根が外れて見える
		var applied := _hair_ang[i]
		if i == 0:
			applied.x += lift
		_apply_bone_swing(_hair_chain[i], applied, float(i) / float(last))


## クリップ再生中に髪を揺らすための駆動源。
##
## 再生中はプレイヤーが止まっている（タイトルではそもそも居ない）ので、
## 移動速度は使えない。代わりに、髪の付け根の親＝頭ボーンが画面上を
## どれだけ動いたかを測る。踊りの首振りやしゃがみがそのまま髪へ伝わる。
## 戻り値の単位は _player.velocity / 1000 と揃えてあるので、
## ゲーム中と同じ gain / ばねのパラメータがそのまま効く
func _clip_head_drive(delta: float) -> Vector2:
	if _hair_chain.is_empty():
		return Vector2.ZERO
	var head := _skeleton.get_bone_parent(_hair_chain[0])
	if head < 0:
		return Vector2.ZERO
	# スケルトンの外側（体の向き）ごと含めたいのでグローバルで測る
	var now: Vector3 = (_skeleton.global_transform
		* _skeleton.get_bone_global_pose(head)).origin
	# ループで先頭へ戻った瞬間は頭が瞬間移動する。そのまま速度として読むと
	# 一周ごとに髪が弾かれるので、折り返しのフレームは捨てる
	var at := _clip_player.current_animation_position if _clip_player else 0.0
	var looped := at < _clip_head_time
	_clip_head_time = at

	var drive := Vector2.ZERO
	if _clip_head_ready and not looped:
		var ref: float = maxf(_v(&"clip_head_speed_ref"), 0.001)
		# 3Dは上が +y、2Dは下が +y。ゲーム中の速度と符号を揃える
		var moved := Vector2(now.x - _clip_head_pos.x, _clip_head_pos.y - now.y)
		drive = moved / (delta * ref)
	_clip_head_pos = now
	_clip_head_ready = true
	return drive


## hair_bones の並び順（根元→毛先）をボーン番号の配列にしておく
func _build_hair_chain() -> void:
	if not _hair_chain.is_empty():
		return
	for bone_name in hair_bones:
		var i := _skeleton.find_bone(bone_name)
		if i < 0:
			continue
		_hair_chain.append(i)
		_hair_weight.append(hair_bones[bone_name])
		_hair_ang.append(Vector2.ZERO)
		_hair_vel.append(Vector2.ZERO)


func _apply_bone_swing(i: int, angle: Vector2, stretch_scale := 1.0) -> void:
	if not _secondary_base.has(i):
		_secondary_base[i] = _skeleton.get_bone_pose_rotation(i)
		_secondary_pos_base[i] = _skeleton.get_bone_pose_position(i)
	var rx := deg_to_rad(angle.x)
	var rz := deg_to_rad(angle.y)
	_skeleton.set_bone_pose_rotation(i,
		_secondary_base[i] * Quaternion.from_euler(Vector3(rx, 0.0, rz)))

	# 回転だけだと関節が硬く見えるので、振れた向きへ位置も逃がす。
	# ボーンは自分の +Y 方向へ伸びているので、Z軸まわりの振れは +X へ、
	# X軸まわりの振れは -Z へずらすと、曲がりを後押しする向きになる
	var stretch: float = _v(&"hair_stretch") * stretch_scale
	if stretch > 0.0:
		_skeleton.set_bone_pose_position(i,
			_secondary_pos_base[i] + Vector3(rz, 0.0, -rx) * stretch)


func _apply_secondary(bones: Dictionary[StringName, float], angle: Vector2) -> void:
	for bone_name in bones:
		var i := _skeleton.find_bone(bone_name)
		if i < 0:
			continue
		# 基準は最初に見たときの姿勢。毎フレーム取り直すと自分が書いた値を
		# 読み戻して角度が積み上がっていく
		if not _secondary_base.has(i):
			_secondary_base[i] = _skeleton.get_bone_pose_rotation(i)
		var w: float = bones[bone_name]
		var offset := Quaternion.from_euler(
			Vector3(deg_to_rad(angle.x * w), 0.0, deg_to_rad(angle.y * w)))
		_skeleton.set_bone_pose_rotation(i, _secondary_base[i] * offset)


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
	# ビューポートとカメラを同じ倍率で広げると、1ワールド単位あたりの画面px
	# (world_height_px / camera_view_units) も1ワールド単位あたりのテクセル数も
	# 変わらない。つまり大きさ・粗さはそのままで、周りの余白だけが増える
	var vsize := Vector2i(Vector2(view_size) * _clip_zoom)
	if _viewport and _viewport.size != vsize:
		_viewport.size = vsize
	_cam.size = visual_stats.camera_view_units * _clip_zoom
	_cam.position = Vector3(0.0, visual_stats.camera_height, 6.0)
	_light.rotation_degrees = Vector3(visual_stats.light_pitch_deg,
		visual_stats.light_yaw_deg, 0.0)
	_light.light_energy = visual_stats.light_energy
	_light.light_color = visual_stats.light_color
	if _env:
		_env.ambient_light_color = visual_stats.ambient_color
		_env.ambient_light_energy = visual_stats.ambient_energy
	# 枠を広げても画面上の大きさは変えない。ビューポートを z 倍したぶんは
	# ここで割り戻す（vsize.y = view_size.y * z なので、式としては元のまま）
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
	if _anim_name != "" or _clip_playing:
		return          # アニメーションが姿勢を握っているので触らない
	if pose:
		pose.apply_to(_skeleton)


# ═══════════════════════════════ 全身アニメーション（ゴール演出など）

## 全身アニメーションを再生する。名前を省略すると goal_clip、
## それも空なら clip_source の最初のアニメーションを使う。
## 再生中は手付けポーズ・手足の振れ・耳髪の揺れを止めてアニメーションに明け渡す
func play_clip(clip_name: StringName = &"") -> bool:
	if _clip_player == null or _skeleton == null:
		return false
	var clip := String(clip_name)
	if clip == "":
		clip = String(goal_clip)
	if clip == "":
		clip = _clip_names[0] if not _clip_names.is_empty() else ""
	if clip == "" or not _clip_player.has_animation(clip):
		push_warning("PlayerVisual: アニメーション '%s' がありません（候補: %s）"
			% [clip, ", ".join(_clip_names)])
		return false

	# 終わったあとに戻せるよう、今の姿勢を控えておく。
	# PogoPose は一部のボーンしか指定していないので、_apply_pose では戻しきれない
	_clip_saved_pose.resize(_skeleton.get_bone_count())
	for i in _skeleton.get_bone_count():
		_clip_saved_pose[i] = _skeleton.get_bone_pose(i)
	if _clip_root:
		_clip_root_rest = _clip_root.quaternion

	# 土台をレスト姿勢に戻してから流す。
	# PogoPose はボールにまたがる姿勢なので、そこへ立ち姿のモーションを重ねると
	# 二つの姿勢が足し合わさって体が倒れる。供給元のモデルでは、キーの無いボーンは
	# レスト姿勢のままなので、こちらもその状態に揃える
	_skeleton.reset_bone_poses()
	# レスト姿勢は「直立」なので、またがる姿勢の前提で置いてあるボールに
	# 脚が丸ごと埋まってしまう。踊っている間はボールを隠して地面に降りたことにする
	if _ball_skeleton:
		_ball_skeleton.visible = false
	# 土台が変わるので、揺れの基準と溜まった角度は捨てる
	_reset_secondary_state()
	_clip_playing = true
	_clip_zoom = maxf(visual_stats.clip_view_zoom, 1.0)
	_apply_visual_stats()
	_clip_player.play(clip)
	return true


## ゴール到達時の勝利モーション
func play_goal_clip() -> bool:
	return play_clip(goal_clip)


func is_clip_playing() -> bool:
	return _clip_playing


## 再生を止めて、始める前の姿勢へ戻す。
## 揺れの基準も取り直す（アニメーションが書いた値を基準にすると角度が流れていく）
func stop_clip() -> void:
	if not _clip_playing:
		return
	_clip_playing = false
	_clip_zoom = 1.0
	_apply_visual_stats()
	if _clip_player:
		_clip_player.stop()
	if _ball_skeleton:
		_ball_skeleton.visible = show_ball
	if _clip_root:
		_clip_root.quaternion = _clip_root_rest
	if _skeleton:
		for i in mini(_clip_saved_pose.size(), _skeleton.get_bone_count()):
			var saved := _clip_saved_pose[i]
			_skeleton.set_bone_pose_position(i, saved.origin)
			_skeleton.set_bone_pose_rotation(i, saved.basis.get_rotation_quaternion())
			_skeleton.set_bone_pose_scale(i, saved.basis.get_scale())
	_clip_saved_pose.clear()
	_flail_base.clear()
	_flail_angle = 0.0
	_flail_vel = 0.0
	_reset_secondary_state()
	_apply_pose()
	_capture_flail_base()


## 揺れの基準と溜まった角度を捨てる。
## 土台の姿勢が変わったあとに呼ぶこと。古い基準のまま続けると、
## 自分が書いた値を基準として読み戻して角度が流れていく
func _reset_secondary_state() -> void:
	_secondary_base.clear()
	_secondary_pos_base.clear()
	_drive = Vector2.ZERO
	_ear_angle = Vector2.ZERO
	_ear_vel = Vector2.ZERO
	_clip_head_ready = false
	_clip_head_time = 0.0
	for i in _hair_ang.size():
		_hair_ang[i] = Vector2.ZERO
		_hair_vel[i] = Vector2.ZERO


## clip_source のアニメーションをプレイヤーのリグ向けに載せ替えて持っておく。
## 供給元のモデルは読み取るだけで、ビューポートには入れない
func _setup_clips() -> void:
	var source := clip_source
	if source == null and ResourceLoader.exists(DEFAULT_CLIP_PATH):
		source = load(DEFAULT_CLIP_PATH) as PackedScene
	if source == null or _skeleton == null or _yaw == null:
		return
	var src := source.instantiate()
	var src_anim := _find_node_of_type(src, "AnimationPlayer") as AnimationPlayer
	if src_anim == null:
		push_warning("PlayerVisual: clip_source に AnimationPlayer がありません")
		src.free()
		return

	_clip_root = _skeleton.get_parent() as Node3D
	var lib := AnimationLibrary.new()
	for clip in src_anim.get_animation_list():
		var converted := _retarget_clip(src_anim.get_animation(clip), src)
		if converted.get_track_count() == 0:
			push_warning("PlayerVisual: '%s' に流し込めるトラックがありません（ボーン名の不一致）"
				% clip)
			continue
		lib.add_animation(clip, converted)
		_clip_names.append(clip)
	src.free()
	if _clip_names.is_empty():
		return

	_clip_player = AnimationPlayer.new()
	_clip_player.name = "ClipPlayer"
	# root_node の既定は "..", つまり親の _yaw。トラックのパスもそこ基準で作る
	_yaw.add_child(_clip_player)
	_clip_player.add_animation_library("", lib)


## 別モデルのアニメーションをこちらのリグへ載せ替える。
##
## 使うのは回転トラックだけ。位置トラックはモデルごとに単位（骨の長さ）が違うので
## 流し込むと体が崩れる。回転はリグの構造が同じなら単位に依らずそのまま通る。
## ルートの移動も捨てる（ボールの上から滑り出てしまうため）が、
## 向きだけは残したいので、軸変換ぶんを打ち消してからこちらのノードへ乗せ替える
func _retarget_clip(src: Animation, src_root: Node) -> Animation:
	var skel_path := String(_yaw.get_path_to(_skeleton))
	var root_path := String(_yaw.get_path_to(_clip_root)) if _clip_root else ""
	var out := Animation.new()
	out.length = src.length
	out.loop_mode = Animation.LOOP_LINEAR      # 次のステージへ移るまで踊り続ける
	for t in src.get_track_count():
		if src.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var path := src.track_get_path(t)
		var bone := String(path.get_concatenated_subnames())
		var dest := ""
		var fix := Quaternion.IDENTITY
		if bone != "":
			if _skeleton.find_bone(bone) < 0:
				continue          # こちらに無いボーン（末端の _end など）は捨てる
			dest = "%s:%s" % [skel_path, bone]
		else:
			if root_path == "":
				continue
			var node := src_root.get_node_or_null(path) as Node3D
			if node == null:
				continue
			# キーは供給元ノードの絶対姿勢。供給元は軸変換で寝ている（Z-up のまま
			# ノード側で -90 度倒している）ので、その基準を割ってこちらの基準へ掛け直す。
			# 右から掛けること。左から掛けると差分を供給元のローカル軸で解釈してしまい、
			# 向き変え(ヨー)が横転(ロール)になって体が倒れる
			fix = node.quaternion.inverse() * _clip_root.quaternion
			dest = root_path
		var dst := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(dst, NodePath(dest))
		for k in src.track_get_key_count(t):
			out.rotation_track_insert_key(dst, src.track_get_key_time(t, k),
				(src.track_get_key_value(t, k) as Quaternion) * fix)
	return out
