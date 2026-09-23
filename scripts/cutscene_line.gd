@tool
class_name CutsceneLine
extends Resource
##
## イベント1コマぶんの指定。テキストと、そのコマで起きる見た目の変化をまとめる。
##
## 画像は「指定したものだけ変わる」方式。null のままなら前のコマの状態を引き継ぐので、
## 会話が続く間は同じ立ち絵を並べ直す必要がない。
## 消したいときは clear_left / clear_right を立てる。
##

enum Side { NONE, LEFT, RIGHT, BOTH }

## ポップアップの種別。見た目と消え方が変わる
enum PopupKind { TALK, MISS }

# ─────────────────────────────── テキスト
## 話者名。空ならネームプレートを出さない
@export var speaker := ""
## 本文。BBCode が使える
@export_multiline var text := ""

# ─────────────────────────────── 立ち絵
@export_group("Portrait")
## どちら側が話しているか。話者側だけ明るくし、反対側は暗くする
@export var speaking := Side.NONE
## 左の立ち絵を差し替える。null なら変更しない
@export var left: Texture2D
## 左の立ち絵を消す
@export var clear_left := false
## 右の立ち絵を差し替える。null なら変更しない
@export var right: Texture2D
## 右の立ち絵を消す
@export var clear_right := false
## 差し替え時に外側からスライドインさせる
@export var slide_in := true

# ─────────────────────────────── 背景
@export_group("Background")
## 背景画像を差し替える。null なら変更しない
@export var background: Texture2D
## 背景を消す（暗転）
@export var clear_background := false
## 背景を隠す強さ。-1 なら変えない（前のコマの状態が続く）。
##
## 元の絵とは混ざらない。0 より大きければ出るのは常に 100% モザイクで、
## この値が決めるのは目の粗さ。0 で元の絵と見分けがつかない細かさ、
## 1 で一番粗い。0.5 なら中くらいの目で、やはり元の絵は透けない。
## ヒント中は 1 にしておき、正体が分かるコマで 0 に戻す、といった使い方をする
@export_range(-1.0, 1.0, 0.05) var bg_hide := -1.0
## モザイクの動かし方。-1 なら変えない（Cutscene 側の既定か、前のコマが続く）。
##   0 … 流れる      : 目が画面をゆっくり滑っていく
##   1 … 中心から拡縮: 画面中心を軸に、目が大きくなったり小さくなったりする
##   2 … 中心から放射: 中心ほど目が細かく外ほど粗い。目は外へ流れ続ける
##
## 隠し具合が 0 でないコマで切り替えると見た目が飛ぶので、
## 隠し始めるコマ（bg_hide を 0 から上げるコマ）で一緒に指定するとよい
@export_range(-1, 2, 1) var bg_pattern := -1

# ─────────────────────────────── カメラ揺れ
@export_group("Camera")
## そのコマで画面を揺らす振れ幅 (px)。0 なら揺らさない。
## 8 で小突かれた程度、24 で殴られた感じ、48 で地面が揺れる。
## 暗幕・背景・立ち絵・ウインドウがまとめて揺れる
@export_range(0.0, 48.0, 1.0) var shake := 0.0
## 揺れが収まるまでの秒数。0 なら Cutscene 側の既定値を使う
@export_range(0.0, 2.0, 0.05) var shake_time := 0.0

# ─────────────────────────────── ポップアップ（カットイン）
@export_group("Popup")
## このコマで重ねる一枚絵。null なら出さない。
## 立ち絵の上に出て、hold のあと自分で消えるので、次のコマで消す指定はいらない
@export var popup: Texture2D
## 枠の色と消え方。資材リストの取り決めに合わせてある
##   TALK … 青枠。実況ポップアップ。そのまま消える
##   MISS … 赤枠。誤答カットイン。ヒビが入って割れる
@export var popup_kind := PopupKind.TALK
## 出しておく秒数。0 なら Cutscene 側の既定値を使う。
## 「気づき」を見せるコマは 1.5 くらいためる
@export_range(0.0, 5.0, 0.1) var popup_hold := 0.0

# ─────────────────────────────── 音
@export_group("Audio")
## そのコマから流すBGM。null なら変えない（前の曲がそのまま続く）。
## 鳴っている曲と同じものを指定した場合は鳴らし直さない
@export var bgm: AudioStream
## そこでBGMを止める。台本の「ここで初めてBGMを止め」に当たる指定
@export var bgm_stop := false
## BGMの切り替え・停止にかける秒数。0 なら Cutscene 側の既定値を使う
@export_range(0.0, 5.0, 0.1) var bgm_fade := 0.0
## そのコマで一度だけ鳴らす効果音。缶を開ける音のような、絵と対になるもの
@export var sfx: AudioStream

# ─────────────────────────────── 進行
@export_group("Timing")
## 0 なら入力待ち。0 より大きいとその秒数で自動的に次へ進む
@export_range(0.0, 10.0, 0.1) var auto_advance := 0.0
## このコマの前に挟む待ち時間 (秒)。演出の間合い調整用
@export_range(0.0, 5.0, 0.1) var delay := 0.0

# ─────────────────────────────── 演出メモ
@export_group("Note")
## 台本の〔演出：…〕。このコマで起きることの覚え書きで、ゲーム中には出ない。
## Cutscene の show_notes を立てたときだけ、確認用に画面へ表示する。
##
## 台本が正なので、ここに書いても次の再生成で上書きされる。
## 直すときは台本 (resources/scenario-v4.md) 側を直すこと
@export_multiline var note := ""

# ─────────────────────────────── 台本との突き合わせ用
@export_group("Merge")
## 台本には無い、CutsceneEditor で手を入れて挿したコマ。
##
## tools/make_cutscenes.gd は台本からコマを作り直すので、この印が無いコマは
## 台本に同じ本文が見つからなければ消える。印が付いたコマは台本の外のものとして、
## 「直前にあった台本のコマ」を手掛かりに元の位置へ戻される。
## 立ち絵や背景だけを変える無音の間や、台本に無い掛け合いを足すときに立てる
@export var inserted := false
