@tool
class_name PogoStats
extends Resource
##
## ポゴの挙動パラメータ一式。
## .tres として保存し、PogoPlayer.stats に差し込む。
## エディタで値を変えると changed シグナルが飛び、実行中でも即反映される。
##
## @export_range を付けた変数は PogoTuner が自動でスライダー化するので、
## 新しいパラメータを足すときは必ず範囲付きで宣言すること。
##

## PogoTuner の見出し用。パラメータを追加したらここにも足す
const GROUPS := {
	"bounce":    ["restitution", "bounce_add", "bounce_add_authority", "pogo_authority",
				  "max_bounce_speed"],
	"tilt":      ["tilt_speed", "stabilize_rate", "tilt_limit"],
	"charge":    ["charge_time", "charge_hold_time", "charge_mult",
				  "charge_restitution_mult", "super_mult", "super_cooldown"],
	"air":       ["gravity", "terminal_velocity", "air_drag",
				  "air_control", "air_control_max_speed"],
	"assist":    ["input_buffer_time", "landing_snap_angle", "landing_snap_hold_time",
				  "wall_bounce_scale", "ceiling_keep", "ground_normal_threshold"],
	"fall":      ["fall_threshold"],
	"collision": ["body_radius", "body_height", "safe_margin"],
}

# ─────────────────────────────── 反発
@export_group("Bounce")
## 地形反射成分の減衰。1.0で完全弾性
@export_range(0.0, 1.2, 0.01) var restitution := 0.62
## 接地時に必ず加算される最低跳躍量 (px/s)
@export_range(0.0, 1200.0, 10.0) var bounce_add := 380.0
## bounce_add をどれだけ射出方向（傾き角）に沿わせるか。
## 0.0 = 常に法線方向（＝真上に近い。傾けても飛距離が伸びない）
## 1.0 = 完全に傾き方向（＝飛距離は伸びるが、急斜面で地面に押し付ける向きになりうる）
@export_range(0.0, 1.0, 0.05) var bounce_add_authority := 0.7
## 射出方向の主導権。1.0でプレイヤーの傾き角そのまま、0.0で純粋な地形反射
@export_range(0.0, 1.0, 0.01) var pogo_authority := 0.75
## 反発後の速度上限 (px/s)
@export_range(500.0, 4000.0, 50.0) var max_bounce_speed := 1600.0

# ─────────────────────────────── 傾き
@export_group("Tilt")
## 左右入力による角速度 (deg/s)
@export_range(30.0, 720.0, 5.0) var tilt_speed := 180.0
## 入力を離したときに0度へ戻る速度 (deg/s)
@export_range(0.0, 720.0, 5.0) var stabilize_rate := 120.0
## 傾き可動域 (deg)
@export_range(5.0, 90.0, 1.0) var tilt_limit := 60.0

# ─────────────────────────────── チャージ
@export_group("Charge")
## 満タンまでの秒数
@export_range(0.05, 3.0, 0.05) var charge_time := 0.6
## チャージ中にその場で留まれる時間 (秒)。charge_time より短いと満タン前に強制発射される
@export_range(0.05, 3.0, 0.05) var charge_hold_time := 1.0
## 満タン時の最低跳躍量(bounce_add)の倍率
@export_range(1.0, 3.0, 0.05) var charge_mult := 1.5
## 満タン時の地形反射(restitution)の倍率。
## 1.0 にすると従来どおり bounce_add にしかチャージが効かず、
## 進入速度を溜めてからチャージしても高く飛べない。
## 1.0 より大きくすると「速度を稼いでから溜める」が報われるようになる
@export_range(1.0, 3.0, 0.05) var charge_restitution_mult := 1.45
## スーパージャンプ倍率（スキル解放時のみ有効）
@export_range(1.0, 4.0, 0.05) var super_mult := 1.8
## スーパージャンプのクールタイム (秒)
@export_range(0.0, 20.0, 0.5) var super_cooldown := 6.0

# ─────────────────────────────── 空中
@export_group("Air")
@export_range(0.0, 5000.0, 25.0) var gravity := 1800.0
## 落下速度の上限 (px/s)
@export_range(200.0, 4000.0, 50.0) var terminal_velocity := 2000.0
## 空中での水平方向の空気抵抗 (1秒あたりの減衰率)
@export_range(0.0, 1.0, 0.01) var air_drag := 0.05
## 空中で左右入力から得られる水平加速度 (px/s^2)。0 で空中制御なし
@export_range(0.0, 1500.0, 10.0) var air_control := 200.0
## 空中制御だけで到達できる水平速度の上限 (px/s)。
## これ以上速いときは進行方向への加速が効かなくなる（逆方向の減速は常に効く）
@export_range(0.0, 1500.0, 10.0) var air_control_max_speed := 400.0

# ─────────────────────────────── 補正（ストレス低減）
@export_group("Assist")
## 接地何秒前までの入力を拾うか
@export_range(0.0, 0.5, 0.01) var input_buffer_time := 0.13
## 接地時、この角度差以内なら法線に自動スナップ (deg)
@export_range(0.0, 20.0, 0.5) var landing_snap_angle := 5.0
## 着地スナップ後、スタビライズ補正（0度への自動復元）を止めておく時間 (秒)。
## 経過すると強制解除され、通常のスタビライズに戻る
@export_range(0.0, 2.0, 0.05) var landing_snap_hold_time := 0.5
## 壁面ヒット時の反発倍率。無限バウンド事故防止
@export_range(0.0, 1.0, 0.01) var wall_bounce_scale := 0.4
## 天井ヒット時の速度保持率
@export_range(0.0, 1.0, 0.01) var ceiling_keep := 0.2
## 法線のY成分がこれ以下なら「地面」扱い（-1.0が真上）
@export_range(-1.0, 0.0, 0.05) var ground_normal_threshold := -0.5

# ─────────────────────────────── 落下判定
@export_group("Fall")
## 連続下降がこの距離を超えて着地したら「落下」とみなす (px)
@export_range(200.0, 4000.0, 50.0) var fall_threshold := 900.0

# ─────────────────────────────── コリジョン形状
@export_group("Collision")
## カプセルの半径 (px)
@export_range(2.0, 64.0, 1.0) var body_radius := 14.0
## カプセルの全高 (px)
@export_range(8.0, 256.0, 1.0) var body_height := 56.0
## 形状の中心オフセット。足元を軸にしたいときに使う
@export var body_offset := Vector2.ZERO
## めり込み解決の余白 (px)
@export_range(0.0, 4.0, 0.1) var safe_margin := 0.4
