extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1)
	var path := args[0]
	var file := FileAccess.open(path.path_join("GODOT-LICENSE.txt"),FileAccess.WRITE)
	file.store_string(Engine.get_license_text()); file.close()
	file = FileAccess.open(path.path_join("GODOT-THIRD-PARTY.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"components":Engine.get_copyright_info(),"licenses":Engine.get_license_info()},"  ")); file.close()
	quit()
