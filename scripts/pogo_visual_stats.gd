@tool
class_name PogoVisualStats
extends Resource
##
## 見た目まわりの調整パラメータ一式。
## PogoStats と同じ思想で、数値はここに集約して .tres として保存する。
##
## @export_range を付けた変数は PogoTuner が自動でスライダー化するので、
## 新しいパラメータを足すときは必ず範囲付きで宣言すること。
##
## モデルやボーン名といった「配線」は PlayerVisual ノード側に残す。
## ここに置くのはプレイ中に触って詰める数値だけ。
##

## PogoTuner の見出し用。パラメータを追加したらここにも足す
const GROUPS := {
	"camera": ["camera_view_units", "camera_height", "world_height_px",
			   "model_yaw_right_deg", "model_yaw_left_deg",
			   "model_yaw_turn_speed", "facing_deadzone"],
	"light":  ["light_pitch_deg", "light_yaw_deg", "light_energy", "light_color",
			   "ambient_energy", "ambient_color"],
	"squash": ["ball_squash_y", "squash_recover_frames", "squash_compensate_character"],
	"flail":  ["flail_gain", "flail_stiffness", "flail_damping",
			   "flail_soft_deg", "flail_barrier", "flail_max_deg", "flail_max_speed"],
}

# ─────────────────────────────── カメラ
@export_group("Camera")
## カメラが縦に写す範囲 (3Dワールド単位)
@export_range(0.5, 20.0, 0.1) var camera_view_units := 3.6
## カメラの注視高さ (3Dワールド単位)。0 が足元
@export_range(0.0, 5.0, 0.05) var camera_height := 1.3
## camera_view_units ぶんを2D上で何pxとして描くか
@export_range(16.0, 512.0, 1.0) var world_height_px := 150.0
## 右へ進むときのモデルの向き (度)。0 でカメラ正面、90 で画面右（真横）
@export_range(-180.0, 180.0, 5.0) var model_yaw_right_deg := 45.0
## 左へ進むときのモデルの向き (度)。
## 右向き 45 度の鏡像は -45 度。135 度にすると右を向いたまま背面側の 3/4 になる
@export_range(-180.0, 180.0, 5.0) var model_yaw_left_deg := -45.0
## 向きを切り替えるときの追従速度。大きいほど素早く振り向く
@export_range(1.0, 40.0, 0.5) var model_yaw_turn_speed := 8.0
## この横速度 (px/s) を超えたときだけ向きを更新する。
## 小さすぎると停止間際に左右がばたつく
@export_range(0.0, 300.0, 5.0) var facing_deadzone := 30.0

# ─────────────────────────────── ライティング
@export_group("Light")
## キーライトの仰角 (度)。-90 で真上から、0 で真横から
@export_range(-90.0, 90.0, 1.0) var light_pitch_deg := -35.0
## キーライトの方位 (度)。0 でカメラ側から、-90 で画面左から
@export_range(-180.0, 180.0, 1.0) var light_yaw_deg := -40.0
## キーライトの強さ
@export_range(0.0, 8.0, 0.05) var light_energy := 1.2
## キーライトの色
@export var light_color := Color(1.0, 0.98, 0.94)
## 環境光（影側の持ち上げ）の強さ。0 だと影が真っ黒に落ちる
@export_range(0.0, 4.0, 0.05) var ambient_energy := 0.35
## 環境光の色。キーライトと補色寄りにすると立体感が出る
@export var ambient_color := Color(0.55, 0.62, 0.75)

# ─────────────────────────────── ボールの潰れ
@export_group("Squash")
## 着地時のボールの縦スケール。1.0 で潰さない
@export_range(0.5, 1.0, 0.01) var ball_squash_y := 0.9
## 潰れてから元に戻るまでのフレーム数 (60fps 換算)
@export_range(1, 30, 1) var squash_recover_frames := 6
## ボールを潰したときにキャラまで一緒に潰れるのを打ち消す
@export var squash_compensate_character := false

# ─────────────────────────────── 手足の振れ
@export_group("Flail")
## 着地の反発量(px/s)をどれだけ角速度(度/s)に変換するか
@export_range(0.0, 1.0, 0.005) var flail_gain := 0.45
## ばね定数。大きいほど素早く戻る
@export_range(0.0, 200.0, 1.0) var flail_stiffness := 55.0
## 減衰。大きいほど早く止まる
@export_range(0.0, 30.0, 0.5) var flail_damping := 7.0
## ソフトリミットの開始角 (度)。ここを超えると基本姿勢へ戻す力が急激に強くなる。
## 通常のバウンドがこの角度に届かないよう設定すれば、今の振れ心地は変わらない
@export_range(0.0, 90.0, 1.0) var flail_soft_deg := 22.0
## ソフトリミットの強さ。超過1度あたりに追加されるばね定数
@export_range(0.0, 3000.0, 10.0) var flail_barrier := 500.0
## 振れ幅の絶対上限 (度)。ソフトリミットが効いていれば通常ここには到達しない保険
@export_range(0.0, 90.0, 1.0) var flail_max_deg := 38.0
## 角速度の上限 (度/秒)。大きなバウンドで振れ角の上限に叩きつけられ、
## そこで張り付いてから鞭のように戻るのを防ぐ。
## 目安は flail_max_deg * sqrt(flail_stiffness)
@export_range(10.0, 2000.0, 10.0) var flail_max_speed := 300.0
