extends SceneTree
## Drives the guide window on the real renderer: it opens from the header mark, shows its chapters and pictures, and goes to a
## chapter chosen in the contents. Needs CENTURIONS_PROJECT to be an imported level, CENTURIONS_INSTALLATION and CENTURIONS_CAPTURE_OUT.
var shell: Control
var out := ""
var failures: Array = []


func _initialize() -> void:
	call_deferred("run")


func settle() -> void:
	while shell.bridge.busy: await process_frame
	for _frame in range(4): await process_frame
	await RenderingServer.frame_post_draw


func snapshot(name: String) -> void:
	await settle()
	var image := root.get_texture().get_image()
	if image == null or image.save_png(out.path_join(name + ".png")) != OK: failures.append(name)


func expect(passed: bool, message: String) -> void:
	if not passed: failures.append(message)


func run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Guide capture timed out"); quit(99))
	root.gui_embed_subwindows = true
	out = OS.get_environment("CENTURIONS_CAPTURE_OUT")
	if out.is_empty(): push_error("CENTURIONS_CAPTURE_OUT required"); quit(1); return
	shell = load("res://src/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await shell.startup_completed
	root.size = Vector2i(1600, 900)
	shell.ui("GuideMark").pressed.emit()
	await settle()
	var guide: Window = shell.guide_window
	expect(guide.visible, "The header mark opens the guide")
	expect(guide.document.chapters.size() >= 10, "The guide holds its chapters")
	await snapshot("1600x900-guide")
	await guide.show_guide("Anatomy of a Trigger")
	await snapshot("1600x900-guide-trigger")
	await guide.show_guide("Anatomy of an Encounter")
	await snapshot("1600x900-guide-encounter")
	shell.bridge.stop()
	if failures.is_empty(): print("CENTURIONS_GUIDE_CAPTURES_PASSED")
	else: push_error("Guide capture failures: " + str(failures))
	quit(0 if failures.is_empty() else 1)
