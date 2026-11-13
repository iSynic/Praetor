extends SceneTree
## Drives Play from here on the real renderer: the project is exported into a
## scratch copy of the installation and replayed through centurions-tools.exe.
## Needs CENTURIONS_INSTALLATION to name a folder that holds the classic
## installation, The New Centurions.exe and centurions-tools.exe, CENTURIONS_PROJECT
## to be a scenario made from a template, and CENTURIONS_CAPTURE_OUT.
var shell: Control
var out := ""
var failures: Array = []


func _initialize() -> void:
	call_deferred("run")


func settle() -> void:
	while shell.bridge.busy or shell.play.running: await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func snapshot(name: String) -> void:
	await settle()
	var image := root.get_texture().get_image()
	if image == null or image.save_png(out.path_join(name + ".png")) != OK: failures.append(name)


func expect(passed: bool, message: String) -> void:
	if not passed: failures.append(message)


func run() -> void:
	create_timer(160).timeout.connect(func(): push_error("Play capture timed out"); quit(99))
	root.gui_embed_subwindows = true
	out = OS.get_environment("CENTURIONS_CAPTURE_OUT")
	if out.is_empty(): push_error("CENTURIONS_CAPTURE_OUT required"); quit(1); return
	shell = load("res://src/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await shell.startup_completed
	shell.settings.set_value("output_parent", out)
	expect(shell.play.unavailable().is_empty(), "The folder must hold the runtime: " + shell.play.unavailable())
	expect(not shell.ui("PlayFromHere").disabled, "Play from here must be available beside the runtime")
	expect(PlaySession.route(Vector2i(2, 2), Vector2i(4, 1)).size() == 3, "The route is a step for each cell")
	for size in [Vector2i(1600, 900), Vector2i(1200, 720)]:
		root.size = size
		await session("%dx%d" % [size.x, size.y])
	shell.bridge.stop()
	if failures.is_empty(): print("CENTURIONS_PLAY_CAPTURES_PASSED")
	else: push_error("Play capture failures: " + str(failures))
	quit(0 if failures.is_empty() else 1)


const PlaySession = preload("res://src/services/play_session.gd")


func session(tag: String) -> void:
	await shell._show_route(shell.ROUTES.find("Maps"))
	shell.maps.canvas.selected_cell = Vector2i(4, 2)
	await shell.play_from_here()
	await settle()
	var names: Array = shell.play.commands().map(func(command): return PlaySession.name_of_command(command))
	expect(shell.play.active and "EnterMission First Patrol" in names, "The session must enter the mission: " + str(names))
	expect(shell.play.log.size() >= 3, "The runtime must answer each command")
	expect(shell.problems.play_tree.get_root().get_child_count() == shell.play.log.size(), "The Play log must list every command")
	expect(shell.play_bar.visible, "The bar must show while playing")
	expect(not DirAccess.dir_exists_absolute(shell.folder.path_join("Scenarios/First Patrol")), "The installation itself is never written")
	await snapshot(tag + "-play")
	await shell.play.continue_play()
	await settle()
	await snapshot(tag + "-play-continue")
	shell.play.stop()
	await settle()
	expect(not shell.play_bar.visible and not shell.play.active, "Stop must close the session")
