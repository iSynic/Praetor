extends SceneTree
## Drives the Triggers & encounters workspace on the real renderer: a walking
## trigger's steps as cards and as a form, Choose action and Choose message,
## moving, clearing and applying steps, the code helper, the technical details
## and the choice and typed encounters with their branches. Needs
## CENTURIONS_PROJECT to be an imported level with an active walking trigger on
## map 0, CENTURIONS_INSTALLATION and CENTURIONS_CAPTURE_OUT.
var shell: Control
var programs: Control
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


func inside(dialog: Control, label: String, size: Vector2i) -> void:
	if not Rect2(Vector2.ZERO, Vector2(size)).encloses(dialog.panel_rect()): failures.append("%s exceeds the %s window" % [label, str(size)])


func run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Scripts capture timed out"); quit(99))
	root.gui_embed_subwindows = true
	out = OS.get_environment("CENTURIONS_CAPTURE_OUT")
	if out.is_empty(): push_error("CENTURIONS_CAPTURE_OUT required"); quit(1); return
	shell = load("res://src/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await shell.startup_completed
	programs = shell.programs
	await shell._show_route(shell.ROUTES.find("Maps"))
	var live: Array = shell.ui("MapCanvas").triggers.filter(func(trigger): return trigger.active)
	expect(not live.is_empty(), "The imported map must have an active trigger")
	var trigger_id := int(live[0].id)
	for size in [Vector2i(1600, 900), Vector2i(1200, 720)]:
		root.size = size
		await session(size, trigger_id)
	shell.bridge.stop()
	if failures.is_empty(): print("CENTURIONS_SCRIPT_CAPTURES_PASSED")
	else: push_error("Script capture failures: " + str(failures))
	quit(0 if failures.is_empty() else 1)


func session(size: Vector2i, trigger_id: int) -> void:
	var tag := "%dx%d" % [size.x, size.y]
	await shell._show_route(shell.ROUTES.find("Programs"))
	await programs.choose("walking", trigger_id, 0)
	await programs.select_step(0, 1)
	expect(programs.panel._heading.text == "Show message" and programs.selected_slot == 1, "Choosing a step must show its form")
	await snapshot(tag + "-script-walking")
	# The walking list can be limited to any map, not only the open one or all of them.
	if int(shell.summary.get("maps", 0)) > 1:
		var other := 1 if programs.list.picked_map != 1 and shell.maps.map_id != 1 else 0
		programs.list.list.scope_changed.emit("pick:%d" % other)
		await settle()
		expect(programs.list.picked_map == other and programs.list.scope == "map" and "Map %d" % other in programs.list._foot.text, "Another map can be picked for the walking triggers")
		programs.list.show_family("walking")
		await settle()
	if size.x < 1600:
		await programs.choose("menu", 0, 0)
		await snapshot(tag + "-script-choice")
		return
	# Choose action: a step is drafted through the model, so a draft is the same as any other edit.
	programs._choose_action()
	await snapshot(tag + "-script-choose-action")
	inside(programs.action_dialog, "Choose action", Vector2i(size))
	programs.action_dialog._picked = 9
	programs.action_dialog._commit()
	await settle()
	var key: String = programs.key(1)
	expect(shell.drafts.has(key) and int(shell.drafts[key].opcode) == 9, "Choosing Play sound must draft the step")
	expect(programs.panel._heading.text == "Play sound", "The form must follow the draft")
	# Moving swaps two steps; clearing sets the empty slot; Revert takes the drafts back.
	await programs.select_step(0, 2)
	await programs.move_step(-1)
	expect(programs.selected_slot == 1, "Moving up must follow the step")
	expect(int(programs._view(0, 2).opcode) == 9 and int(programs._view(0, 1).opcode) == 9, "Moving up must swap the two steps")
	await shell._discard_continue()
	expect(shell.drafts.is_empty(), "Discard must clear the drafts")
	await programs.select_step(0, 3)
	var before := int(programs._view(0, 3).opcode)
	programs.panel.clear_requested.emit()
	await settle()
	expect(int(programs._view(0, 3).opcode) == 0 and before != 0, "Clear step must set the empty slot")
	await shell._discard_continue()
	# Choose message: the table's rows, and only the operand changes.
	await programs.select_step(0, 1)
	programs.panel.choose_message_requested.emit()
	await settle()
	await snapshot(tag + "-script-choose-message")
	inside(programs.message_dialog, "Choose message", Vector2i(size))
	programs.message_dialog._picked = 51
	programs.message_dialog._commit()
	await settle()
	expect(int(shell.drafts[programs.key(1)].operand) == 51 and int(shell.drafts[programs.key(1)].opcode) == 1, "Choosing a message must draft only the operand")
	revision_check()
	var revision: int = shell.bridge.revision
	expect(await shell.apply_draft(), "Apply must accept the step")
	await settle()
	var check: Dictionary = await shell.request_backend({"op": "program", "family": "walking", "id": trigger_id, "branch": 0})
	expect(int(check.result.steps[1].operand) == 51 and shell.bridge.revision == revision + 1, "The applied operand must be read back as one revision")
	await shell._history("undo")
	# Code helper (F1) and technical details.
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_F1
	key_event.pressed = true
	expect(shell.header.command_for_key(key_event) == "helper", "F1 must open the code helper")
	programs.toggle_helper()
	await snapshot(tag + "-script-code-helper")
	expect(programs.helper.visible, "The code helper must open")
	programs.toggle_helper()
	programs.panel.details_button.button_pressed = true
	await settle()
	await settle()
	await snapshot(tag + "-script-technical-details")
	expect(programs.panel._hex_row.split(" ").size() == 42, "Technical details must show the 42 bytes of the row")
	expect("Step 2 owns" in programs.panel._owns.text, "Technical details must say what the step owns")
	programs.panel.details_button.button_pressed = false
	# Choice and typed encounters have four branches.
	await programs.choose("menu", 0, 0)
	expect(programs.branch_programs.size() == 4 and programs._cards_by_branch.size() == 4, "A choice encounter must show four branches")
	await snapshot(tag + "-script-choice")
	# The labels and the prompt of a choice encounter are edited where they are shown.
	programs._choice_boxes[1].text = "Open the damaged crate"
	programs._choice_boxes[1].text_changed.emit("Open the damaged crate")
	expect(shell.drafts.has("choice_label:0:1") and "Open the damaged crate" in programs._branch_opens[1].text, "A changed choice label is a draft shown over its branch")
	programs._choice_boxes[1].text_changed.emit(str(programs.branch_programs[1].label))
	expect(not shell.drafts.has("choice_label:0:1"), "The saved choice label leaves no draft")
	await programs.select_step(2, 4)
	expect(programs.branch == 2 and programs.selected_slot == 4, "Choosing a step of another branch must open that branch")
	await snapshot(tag + "-script-choice-branch")
	await programs.choose("typed", 1, 0)
	await snapshot(tag + "-script-typed")
	shell.condition_ui.refresh()
	var labels: Array = shell.condition_ui.rows.get_children().filter(func(row): return row.get_child_count() == 2 and row.get_child(1) is LineEdit)
	expect(labels.size() == 9, "A typed encounter must offer its eight action labels and its password label")
	labels[8].get_child(1).text_changed.emit("Open sesame")
	expect(shell.drafts.has("typed_label:1:8"), "A changed label is a draft")
	shell.drafts.clear()
	await programs.choose("story", 56, 0)
	await programs.select_step(0, 7)
	await snapshot(tag + "-script-story")
	# A battle step shows the five words of the Extra Codes row it names; a word is a draft, and putting it back leaves none.
	await programs.choose("story", 9, 0)
	await programs.select_step(0, 2)
	await settle()
	var row_id := int(programs._current(2).operand)
	expect(programs._extra_cache.has(row_id), "A battle step must load the Extra Codes row it names")
	if programs._extra_cache.has(row_id):
		var saved_word: int = int(programs._extra_cache[row_id].words[2])
		programs._extra_word_edited(row_id, 2, saved_word + 1)
		expect(shell.drafts.has("extra_row:%d" % row_id), "A changed Extra Code must be a draft of its row")
		programs._extra_word_edited(row_id, 2, saved_word)
		expect(not shell.drafts.has("extra_row:%d" % row_id), "The saved Extra Code must leave no draft")
		await snapshot(tag + "-script-extra")
	# A branching step shows the words of its row, and a word is a draft of the whole row.
	await programs.choose("story", 92, 0)
	await programs.select_step(0, 0)
	await settle()
	var branch_row := int(programs._current(0).operand)
	expect(int(programs._current(0).opcode) == 46 and programs._extra_cache.has(branch_row), "A mission flag branch must load its row")
	if programs._extra_cache.has(branch_row):
		var saved_type: int = int(programs._extra_cache[branch_row].words[2])
		programs._extra_word_edited(branch_row, 2, 3)
		var draft: Dictionary = shell.drafts.get("extra_row:%d" % branch_row, {})
		expect(not draft.is_empty() and int(draft.words[2]) == 3 and int(draft.words[0]) == int(programs._extra_cache[branch_row].words[0]), "A changed jump type must draft the whole row")
		programs._extra_word_edited(branch_row, 2, saved_type)
		expect(not shell.drafts.has("extra_row:%d" % branch_row), "The saved row must leave no draft")
		await snapshot(tag + "-script-branch")
		# Find uses on the row lists the steps that read it.
		await shell.find_uses("extra", branch_row)
		expect(shell.problems.uses.get("rows", []).any(func(row): return int(row.id) == 92), "Find uses on a row must list the step that reads it")


## Nothing to check here; kept so the order of the checks above reads as the workflow does.
func revision_check() -> void:
	pass
