extends SceneTree
## Captures the project flows and shell states on the real renderer: First run,
## the Project page with its recent list, the Import level, New from template,
## Save, Export, Export result and Preferences dialogs, the menus, the
## confirmations and the status states. No host input or window automation.
## Needs CENTURIONS_CAPTURE_OUT, CENTURIONS_INSTALLATION, CENTURIONS_SETTINGS_FILE
## (a file that does not exist yet) and CENTURIONS_FIXTURES: a folder that holds
## `checkpoints` (the checkpoint folders to open, one per line in checkpoints.txt),
## and a template (`template.txt`).
var shell: Control
var out := ""
var failures: Array = []


func _initialize() -> void:
	call_deferred("run")


func settle(wait_for_adapter := true) -> void:
	while wait_for_adapter and shell.bridge.busy: await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func snapshot(name: String, region := Rect2i(), wait_for_adapter := true) -> void:
	await settle(wait_for_adapter)
	var image := root.get_texture().get_image()
	if region.size != Vector2i.ZERO: image = image.get_region(region)
	if image == null or image.is_empty() or image.save_png(out.path_join(name + ".png")) != OK: failures.append(name)


func expect(passed: bool, message: String) -> void:
	if not passed: failures.append(message)


func fixture_lines(file: String) -> Array:
	var text := FileAccess.get_file_as_string(OS.get_environment("CENTURIONS_FIXTURES").path_join(file))
	return Array(text.split("\n", false)).map(func(line): return str(line).strip_edges())


