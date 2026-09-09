extends SceneTree

const REFERENCED := [
	"DEF-upper_arm.L", "DEF-forearm.L", "DEF-upper_arm.R", "DEF-forearm.R",
	"DEF-thigh.L", "DEF-shin.L", "DEF-thigh.R", "DEF-shin.R",
	"DEF-spine.001", "DEF-spine.002", "DEF-spine.004", "DEF-spine.005",
]

var _meshes: Array[String] = []
var _skel: Skeleton3D
var _anim: AnimationPlayer


func _initialize() -> void:
	var ps: PackedScene = load("res://resources/model/player_7.blend")
	var root := ps.instantiate()
	_tree(root, 0)
	_walk(root)

	print("MESHES(", _meshes.size(), "): ", ", ".join(_meshes).substr(0, 300))
	if _skel:
		print("BONES: ", _skel.get_bone_count())
		for i in _skel.get_bone_count():
			var parent := _skel.get_bone_parent(i)
			print("  [", i, "] ", _skel.get_bone_name(i), " parent=",
				_skel.get_bone_name(parent) if parent >= 0 else "-",
				" y=", "%.3f" % _skel.get_bone_global_rest(i).origin.y)
		var missing: Array[String] = []
		for b in REFERENCED:
			if _skel.find_bone(b) < 0:
				missing.append(b)
		print("MISSING REFERENCED: ", missing)
	else:
		print("BONES: no Skeleton3D")
	if _anim:
		for a in _anim.get_animation_list():
			var ani := _anim.get_animation(a)
			var bones := {}
			for t in ani.get_track_count():
				bones[String(ani.track_get_path(t).get_concatenated_subnames())] = true
			print("ANIM '", a, "' len=", ani.length, " tracks=", ani.get_track_count(),
				" bones=", bones.size())
	else:
		print("ANIMS: no AnimationPlayer")
	quit()


func _tree(n: Node, depth: int) -> void:
	var extra := ""
	if n is Skeleton3D:
		var s := n as Skeleton3D
		var names: Array[String] = []
		for i in mini(s.get_bone_count(), 4):
			names.append(s.get_bone_name(i))
		extra = " bones=%d %s" % [s.get_bone_count(), names]
	print("TREE ", "  ".repeat(depth), n.name, " (", n.get_class(), ")", extra)
	for c in n.get_children():
		_tree(c, depth + 1)


func _walk(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		_meshes.append(mi.name)
		var m := mi.mesh
		if m:
			for i in m.get_surface_count():
				var act := mi.get_active_material(i)
				var surf := m.surface_get_material(i) if m is ArrayMesh else null
				print("MAT ", mi.name, "[", i, "] name=",
					act.resource_name if act else "-", " active=",
					act.get_class() if act else "null",
					" surface=", surf.get_class() if surf else "null",
					" albedo_tex=", (act as BaseMaterial3D).albedo_texture != null \
						if act is BaseMaterial3D else "n/a")
		var skel := mi.get_parent() as Skeleton3D
		if skel:
			print("AABB ", mi.name, " ", mi.get_aabb(), " skel_bones=", skel.get_bone_count(),
				" bone0_rest_origin=", skel.get_bone_global_rest(0).origin,
				" mi_pos=", mi.position)
	if n is Skeleton3D:
		_skel = n
	if n is AnimationPlayer:
		_anim = n
	for c in n.get_children():
		_walk(c)
