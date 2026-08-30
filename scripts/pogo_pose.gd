@tool
class_name PogoPose
extends Resource
##
## ボーンごとの「rest からの回転オフセット」を持つポーズ。
##
## 設計方針:
##   - 絶対角ではなく rest からの差分で持つ。全部空なら素のバインドポーズに戻る
##   - モデルを差し替えてもボーン名さえ合っていれば流用できる
##   - .tres なのでエディタで値を変えると changed が飛び、実行中でも即反映される
##
## ラグドールは「現在のボーン姿勢」から始まるので、これがそのまま
## ラグドール突入時の初期姿勢にもなる。
##

## ボーン名 -> オイラー角オフセット (度)
@export var rotations: Dictionary[StringName, Vector3] = {}


## スケルトンへ適用する。rotations に無いボーンは rest のまま
func apply_to(skel: Skeleton3D) -> void:
	if skel == null:
		return
	for bone_name in rotations:
		var i := skel.find_bone(bone_name)
		if i < 0:
			push_warning("PogoPose: ボーン '%s' が見つかりません" % bone_name)
			continue
		var rest_q := skel.get_bone_rest(i).basis.get_rotation_quaternion()
		var offset := Quaternion.from_euler(Vector3(rotations[bone_name]) * (PI / 180.0))
		skel.set_bone_pose_rotation(i, rest_q * offset)


## 全ボーンを rest へ戻す
func reset(skel: Skeleton3D) -> void:
	if skel == null:
		return
	for i in skel.get_bone_count():
		skel.set_bone_pose_rotation(i, skel.get_bone_rest(i).basis.get_rotation_quaternion())
