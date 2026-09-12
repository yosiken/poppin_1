extends SceneTree

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var inst := (load("res://scenes/samples/PlayerShadingSample.tscn") as PackedScene).instantiate()
	root.add_child(inst)
	for i in 60:
		await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var out := "user://pose_check.png"
	img.save_png(out)
	print("SHOT ", ProjectSettings.globalize_path(out), " ", img.get_size())
	quit()