func run() -> void:
	create_timer(140).timeout.connect(func(): push_error("Project flow capture timed out"); quit(99))
	root.gui_embed_subwindows = true
	root.size = Vector2i(1600, 900)
	out = OS.get_environment("CENTURIONS_CAPTURE_OUT")
	if out.is_empty(): push_error("CENTURIONS_CAPTURE_OUT required"); quit(1); return
	var installation := OS.get_environment("CENTURIONS_INSTALLATION")
	shell = load("res://src/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await shell.startup_completed
	# First run: nothing open and no recent projects yet.
	expect(shell.summary.is_empty() and shell.project.recents.is_empty(), "First run must start with no project and no recent list")
	await shell._show_route(0)
	await snapshot("first-run")
	# Recent projects come from opening checkpoints.
	var checkpoints := fixture_lines("checkpoints.txt")
	for path in checkpoints: await shell.open_project(path)
	await shell._show_route(0)
	expect(shell.project.recents.size() == checkpoints.size(), "Every opened checkpoint must be in the recent list")
	await snapshot("project")
	shell.project.choose(str(shell.project.recents[1].path))
	await snapshot("project-selected-recent")
	shell.project.choose(str(shell.project.recents[0].path))
	# Import level: the source, then the result.
	shell._folder_action = "import"
	await shell._folder_selected(installation.path_join("Scenarios/The Thunder of Guns/0"))
	shell.set_destination(out.path_join("imported"))
	await snapshot("import-level-source")
	shell.flows.import_dialog.import_requested.emit()
	await settle()
	await settle()
	expect(shell.summary.get("origin", {}).get("kind", "") == "imported", "Import must open the imported checkpoint")
	await snapshot("import-level-result")
	shell.flows.import_dialog.close()
	# New from template, from the unchanged import just made.
	shell._scenario_name = "Micro Patrol"
	shell._source = out.path_join("imported")
	shell._choose_destination("new")
	shell.set_destination(out.path_join("base"))
	await snapshot("new-from-template")
	shell.flows.new_dialog.create_requested.emit()
	await settle()
	await settle()
	expect(shell.summary.get("native", {}).get("name", "") == "Micro Patrol", "Create scenario must open the new scenario")
	# Save and reopen: a good destination, a refused one and the status after.
	shell.stages.stage_id = 0
	shell.ui("StageX").value = 5
	shell._stage_changed()
	await shell.apply_draft()
	shell._choose_destination("save")
	shell.set_destination(out.path_join("checkpoint"))
	await snapshot("save-checkpoint")
	shell.set_destination(out.path_join("base"))
	shell.flows.save_dialog.save_requested.emit()
	await settle()
	await settle()
	expect(shell.flows.save_dialog.visible, "A refused destination must bring the Save dialog back")
	await snapshot("save-checkpoint-error")
	shell.flows.save_dialog.close()
	shell._choose_destination("save")
	shell.set_destination(out.path_join("checkpoint"))
	shell.flows.save_dialog.save_requested.emit()
	await settle()
	await settle()
	await snapshot("saved-status", Rect2i(0, 872, 1600, 28))
	# Export page, then the written result.
	await shell._show_route(shell.ROUTES.find("Export"))
	shell.set_destination(out.path_join("export-1"))
	await snapshot("export")
	await shell.start_export(true)
	await settle()
	expect(shell.flows.result_dialog.visible and DirAccess.dir_exists_absolute(out.path_join("export-1")), "Export must write the folder and show its result")
	await snapshot("export-results")
	shell.flows.result_dialog.close()
	await shell._show_route(0)
	await snapshot("project-after-save")
	# Preferences.
	shell.flows.open_preferences()
	await snapshot("preferences")
	shell.flows.preferences_dialog.close()
	# Menus.
	for title in ["File", "Edit", "View", "Map", "Play", "Help"]:
		shell.ui("Menu" + title).show_popup()
		await snapshot("menu-" + title.to_lower())
		shell.ui("Menu" + title).get_popup().hide()
	# File with its Open recent submenu.
	shell.ui("MenuFile").show_popup()
	await settle()
	var recent: PopupMenu = shell.header._recent
	recent.position = Vector2i(shell.ui("MenuFile").get_popup().position.x + shell.ui("MenuFile").get_popup().size.x + 2, shell.ui("MenuFile").get_popup().position.y + 100)
	recent.popup()
	await snapshot("menu-file-recent")
	recent.hide()
	shell.ui("MenuFile").get_popup().hide()
	# Confirmations.
	await shell._show_route(2)
	await shell._load_message(0)
	shell.ui("TextCheckTimer").stop()
	shell.ui("MessageText").text = "Draft for review."
	shell._message_changed()
	shell.ui("TextCheckTimer").stop()
	shell.guard(shell._show_route.bind(1))
	await snapshot("confirm-discard")
	await shell._discard_continue()
	shell.ui("StageX").value = 9
	shell._stage_changed()
	await shell.apply_draft()
	shell.guard(shell._close_project, true)
	expect(shell.ui("UnsavedDialog").visible, "Closing a project with unsaved edits must ask")
	await snapshot("confirm-close")
	shell.ui("UnsavedDialog")._answer("cancel")
	# Status states: each line of the board on the real bar, stacked.
	var lines := [
		"Starting local adapter…", "Ready · Open or import a scenario level", "Local installation remembered for subsequent launches", "Opened checkpoint",
		"Select a map cell first", "This slot is unplaced; use Remove or choose a placed slot", "Return destination applies to walking triggers only",
		"Return destination drafted · Apply edits", "Edits applied · Save a new checkpoint to keep them", "Floor stroke applied · one undo step", "Undo complete",
		"Checkpoint ready · …\\artifacts\\checkpoint", "No receipt matched to this exact export. Loading, prologue, and gameplay are separate checks.",
		"Edits are pending · match a validation receipt after applying them.", "Receipt does not match this exact export. Startup remains unverified for the current edits.",
		"Wait for the current operation.", "Adapter disconnected. Reopen the project; drafts are kept.", "Reopen the project before continuing; drafts are kept.",
		"Reopened saved checkpoint · pending drafts retained; applied edits require a saved checkpoint to survive interruption"]
	var sheet := Image.create(1600, 28 * lines.size(), false, Image.FORMAT_RGBA8)
	for index in range(lines.size()):
		shell.status(lines[index])
		await settle()
		sheet.blit_rect(root.get_texture().get_image(), Rect2i(0, 872, 1600, 28), Vector2i(0, 28 * index))
	expect(sheet.save_png(out.path_join("status-states.png")) == OK, "status-states")
	# Busy: the buttons that change the project are off while a request runs.
	await shell._show_route(3)
	shell.bridge.busy = true
	await snapshot("busy-header", Rect2i(0, 0, 1600, 48), false)
	shell.bridge.busy = false
	shell.bridge.stop()
	if failures.is_empty(): print("CENTURIONS_PROJECT_FLOW_CAPTURES_PASSED")
	else: push_error("Project flow capture failures: " + str(failures))
	quit(0 if failures.is_empty() else 1)
