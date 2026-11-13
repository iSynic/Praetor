extends SceneTree
## Drives navigation on the real renderer: Go to with its prefixes, Find uses
## with Replace, View flow, the Problems page with its capability map and the
## findings in the dock. Needs CENTURIONS_PROJECT to be an imported level,
## CENTURIONS_INSTALLATION and CENTURIONS_CAPTURE_OUT.
var shell: Control
var out := ""
var failures: Array = []


func _initialize() -> void:
	call_deferred("run")


func settle() -> void:
	while shell.bridge.busy: await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func snapshot(name: String) -> void:
	await settle()
	var image := root.get_texture().get_image()
	if image == null or image.save_png(out.path_join(name + ".png")) != OK: failures.append(name)


func expect(passed: bool, message: String) -> void:
	if not passed: failures.append(message)


func inside(dialog: Object, label: String, size: Vector2i) -> void:
	if not Rect2(Vector2.ZERO, Vector2(size)).encloses(dialog.panel_rect()): failures.append("%s exceeds the %s window: %s" % [label, str(size), str(dialog.panel_rect())])


func run() -> void:
	create_timer(170).timeout.connect(func(): push_error("Navigation capture timed out"); quit(99))
	root.gui_embed_subwindows = true
	out = OS.get_environment("CENTURIONS_CAPTURE_OUT")
	if out.is_empty(): push_error("CENTURIONS_CAPTURE_OUT required"); quit(1); return
	shell = load("res://src/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await shell.startup_completed
	for size in [Vector2i(1600, 900), Vector2i(1200, 720)]:
		root.size = size
		await session(size)
	shell.bridge.stop()
	if failures.is_empty(): print("CENTURIONS_NAVIGATION_CAPTURES_PASSED")
	else: push_error("Navigation capture failures: " + str(failures))
	quit(0 if failures.is_empty() else 1)


func session(size: Vector2i) -> void:
	var tag := "%dx%d" % [size.x, size.y]
	await shell._show_route(shell.ROUTES.find("Maps"))
	# Go to: a name, a prefixed number and a cell.
	var goto: Control = shell.goto_dialog
	expect(goto.query_of("W 12") == "w12" and goto.query_of("pirate") == "pirate", "A prefix and its number must run together")
	expect(goto.cell_of("3, 3") == Vector2i(3, 3) and goto.cell_of("3, x").x < 0, "A cell is two numbers")
	await goto.show_dialog()
	goto.field.text = "pirate"
	await goto.search()
	await settle()
	expect(goto.entries.size() > 0, "Go to must find a monster by name")
	goto.field.text = "denny"
	await goto.search()
	await settle()
	expect(int(goto.totals.get("texts", 0)) >= 1, "Go to must find words inside a scrolling text")
	goto.field.text = "pirate"
	await goto.search()
	await settle()
	inside(goto, "goto", size)
	await snapshot(tag + "-goto")
	goto.selected = 0
	goto.commit()
	await settle()
	expect(shell.pages.current_tab == shell.ROUTES.find("Records") or shell.pages.current_tab == shell.ROUTES.find("Combat"), "Choosing a monster must open it")
	await shell._show_route(shell.ROUTES.find("Maps"))
	# Find uses lists the steps that name a story, and Replace drafts them.
	await shell.find_uses("story", 1)
	var uses: Dictionary = shell.problems.uses
	expect(shell.problems.find_panel.visible and int(uses.get("total", 0)) > 0, "Find uses must list what names the story")
	await snapshot(tag + "-find-uses")
	shell.problems.replace_value.value = 2
	shell.problems.replace()
	expect(shell.drafts.size() == shell.problems._step_rows().size() and shell.drafts.size() > 0, "Replace must draft one step edit for each step")
	await shell._discard_continue()
	shell.problems.open(false)
	# View flow.
	await shell.flow_dialog.show_for("story", 13)
	expect(shell.flow_dialog.graph.nodes.size() >= 1, "View flow must draw the program")
	inside(shell.flow_dialog, "flow", size)
	await snapshot(tag + "-flow")
	shell.flow_dialog.close()
	# Problems: the findings agree with the dock and the map lists the operations in use.
	await shell._show_named_route("Problems")
	var findings: Array = shell.problems.result.get("findings", [])
	expect(findings.size() == shell.problems.count and findings.size() > 0, "The page and the dock must show the same findings")
	expect(shell.problems.result.get("operations", []).size() > 5, "The capability map must count the operations in use")
	await snapshot(tag + "-problems-page")
	shell.problems.open(true)
	await snapshot(tag + "-problems-dock")
	shell.problems.open(false)
