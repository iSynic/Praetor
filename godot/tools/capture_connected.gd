extends SceneTree
## Real renderer captures on an off-screen window; no host UI automation.
var shell: Control
var out: String
var failures: Array = []

func _initialize() -> void: call_deferred("run")

func snapshot(name: String) -> void:
	while shell.bridge.busy: await process_frame
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image != null and not image.is_empty())
	assert(image.save_png(out.path_join("%dx%d-%s.png" % [root.size.x,root.size.y,name])) == OK)
	for key in ["Pages","Status","Save","Export"]:
		if not Rect2(Vector2.ZERO,Vector2(root.size)).encloses(shell.ui(key).get_global_rect()): failures.append(name+":"+key)

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Connected capture timeout"); quit(99))
	root.gui_embed_subwindows = true; out = OS.get_environment("CENTURIONS_CAPTURE_OUT")
	assert(not out.is_empty())
	shell = load("res://src/editor_shell.tscn").instantiate(); root.add_child(shell); await shell.startup_completed
	for dimensions in [Vector2i(1600,900),Vector2i(1200,720)]:
		root.size = dimensions
		await shell._show_route(0); await snapshot("project")
		await shell._show_route(1); await shell._select_stage(1); await snapshot("stage")
		await shell._show_route(3); shell.ui("MapCanvas").zoom = 1.0; shell.ui("MapCanvas").pan = Vector2(18,18); await snapshot("trigger-map")
		shell.maps.toolbar.select_tool("trigger"); await snapshot("placement")
		shell.maps.toolbar.select_tool("select")
		await shell._choose_program("menu",10,0); await shell._show_route(5); await snapshot("program")
		for entry in [["choice",10],["battle_extra",670],["battle",152],["monster",136],["reward",174]]:
			await shell.record_ui.open_record(entry[0],entry[1]); await snapshot(entry[0])
		shell.mission_ui.window.popup_centered(); await snapshot("recipe"); shell.mission_ui.window.hide()
		await shell.record_ui.open_record("reward",174); shell.record_ui.controls.credits.value = 26
		shell.guard(shell._show_route.bind(0)); await snapshot("draft-dialog")
		await shell._discard_continue()
	assert(failures.is_empty(),str(failures))
	var file := FileAccess.open(out.path_join("receipt.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"status":"passed","window_sizes":[[1600,900],[1200,720]],"outside_window":failures,"host_automation":false},"  ")); file.close()
	shell.bridge.stop(); print("CENTURIONS_CONNECTED_CAPTURES_PASSED"); quit()
