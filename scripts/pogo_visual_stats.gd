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
	"squash": ["ball_squash_y", "squash_recover_frames", "ball_stretch_y", "stretch_speed_ref",
			   "body_follow_ball", "body_offset_y"],
	"flail":  ["flail_gain", "flail_stiffness", "flail_damping",
			   "flail_soft_deg", "flail_barrier", "flail_max_deg", "flail_max_speed"],
	"secondary": ["secondary_smoothing", "secondary_max_deg",
				  "ear_gain", "ear_stiffness", "ear_damping",
				  "hair_gain", "hair_stiffness", "hair_damping",
				  "hair_follow", "hair_follow_ramp", "hair_softening", "hair_stretch",
				  "hair_fall_lift"],
	"toon":   ["toon_band_count", "toon_shadow_floor"],
	"outline": ["outline_color", "outline_width"],
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
## キーライトの方位 (度)。0 でカメラ側から奥へ、-90 で画面左から
@export_range(-180.0, 180.0, 1.0) var light_yaw_deg := -10.0
## キーライトの強さ
@export_range(0.0, 8.0, 0.05) var light_energy := 1.2
## キーライトの色
@export var light_color := Color(1.0, 0.98, 0.94)
## 環境光（影側の持ち上げ）の強さ。0 だと影が真っ黒に落ちる
@export_range(0.0, 4.0, 0.05) var ambient_energy := 0.35
## 環境光の色。キーライトと補色寄りにすると立体感が出る
@export var ambient_color := Color(0.55, 0.62, 0.75)

# ─────────────────────────────── ボールの潰れ・伸び
@export_group("Squash")
## 着地時のボールの縦スケール。1.0 で潰さない
@export_range(0.5, 1.0, 0.01) var ball_squash_y := 0.9
## 潰れてから元に戻るまでのフレーム数 (60fps 換算)
@export_range(1, 30, 1) var squash_recover_frames := 6
## 空中で最も速いときのボールの縦スケール。1.0 で伸ばさない
@export_range(1.0, 1.6, 0.01) var ball_stretch_y := 1.15
## 縦の伸びが最大になる上下方向の速さ (px/s)
@export_range(100.0, 2000.0, 10.0) var stretch_speed_ref := 900.0
## ボールの伸縮にキャラがどれだけ付いていくか。1.0 でボール上端にぴったり乗る。
## 0 にするとキャラは動かず、ボールだけが伸び縮みする
@export_range(0.0, 1.5, 0.05) var body_follow_ball := 1.0
## キャラをボールに対して上下へずらす (3Dワールド単位)。
## 足がボールに埋まるときは上げる（プラス）、浮くときは下げる
@export_range(-0.5, 0.5, 0.01) var body_offset_y := 0.15

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

# ─────────────────────────────── 耳・髪の揺れ
@export_group("Secondary")

## 速度をどれだけ均すか (1/秒)。小さいほど滑らかだが反応が鈍る
@export_range(1.0, 300.0, 1.0) var secondary_smoothing := 18.0
## 振れ角の上限 (度)
@export_range(0.0, 180.0, 1.0) var secondary_max_deg := 80.0
## 耳の振れ幅。頭の速度を振れ角へ変換する強さ (度 / 単位速度)
@export_range(0.0, 1200.0, 1.0) var ear_gain := 135.0
## 耳のばね定数。大きいほど硬く、すぐ元へ戻る
@export_range(1.0, 500.0, 1.0) var ear_stiffness := 87.0
## 耳の減衰。大きいほど早く止まる
@export_range(0.0, 20.0, 0.01) var ear_damping := 12.0
## 髪の振れ幅。耳より大きくすると、頭に引きずられて流れる感じが出る
@export_range(0.0, 1200.0, 1.0) var hair_gain := 145.0
## 髪のばね定数。小さいほど柔らかく、大きく遅れて流れる
@export_range(1.0, 500.0, 1.0) var hair_stiffness := 79.0
## 髪の減衰。小さいほど長く揺れ続ける
@export_range(0.0, 20.0, 0.01) var hair_damping := 5.39
## 次の段が一つ前の段をどれだけ追いかけるか。
## 1.0 に近いほど毛先まで大きく振れ、小さいほど根元で収まる
@export_range(0.0, 3.0, 0.01) var hair_follow := 0.67
## 段が下るごとに hair_follow を何倍していくか。
## 1.0 で全段同じ、1 より大きいと毛先ほど親に強く引かれて大きく振れる
@export_range(0.5, 3.0, 0.01) var hair_follow_ramp := 1.2
## 毛先へ行くほどばねを柔らかくする割合。
## 小さいほど毛先が遅れて付いてきて、しなりが強くなる
@export_range(0.3, 2.0, 0.05) var hair_softening := 0.8
## 振れた向きへボーンの位置もずらす量 (3Dワールド単位 / ラジアン)。
## 回転だけだと関節が硬く見えるので、少し伸びる方向へ逃がして柔らかさを出す。
## これは毛先での量で、根元は 0、そこから毛先へ向けて線形に増える。
## 根元を動かすと髪の付け根が頭から外れて見えるため。0 で位置は動かさない
@export_range(0.0, 0.5, 0.005) var hair_stretch := 0.185
## 落下中に髪の根元を持ち上げる角度 (度)。下向きの速度1000px/sでこの値になる。
## 左右の流れとは別枠で、付け根から角度が付いて毛先が肩の上へ回る
@export_range(0.0, 180.0, 1.0) var hair_fall_lift := 48.0

# ─────────────────────────────── トゥーンシェーディング
@export_group("Toon")
## キーライトの当たり方を何階調に分けるか
@export_range(2, 6, 1) var toon_band_count := 4
## 一番暗い帯の明るさ。0にすると陰が真っ黒になる
@export_range(0.0, 1.0, 0.01) var toon_shadow_floor := 0.2

# ─────────────────────────────── 輪郭線
@export_group("Outline")
## 輪郭線の色。アルファを0にすると輪郭が消える
@export var outline_color := Color(0.08, 0.07, 0.1, 1.0)
## 輪郭線の太さ。3Dを焼いたテクスチャのテクセル単位なので、
## view_size を変えると画面上の見た目の太さも変わる。0 で無効
@export_range(0.0, 8.0, 0.5) var outline_width := 2.0
