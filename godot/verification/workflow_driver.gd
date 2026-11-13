extends RefCounted
## Runs the actual shell/controller/adapter workflow without host UI automation.
var shell: Control
var out: String

func run_on_shell(current: Control) -> void:
	shell = current
	var tree: SceneTree = shell.get_tree()
	tree.root.gui_embed_subwindows = true
	tree.root.size = Vector2i(1600,900)
	tree.create_timer(85).timeout.connect(func(): push_error("Editor workflow timed out"); tree.quit(99))
	out = OS.get_environment("CENTURIONS_TEST_OUT")
	if not check(not out.is_empty(),"CENTURIONS_TEST_OUT required"): return
	if not check(not shell.summary.is_empty(),"Project did not open"): return
	if not check(shell.summary.source_files == 59): return
	if not check(shell.ui("MapCanvas").atlas != null,"Artwork must load on project open before visiting Maps"): return
	await shell._remember_installation()
	if not check(shell.ui("Status").text.begins_with("Local installation remembered")): return
	shell._destination_action = "export"
	shell.ui("DestinationPath").text = out.path_join("native-first-patrol")
	await shell._publish()
	var receipt := OS.get_environment("CENTURIONS_TEST_RECEIPT")
	if not receipt.is_empty():
		await shell._match_receipt(receipt)
		if not check("Exact export match" in shell.ui("RuntimeStatus").text): return
	await shell._show_route(1)
	shell.ui("StageName").text = "Patrouille"
	shell._stage_changed()
	shell.ui("StageX").value = 7
	shell.ui("StageY").value = 11
	if not check(await shell.apply_draft()): return
	if not check(shell.summary.stages[0].x == 7 and shell.summary.stages[0].y == 11): return
	if not check("No receipt matched" in shell.ui("RuntimeStatus").text): return
	if not receipt.is_empty():
		await shell._match_receipt(receipt)
		if not check("does not match" in shell.ui("RuntimeStatus").text): return
	shell.ui("OpeningX").value = 13
	shell.ui("OpeningY").value = 17
	if not check(await shell.apply_draft()): return
	if not check(shell.summary.opening.x == 13 and shell.summary.stages[0].x == 7): return
	await shell._show_route(3)
	if not check(shell.ui("MapCanvas").atlas != null,"Native atlas not loaded"): return
	var before: int = shell.ui("MapCanvas").floor_values[3*90+7]
	shell.ui("TileID").value = 17
	await shell._paint_stroke([{"x":3,"y":7},{"x":4,"y":7}])
	if not check(shell.ui("MapCanvas").floor_values[3*90+7] == 17): return
	await shell._history("undo")
	if not check(shell.ui("MapCanvas").floor_values[3*90+7] == before): return
	await shell._history("redo")
	if not check(shell.ui("MapCanvas").floor_values[4*90+7] == 17): return
	await shell._show_route(2)
	await shell._load_message(0)
	shell.ui("TextCheckTimer").stop()
	shell.ui("MessageText").text = "😀"
	shell._message_changed()
	shell.ui("TextCheckTimer").stop()
	var revision: int = shell.bridge.revision
	if not check(not await shell.apply_draft()): return
	if not check(shell.bridge.revision == revision and not shell.drafts.is_empty()): return
	shell.ui("MessageText").text = "Café.\nPatrol test."
	shell._message_changed()
	shell.ui("TextCheckTimer").stop()
	shell.ui("MessageText").grab_focus()
	var apply_key := InputEventKey.new()
	apply_key.keycode = KEY_ENTER; apply_key.ctrl_pressed = true; apply_key.pressed = true
	Input.parse_input_event(apply_key)
	var deadline := Time.get_ticks_msec()+3000
	while Time.get_ticks_msec()<deadline and (not shell.drafts.is_empty() or shell.bridge.busy): await tree.process_frame
	if not check(shell.drafts.is_empty(),"Ctrl+Enter must apply from the message field"): return
	shell.ui("TextCheckTimer").stop()
	shell._destination_action = "save"
	shell.ui("DestinationPath").text = out.path_join("checkpoint")
	await shell._publish()
	if not check(not shell.summary.dirty): return
	shell._destination_action = "export"
	shell.ui("DestinationPath").text = out.path_join("export")
	await shell._publish()
	if not check(FileAccess.file_exists(out.path_join("export/Data LD"))): return
	await shell.open_project(out.path_join("checkpoint"))
	await shell._load_message(0)
	shell.ui("TextCheckTimer").stop()
	if not check(shell.ui("MessageText").text == "Café.\nPatrol test."): return
	# Pending text survives an interrupted adapter and reopening its checkpoint.
	shell.ui("MessageText").text = "Retained pending text."
	shell._message_changed()
	shell.ui("TextCheckTimer").stop()
	OS.kill(int(shell.bridge._process.pid))
	await tree.create_timer(0.1).timeout
	var failed: Dictionary = await shell.request_backend({"op":"inspect"})
	if not check(not failed.ok and shell.bridge.requires_reopen and not shell.drafts.is_empty()): return
	await shell.open_project(out.path_join("checkpoint"))
	if not check(not shell.drafts.is_empty()): return
	if not check(await shell.apply_draft()): return
	await shell._load_message(0)
	shell.ui("TextCheckTimer").stop()
	if not check(shell.ui("MessageText").text == "Retained pending text."): return
	# All navigation guards use the same apply/discard/cancel dialog path.
	shell.ui("MessageText").text = "Unapplied draft."
	shell._message_changed()
	shell.ui("TextCheckTimer").stop()
	shell.guard(shell._show_route.bind(1))
	if not check(shell.ui("DraftDialog").visible): return
	shell.ui("DraftDialog").canceled.emit()
	shell.ui("DraftDialog").hide()
	if not check(not shell.drafts.is_empty()): return
	shell.guard(shell._show_route.bind(1))
	await shell._discard_continue()
	if not check(shell.drafts.is_empty() and shell.ui("Pages").current_tab == 1): return
	# Inspect the native story geometry through the UI's read-only table.
	await shell._show_route(4)
	if not check(shell.ui("StoryData").get_root().get_child_count() == 8): return
	# Exercise the same folder/destination callbacks used by the native dialogs.
	shell._folder_action = "import"
	await shell._folder_selected(OS.get_environment("CENTURIONS_TEST_SOURCE"))
	shell.ui("DestinationPath").text = out.path_join("imported")
	await shell._publish()
	if not check(shell.summary.origin.kind == "imported" and shell.summary.source_files == 59): return
	# Real native negative floor IDs are masked cicn resources, never atlas slots.
	await shell._show_route(3)
	if not check(shell.ui("MapCanvas").icons.has(-1),"Missing signed cicn -1"): return
	if not check(shell.ui("MapCanvas").default_tile == 155): return
	if not check(not shell.ui("MapCanvas").triggers.is_empty(),"Walking trigger markers absent"): return
	var trigger: Dictionary = shell.ui("MapCanvas").triggers[0]
	await shell._open_map_program(int(trigger.id))
	if not check(shell._program.family == "walking" and shell._program.steps.size() == 8): return
	# Find an existing supported slot; unresolved operations cannot be replaced.
	var slot := -1
	for step in shell._program.steps:
		if step.authorable: slot = int(step.slot); break
	if not check(slot >= 0): return
	var controls: Dictionary = shell._step_controls[slot]
	controls.op.select(controls.op.get_item_index(9)); controls.arg.value = 2
	shell._program_changed(slot)
	if not check(await shell.apply_draft()): return
	if not check(int(shell._program.steps[slot].opcode) == 9 and int(shell._program.steps[slot].operand) == 2): return
	shell._destination_action = "save"; shell.ui("DestinationPath").text = out.path_join("program-checkpoint"); await shell._publish()
	await shell.open_project(out.path_join("program-checkpoint")); await shell._load_program()
	if not check(int(shell._program.steps[slot].opcode) == 9): return
	shell._destination_action = "export"; shell.ui("DestinationPath").text = out.path_join("program-export"); await shell._publish()
	# Choice and typed encounter branches use signed-byte opcodes and separate record strides.
	await shell._choose_program("menu",0,3)
	if not check(shell._program.steps.size() == 8 and shell._program.branches == 4): return
	await shell._choose_program("typed",0,2)
	if not check(shell._program.steps.size() == 8 and shell._program.branches == 4): return
	for family in ["menu","typed"]:
		await shell._choose_program(family,0,3)
		var editable := -1
		for step in shell._program.steps:
			if step.authorable: editable = int(step.slot); break
		if not check(editable >= 0): return
		var c: Dictionary = shell._step_controls[editable]
		c.op.select(c.op.get_item_index(9)); c.arg.value = 3 if family == "menu" else 4
		shell._program_changed(editable)
		# A cancelled family navigation retains the step draft and restores the selector.
		shell.guard(shell._choose_program.bind("story",0,0))
		if not check(shell.ui("DraftDialog").visible): return
		await shell._cancel_navigation(); shell.ui("DraftDialog").hide()
		if not check(not shell.drafts.is_empty() and shell._program_family == family): return
		if not check(await shell.apply_draft()): return
	shell._destination_action = "save"; shell.ui("DestinationPath").text = out.path_join("encounter-checkpoint"); await shell._publish()
	await shell.open_project(out.path_join("encounter-checkpoint"))
	shell._destination_action = "export"; shell.ui("DestinationPath").text = out.path_join("encounter-export"); await shell._publish()
	await shell._show_route(3); await shell._select_map(2)
	if not check(shell.ui("MapCanvas").icons.has(-2) and shell.ui("MapCanvas").icons.has(-3)): return
	# Place an existing header and its positive ordinary-movement gate atomically.
	await shell._select_map(0)
	shell.ui("PlacementSlot").value = 99; shell.ui("PlacementChance").value = 75
	var placement_before: Dictionary = await shell.request_backend({"op":"program","family":"walking","id":99,"branch":0})
	await shell._place_trigger(Vector2i(17,29))
	var placed: Dictionary = await shell.request_backend({"op":"program","family":"walking","id":99,"branch":0})
	if not check(int(placed.result.location_key) == 2917 and int(placed.result.chance) == 75): return
	await shell._history("undo")
	var restored: Dictionary = await shell.request_backend({"op":"program","family":"walking","id":99,"branch":0})
	if not check(restored.result.location_key == placement_before.result.location_key and restored.result.chance == placement_before.result.chance): return
	await shell._history("redo")
	await shell._open_map_program(99)
	await shell.condition_ui.open(); shell.condition_ui.controls[0].value = 25
	if not check(not shell.drafts.is_empty()): return
	if not check(await shell.apply_draft()): return
	shell.condition_ui.window.hide()
	for family in ["menu","typed"]:
		await shell._choose_program(family,0,0)
		await shell.condition_ui.open()
		var changed := false
		for control in shell.condition_ui.controls:
			if control.editable:
				control.value = 2 if int(control.value) != 2 else 3; changed = true; break
		if not check(changed and await shell.apply_draft()): return
		shell.condition_ui.window.hide()
	shell._destination_action = "save"; shell.ui("DestinationPath").text = out.path_join("conditions-checkpoint"); await shell._publish()
	await shell.open_project(out.path_join("conditions-checkpoint"))
	shell._destination_action = "export"; shell.ui("DestinationPath").text = out.path_join("conditions-export"); await shell._publish()
	var readonly_revision: int = shell.bridge.revision
	await shell._show_route(6)
	await shell.combat_ui.record(1)
	if not check(shell.combat_ui.population.cells.size() == 676): return
	shell.combat_ui.kind.select(1); await shell.combat_ui.catalogue(0)
	if not check("Data MD" in shell.combat_ui.details.text and shell.bridge.revision == readonly_revision): return
	await shell.open_project(out.path_join("imported"))
	shell._scenario_name = "UI Patrol"
	shell._folder_action = "template"
	await shell._folder_selected(out.path_join("imported"))
	shell.ui("DestinationPath").text = out.path_join("new-scenario")
	await shell._publish()
	if not check(shell.summary.native.name == "UI Patrol" and shell.summary.stages[0].name == "UI Patrol"): return
	shell._destination_action = "export"
	shell.ui("DestinationPath").text = out.path_join("new-level")
	await shell._publish()
	if not check(FileAccess.file_exists(out.path_join("new-level/UI Patrol"))): return
	shell.ui("DestinationDialog").hide()
	var receipt_file := FileAccess.open(out.path_join("godot-workflow.json"),FileAccess.WRITE)
	receipt_file.store_string(JSON.stringify({"status":"passed","revision":shell.bridge.revision,
		"native_artwork":true,"asymmetric_cells":[[3,7],[4,7]],"stroke_undo":"one step",
		"invalid_text_rejected":true,"adapter_recovery_preserved_draft":true,"checkpoint_reopened":true,
		"draft_cancel_discard":true,"read_only_story_slots":8,"import_and_new_from_template":true,"keyboard_apply_from_text":true},"  "))
	receipt_file.close()
	shell.bridge.stop()
	print("CENTURIONS_EDITOR_WORKFLOW_PASSED")
	tree.quit(0)

func check(condition: bool, message := "Editor workflow requirement failed") -> bool:
	if not condition:
		push_error(message)
		shell.get_tree().quit(1)
	return condition
