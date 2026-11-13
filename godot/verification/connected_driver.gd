extends RefCounted
## One native author/export/reopen workflow, with the real forms and adapter.
var shell: Control
var out: String

func check(passed: bool, message: String) -> bool:
	if not passed: push_error(message); shell.bridge.stop(); shell.get_tree().quit(1)
	return passed

func run_on_shell(owner_shell: Control) -> void:
	shell = owner_shell; out = OS.get_environment("CENTURIONS_TEST_OUT")
	shell.get_tree().create_timer(90).timeout.connect(func(): push_error("Connected workflow timeout"); shell.get_tree().quit(99))
	if not check(await shell.mission_ui.author({}),"Connected authoring failed"): return
	if not check(shell.summary.allocations.size() == 11,"Allocation count"): return
	var allocations: Array = shell.summary.allocations
	var ids := {}
	for allocation in allocations: ids[allocation.family] = int(allocation.id)
	await shell.record_ui.open_record("choice",ids.choice)
	var record: RefCounted = shell.record_ui
	if not check(record.controls.label0.text == "Engage","Choice form label"): return
	record.controls.label0.text = "Proceed"
	record.changed()
	if not check(await shell.apply_draft(),"Choice form apply"): return
	await shell._history("undo")
	if not check(record.controls.label0.text == "Engage","Choice undo refresh"): return
	await shell.record_ui.open_record("battle_extra",ids.battle_extra)
	if not check(int(record.controls.minimum.value) == ids.battle,"Battle EXTRA link"): return
	await shell.record_ui.open_record("monster",ids.monster)
	if not check(record.controls.name.text == "Training Drone","Monster form"): return
	await shell.record_ui.open_record("reward",ids.reward)
	if not check(int(record.controls.credits.value) == 25,"Reward form"): return
	record.controls.credits.value = 30
	if not check(await shell.apply_draft(),"Reward draft"): return
	await shell._history("undo")
	await shell._show_route(3)
	var walking := -1
	for trigger in shell.ui("MapCanvas").triggers:
		if trigger.active and int(trigger.x) == 3 and int(trigger.y) == 2: walking = int(trigger.id)
	if not check(walking >= 0,"Ordinary movement gate and header must be active"): return
	shell.ui("PlacementSlot").value = walking%100
	shell.placement_ui.selected = Vector2i(5,7)
	await shell.placement_ui.create()
	var created := false
	for trigger in shell.ui("MapCanvas").triggers:
		if int(trigger.x) == 5 and int(trigger.y) == 7: created = trigger.active
	if not check(created,"Create an empty walking slot with native activation"): return
	await shell._history("undo")
	shell.ui("PlacementSlot").value = walking%100
	await shell.placement_ui.place(Vector2i(3,2),false,true)
	for trigger in shell.ui("MapCanvas").triggers:
		if int(trigger.id) == walking and not check(not trigger.active,"Disable walking trigger"): return
	await shell._history("undo")
	await shell.placement_ui.place(Vector2i(3,2),true,false)
	for trigger in shell.ui("MapCanvas").triggers:
		if not check(int(trigger.id) != walking,"Remove unplaces without erasing program"): return
	await shell._history("undo")
	shell.ui("PlacementFollow").button_pressed = true
	await shell.placement_ui.place(Vector2i(7,11))
	var moved := false
	for trigger in shell.ui("MapCanvas").triggers:
		if int(trigger.id) == walking: moved = trigger.active and int(trigger.x) == 7 and int(trigger.y) == 11
	if not check(moved,"Asymmetric coupled movement"): return
	await shell._history("undo")
	await shell._choose_program("menu",ids.choice,0)
	await shell._show_route(5)
	if not check(int(shell._program.steps[1].opcode) == 10,"Explicit reward continuation"): return
	await shell._follow_step(1)
	if not check(shell.ui("Pages").current_tab == 7 and record.data.family == "reward","Reward typed link"): return
	await shell._choose_program("menu",ids.choice,0); await shell._show_route(5); await shell._follow_step(3)
	if not check(shell._stage_id == 1,"Signed one-based stage link"): return
	for action in ["save","export"]:
		shell._destination_action = action
		shell.ui("DestinationPath").text = out.path_join("checkpoint" if action == "save" else "level")
		await shell._publish()
	await shell.open_project(out.path_join("checkpoint"))
	if not check(shell.summary.allocations.size() == 11,"Checkpoint allocations reopen"): return
	shell._destination_action = "export"; shell.ui("DestinationPath").text = out.path_join("reopened-level"); await shell._publish()
	if not check(FileAccess.file_exists(out.path_join("level/Data TD")),"Export not written"): return
	shell.bridge.stop(); print("CENTURIONS_CONNECTED_WORKFLOW_PASSED"); shell.get_tree().quit()
