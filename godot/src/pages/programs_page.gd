extends HBoxContainer
## Triggers and encounters: the programs of the scenario. A walking trigger, a
## story, or a choice or typed encounter runs up to eight steps in order; a
## choice or typed encounter has four branches of them. The page lists the
## programs, shows the steps as cards and the chosen step as a form, and drafts
## every change for Apply.
const Capability = preload("res://src/scripts/capability.gd")
const Card = preload("res://src/widgets/card.gd")
const ChooseActionDialog = preload("res://src/dialogs/choose_action_dialog.gd")
const ChooseMessageDialog = preload("res://src/dialogs/choose_message_dialog.gd")
const CodeHelper = preload("res://src/scripts/code_helper.gd")
const KeyValueRow = preload("res://src/widgets/key_value_row.gd")
const ScriptList = preload("res://src/scripts/script_list.gd")
const StepCard = preload("res://src/scripts/step_card.gd")
const StepPanel = preload("res://src/scripts/step_panel.gd")

const FAMILIES := ["walking", "story", "menu", "typed"]
const TITLES := {"walking": "Walking trigger", "story": "Story", "menu": "Choice encounter", "typed": "Typed encounter"}
const TABLES := {"walking": "walking table", "story": "story table ED3", "menu": "choice encounter table ED", "typed": "typed encounter table ED2"}

var shell: Control
var family := "walking"
var id := 0
var branch := 0
var program: Dictionary = {}
## The model of the steps of the open branch: an operation and an operand for
## each slot. The forms write here and the drafts are made from here.
var step_controls: Array = []
## Every branch of the open program, by branch number.
var branch_programs: Dictionary = {}
var selected_slot := 0
var list := ScriptList.new()
var panel := StepPanel.new()
var helper := CodeHelper.new()
var action_dialog := ChooseActionDialog.new()
var message_dialog := ChooseMessageDialog.new()
## Where the return controls of the Maps placement controller are shown.
var after_box := VBoxContainer.new()
var recent_operations: Array = []
var _model := Control.new()
var _messages: Dictionary = {}
## The label of each choice of the open choice encounter, as shown (a draft over what is saved), and the labels over the branches.
var _choice_boxes: Dictionary = {}
var _branch_opens: Dictionary = {}
var _messages_revision := -1
var _title := Label.new()
var _badges := HBoxContainer.new()
var _sub := Label.new()
var _reveal := Button.new()
var _conditions := Button.new()
var _cards := HBoxContainer.new()
var _walking_main := HBoxContainer.new()
var _steps_column := VBoxContainer.new()
var _steps_title := Label.new()
var _encounter_main := VBoxContainer.new()
var _info_column := VBoxContainer.new()
var _branch_row := HBoxContainer.new()
var _panel_slot := VBoxContainer.new()
var _walking_panel_slot := VBoxContainer.new()
var _group := ButtonGroup.new()
var _cards_by_branch: Dictionary = {}
var _branch_titles: Dictionary = {}
var _loading_view := false
var _after_card := Card.new()
var _scroll := ScrollContainer.new()


func _init() -> void:
	add_theme_constant_override("separation", 12)
	_model.visible = false
	add_child(_model)
	list.custom_minimum_size.x = 310
	add_child(list)
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var body := VBoxContainer.new()
	body.name = "ProgramBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	_scroll.add_child(body)
	body.add_child(_header())
	_sub.theme_type_variation = &"Dim"
	body.add_child(_sub)
	_cards.add_theme_constant_override("separation", 12)
	body.add_child(_cards)
	_walking_main.add_theme_constant_override("separation", 16)
	body.add_child(_walking_main)
	_steps_column.custom_minimum_size.x = 340
	_steps_column.add_theme_constant_override("separation", 6)
	_walking_main.add_child(_steps_column)
	_walking_panel_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_walking_main.add_child(_walking_panel_slot)
	_encounter_main.add_theme_constant_override("separation", 12)
	body.add_child(_encounter_main)
	var encounter_row := HBoxContainer.new()
	encounter_row.add_theme_constant_override("separation", 12)
	_encounter_main.add_child(encounter_row)
	_info_column.custom_minimum_size.x = 290
	_info_column.add_theme_constant_override("separation", 10)
	encounter_row.add_child(_info_column)
	_branch_row.add_theme_constant_override("separation", 8)
	_branch_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	encounter_row.add_child(_branch_row)
	_panel_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_encounter_main.add_child(_panel_slot)
	_walking_panel_slot.add_child(panel)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_after_card.title = "After the steps"
	_after_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	after_box.add_theme_constant_override("separation", 6)
	_after_card.add_row(after_box)
	_steps_title.theme_type_variation = &"CaptionMuted"
	_build_model()
	for node in [_cards, _walking_main, _encounter_main]: node.visible = false


func _header() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	_title.theme_type_variation = &"PageTitle"
	_title.add_theme_font_size_override("font_size", 22)
	row.add_child(_title)
	_badges.add_theme_constant_override("separation", 6)
	_badges.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_badges)
	# The buttons wrap under the title when the page is narrow.
	var buttons := HFlowContainer.new()
	buttons.alignment = FlowContainer.ALIGNMENT_END
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 6)
	row.add_child(buttons)
	var callers := Button.new()
	callers.text = "Callers"
	callers.pressed.connect(func(): shell.find_uses({"walking": "walking", "story": "story", "menu": "choice", "typed": "typed"}[family], id))
	buttons.add_child(callers)
	var flow := Button.new()
	flow.text = "View flow"
	flow.pressed.connect(func(): shell.view_flow())
	buttons.add_child(flow)
	_reveal.text = "Reveal on map"
	_reveal.pressed.connect(func(): shell.guard(reveal_on_map))
	buttons.add_child(_reveal)
	_conditions.text = "Conditions…"
	_conditions.pressed.connect(func(): shell.condition_ui.open())
	buttons.add_child(_conditions)
	var duplicate := Button.new()
	duplicate.text = "Duplicate"
	duplicate.disabled = true
	duplicate.tooltip_text = "Records are added from Author records"
	buttons.add_child(duplicate)
	return column


## The model controls the drivers and the drafts read: one operation choice and one operand for each slot.
func _build_model() -> void:
	for slot in range(8):
		var operation := OptionButton.new()
		var operand := SpinBox.new()
		operand.min_value = -32768
		operand.max_value = 32767
		var jump := Button.new()
		var detail := Label.new()
		for node in [operation, operand, jump, detail]: _model.add_child(node)
		step_controls.append({"op": operation, "arg": operand, "detail": detail, "link": jump})
		operation.item_selected.connect(func(_index): changed(slot))
		operand.value_changed.connect(func(_value): changed(slot))


func setup(owner_shell: Control) -> void:
	shell = owner_shell
	list.setup(shell)
	list.record_chosen.connect(func(name, record): shell.guard(choose.bind(name, record, 0)))
	panel.setup(shell)
	for dialog in [helper, action_dialog, message_dialog]: shell.add_child(dialog)
	helper.name = "CodeHelper"
	action_dialog.name = "ChooseActionDialog"
	message_dialog.name = "ChooseMessageDialog"
	message_dialog.setup(shell)
	action_dialog.action_chosen.connect(_action_chosen)
	message_dialog.message_chosen.connect(func(message): set_step(selected_slot, 1, message))
	panel.choose_action_requested.connect(_choose_action)
	panel.extra_word_edited.connect(_extra_word_edited)
	panel.extra_independent_requested.connect(_extra_independent)
	panel.extra_uses_requested.connect(func(record): shell.find_uses("extra", record))
	panel.choose_record_requested.connect(func(record_kind): shell.picker_dialog.show_for(record_kind, absi(int(_current(selected_slot).operand)), "%s · step %d · %s" % [_record_label(), selected_slot + 1, "Scrolling text" if record_kind == "text" else "Explicit reward"], func(chosen): set_step(selected_slot, int(_current(selected_slot).opcode), chosen)))
	panel.choose_message_requested.connect(func(): message_dialog.show_for(absi(int(_current(selected_slot).operand)), "%s · step %d · Show message" % [_record_label(), selected_slot + 1]))
	panel.helper_requested.connect(toggle_helper)
	panel.operand_edited.connect(func(value): _write_operand(selected_slot, value))
	panel.open_link_requested.connect(func(): shell.guard(follow_step.bind(selected_slot)))
	panel.move_requested.connect(move_step)
	panel.duplicate_requested.connect(duplicate_step)
	panel.clear_requested.connect(func(): set_step(selected_slot, 0, int(program.steps[selected_slot].operand)))
	panel.details_toggled.connect(func(_on): _show_bytes())
	helper.closed.connect(func(): pass)


func _record_label() -> String:
	match family:
		"walking": return "W%d" % (id % 100)
		"story": return "Story %d" % id
		"menu": return "Choice %d" % id
	return "Typed %d" % id


func choose(program_family: String, program_id: int, program_branch: int) -> void:
	if program_family != family or program_id != id: selected_slot = 0
	family = program_family; id = program_id; branch = program_branch
	await load_program()


func open_map_program(trigger_id: int) -> void:
	family = "walking"; id = trigger_id; branch = 0; selected_slot = 0
	await shell._show_route(5)


func open_cell_link(target: Dictionary) -> void:
	family = target.family; id = int(target.id); branch = 0; selected_slot = 0
	await shell._show_route(5)


## The program of `branch_number` as the adapter reads it.
func _read(branch_number: int) -> Dictionary:
	var response: Dictionary = await shell.request_backend({"op": "program", "family": family, "id": id, "branch": branch_number})
	return response.result if response.get("ok", false) else {}


## Reads the chosen record and shows its steps, with unapplied edits over the
## saved ones. A step the editor cannot author stays as it is, read-only.
func load_program() -> void:
	if shell.summary.is_empty(): return
	var response: Dictionary = await shell.request_backend({"op": "program", "family": family, "id": id, "branch": branch})
	if not response.get("ok", false):
		program = {}
		_sub.text = shell._error(response)
		for controls in step_controls: controls.op.disabled = true; controls.arg.editable = false; controls.link.disabled = true
		return
	shell._loading = true
	program = response.result
	for slot in range(8):
		var controls: Dictionary = step_controls[slot]
		var original: Dictionary = program.steps[slot]
		var current: Dictionary = shell.drafts.get(key(slot), original)
		controls.op.clear()
		for item in program.catalogue: controls.op.add_item("%d · %s" % [int(item.opcode), item.name], int(item.opcode))
		if not original.authorable: controls.op.add_item("%d · %s (read-only)" % [int(original.opcode), original.name]); controls.op.select(controls.op.item_count - 1)
		else:
			if controls.op.get_item_index(int(current.opcode)) < 0: controls.op.add_item("%d · Does nothing" % int(current.opcode), int(current.opcode))
			controls.op.select(controls.op.get_item_index(int(current.opcode)))
		controls.link.disabled = not Capability.linked(int(current.opcode))
		controls.op.disabled = not original.authorable
		controls.arg.value = current.operand
		controls.arg.editable = original.authorable and int(current.opcode) not in [0, 24]
		controls.detail.text = "Preserved operation" if not original.authorable else operand_help(int(current.opcode))
	shell._loading = false
	branch_programs = {branch: program}
	if family in ["menu", "typed"]:
		for other in range(4):
			if other != branch: branch_programs[other] = await _read(other)
	if _messages_revision != shell.bridge.revision:
		_messages.clear()
		_messages_revision = shell.bridge.revision
	if _extra_revision != shell.bridge.revision:
		_extra_cache.clear()
		_extra_revision = shell.bridge.revision
	for other in branch_programs:
		if not branch_programs[other].has("steps"): continue
		for step in branch_programs[other].steps:
			var view := _view(other, int(step.slot))
			if int(view.opcode) == 1: await ensure_message(absi(int(view.operand)))
			if Capability.uses_extra(int(view.opcode)): await ensure_extra(int(view.operand))
			if Capability.has_companion(int(view.opcode)): await ensure_extra(int(view.operand) + 1)
	if int(program.get("dialogue", 0)) != 0: await ensure_message(int(program.dialogue))
	await shell.references.ensure()
	await shell.references.ensure_monsters()
	shell.placement_ui.refresh()
	await list.refresh()
	await list.select(family, id)
	_show()


func key(slot: int) -> String:
	return key_for(branch, slot)


func key_for(branch_number: int, slot: int) -> String:
	return "script_step:%s:%d:%d:%d" % [family, id, branch_number, slot]


func operand_help(opcode: int) -> String:
	return {0: "No operation; operand retained", 1: "Signed message ID", 2: "Battle EXTRA row ID", 10: "Reward row ID", 110: "Signed one-based stage (negative skips confirmation)", 4: "Choice encounter ID", 5: "Typed encounter ID", 9: "Sound resource ID", 24: "End script; operand retained", 39: "Story replacement ID", 100: "Operand 0; ordinary reward mode 0"}.get(opcode, "Read-only")


## Drafts the step when its operation or operand differs from the saved one.
func changed(slot: int) -> void:
	if shell._loading or program.is_empty(): return
	var controls: Dictionary = step_controls[slot]
	var original: Dictionary = program.steps[slot]
	if not original.authorable: return
	var op: int = controls.op.get_selected_id()
	controls.arg.editable = op not in [0, 24]
	controls.link.disabled = not Capability.linked(op)
	controls.detail.text = operand_help(op)
	var arg: int = int(original.operand) if op in [0, 24] else int(controls.arg.value)
	if op in [0, 24]: controls.arg.set_value_no_signal(arg)
	var step_key := key(slot)
	if op == int(original.opcode) and arg == int(original.operand): shell.drafts.erase(step_key)
	else: shell.drafts[step_key] = {"kind": "script_step", "family": family, "id": id, "branch": branch, "slot": slot, "opcode": op, "operand": arg}
	if not shell.drafts.is_empty(): shell._invalidate_receipt()
	shell._update_buttons()
	if not _loading_view: _show_cards()


## The step as drawn: its saved values, or the draft over them.
func _view(branch_number: int, slot: int) -> Dictionary:
	var source: Dictionary = branch_programs.get(branch_number, program)
	if not source.has("steps"): source = program
	var original: Dictionary = source.steps[slot]
	var draft: Dictionary = shell.drafts.get(key_for(branch_number, slot), original)
	return {"slot": slot, "opcode": int(draft.opcode), "operand": int(draft.operand), "authorable": original.authorable, "drafted": shell.drafts.has(key_for(branch_number, slot))}


func _current(slot: int) -> Dictionary:
	return _view(branch, slot)


func ensure_message(message: int) -> void:
	if _messages.has(message): return
	var response: Dictionary = await shell.request_backend({"op": "message", "id": message})
	if not response.get("ok", false): return
	var text: String = str(shell.drafts.get("message:%d" % message, {}).get("text", response.result.text))
	var counted: Dictionary = await shell.request_backend({"op": "text_check", "text": text})
	_messages[message] = {"text": text, "bytes": int(counted.result.get("encoded_bytes", 0)) if counted.get("ok", false) else text.to_utf8_buffer().size()}


# ── changes to a step ──

## Sets a step's operation and operand through the model, so the draft is made as for any edit.
func set_step(slot: int, opcode: int, operand: int) -> void:
	if program.is_empty() or not program.steps[slot].authorable: return
	var controls: Dictionary = step_controls[slot]
	var index: int = controls.op.get_item_index(opcode)
	if index < 0: return
	controls.op.select(index)
	controls.arg.set_value_no_signal(operand)
	changed(slot)
	await _after_edit()


func _write_operand(slot: int, value: int) -> void:
	if program.is_empty(): return
	step_controls[slot].arg.value = value
	await _after_edit(false)


func _after_edit(rebuild := true) -> void:
	var current := _current(selected_slot)
	if int(current.opcode) == 1: await ensure_message(absi(int(current.operand)))
	if rebuild: _show()
	else:
		_show_cards()
		_show_details()


func _operand_for(opcode: int) -> int:
	var current := _current(selected_slot)
	var operand := int(current.operand)
	match opcode:
		0, 24: return int(program.steps[selected_slot].operand)
		100: return operand if operand in [0, 1, 5] else 0
		14: return operand if absi(operand) >= 1 and absi(operand) <= 6 else 1
		48: return maxi(operand, 0)
		110: return operand if operand != 0 and absi(operand) <= 20 else 1
	return operand


func _choose_action() -> void:
	var current := _current(selected_slot)
	action_dialog.show_for(int(current.opcode), {"where": "step %d of 8" % (selected_slot + 1), "record": _record_label(), "family": family, "branch": branch, "slot": selected_slot, "operand": int(current.operand), "operand_for": _operand_for}, recent_operations)


func _action_chosen(opcode: int) -> void:
	recent_operations.erase(opcode)
	recent_operations.push_front(opcode)
	recent_operations = recent_operations.slice(0, 6)
	await set_step(selected_slot, opcode, _operand_for(opcode))


## Swaps the chosen step with its neighbour; both must be steps the editor authors.
func move_step(delta: int) -> void:
	var other := selected_slot + delta
	if program.is_empty() or other < 0 or other > 7: return
	if not program.steps[selected_slot].authorable or not program.steps[other].authorable:
		shell.status("A preserved step stays where it is", "warn")
		return
	var a := _current(selected_slot)
	var b := _current(other)
	await set_step(selected_slot, int(b.opcode), int(b.operand))
	await set_step(other, int(a.opcode), int(a.operand))
	selected_slot = other
	_show()


## Copies the chosen step into the first empty slot, if one is free.
func duplicate_step() -> void:
	var current := _current(selected_slot)
	for slot in range(8):
		var view := _view(branch, slot)
		if slot != selected_slot and int(view.opcode) == 0 and view.authorable:
			await set_step(slot, int(current.opcode), int(current.operand))
			selected_slot = slot
			_show()
			return
	shell.status("All 8 slots are used. Free one to add a step.", "warn")


# ── what is shown ──

func _detach_after() -> void:
	if _after_card.get_parent() != null: _after_card.get_parent().remove_child(_after_card)


## Rebuilds the header, cards and steps for the open program.
func _show() -> void:
	if program.is_empty(): return
	_loading_view = true
	_detach_after()
	var walking: bool = family in ["walking", "story"]
	_walking_main.visible = walking
	_encounter_main.visible = not walking
	_cards.visible = walking
	if walking and panel.get_parent() != _walking_panel_slot: panel.reparent(_walking_panel_slot)
	if not walking and panel.get_parent() != _panel_slot: panel.reparent(_panel_slot)
	_conditions.visible = family != "story"
	_reveal.visible = family == "walking"
	_show_header()
	if walking:
		_walking_steps()
		_walking_cards()
	else:
		_encounter()
	_show_cards()
	_show_step()
	_loading_view = false


func _show_header() -> void:
	for child in _badges.get_children(): _badges.remove_child(child); child.queue_free()
	var key_value := int(program.get("location_key", 0))
	_title.text = "%s %d" % [TITLES[family], id] if family != "walking" else "Walking trigger W%d" % (id % 100)
	var opcode: int = {"menu": 4, "typed": 5}.get(family, 0)
	if opcode != 0:
		var row := Capability.row(opcode)
		for text in ["opcode %d" % opcode, str(row.get("status", "")), str(row.get("editor", ""))]:
			if text.is_empty(): continue
			var label := Label.new()
			label.theme_type_variation = &"Badge" if text.begins_with("opcode") or text == "source-ported" else (&"BadgeGood" if text in ["allow", "native-verified"] else &"BadgeWarn")
			label.text = text
			_badges.add_child(label)
	if family == "story":
		var label := Label.new()
		label.theme_type_variation = &"BadgeGood"
		label.text = "story"
		_badges.add_child(label)
	_sub.text = "%s · record %d" % [TABLES[family], id]
	if family == "walking": _sub.text = ("Map %d · cell %d, %d · walking table record %d" % [key_value / 10000, key_value % 100, (key_value / 100) % 100, id]) if key_value >= 0 else "Map %d · unplaced · walking table record %d" % [id / 100, id]


func _walking_cards() -> void:
	for child in _cards.get_children(): _cards.remove_child(child); child.queue_free()
	var key_value := int(program.location_key)
	var destination: Dictionary = program.destination
	if family == "walking":
		var placement := Card.new()
		placement.title = "Placement"
		placement.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cards.add_child(placement)
		_kv(placement.body, "Map", "Map %d" % (key_value / 10000 if key_value >= 0 else id / 100))
		_kv(placement.body, "Cell", "x %d · y %d" % [key_value % 100, (key_value / 100) % 100] if key_value >= 0 else "unplaced", true)
		_note(placement.body, "Place and move it in Maps.")
		var activation := Card.new()
		activation.title = "Activation"
		activation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cards.add_child(activation)
		var chance_key := JSON.stringify({"kind": "walking_chance", "id": id})
		var saved := int(program.chance)
		var chance := SpinBox.new()
		chance.max_value = 100
		chance.suffix = "%"
		chance.value = int(shell.drafts.get(chance_key, {}).get("chance", saved))
		chance.editable = program.get("conditions", {}).get("chance_authorable", false)
		chance.custom_minimum_size.x = 100
		chance.value_changed.connect(func(value):
			if _loading_view: return
			if int(value) == saved: shell.drafts.erase(chance_key)
			else: shell.drafts[chance_key] = {"kind": "walking_chance", "id": id, "chance": int(value)}
			shell._invalidate_receipt()
			shell._update_buttons())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var label := Label.new()
		label.theme_type_variation = &"Dim"
		label.text = "Chance"
		label.custom_minimum_size.x = 80
		row.add_child(label)
		row.add_child(chance)
		activation.add_row(row)
		_kv(activation.body, "Gate", "location key %d" % key_value, true)
		_kv(activation.body, "Stamp", str(int(destination.stamp)), true)
		_after_card.title = "After the steps"
		_after_card.visible = true
		_cards.add_child(_after_card)
	else:
		var header := Card.new()
		header.title = "Header"
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var badge := Label.new()
		badge.theme_type_variation = &"BadgeDim"
		badge.text = "preserved"
		header.right.add_child(badge)
		_cards.add_child(header)
		_kv(header.body, "Location key", str(key_value), true)
		_kv(header.body, "Chance", str(int(program.chance)), true)
		_kv(header.body, "Destination", "%d · %d, %d" % [int(destination.map), int(destination.x), int(destination.y)], true)
		_after_card.title = "Linked records"
		_after_card.visible = false
		_cards.add_child(_after_card)


func _kv(parent: Control, key_text: String, value: String, mono := false) -> void:
	var row := KeyValueRow.new()
	row.key = key_text
	row.value = value
	row.mono = mono
	row.key_width = 84
	parent.add_child(row)


func _note(parent: Control, text: String) -> void:
	var label := Label.new()
	label.theme_type_variation = &"Dim"
	label.add_theme_font_size_override("font_size", 12)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	parent.add_child(label)


## One card for each of the eight steps of `branch_number`, in `parent`.
func _step_cards(parent: Control, branch_number: int) -> void:
	var cards: Array = []
	for slot in range(8):
		var card := StepCard.new()
		card.button_group = _group
		card.pressed.connect(func(): select_step(branch_number, slot))
		parent.add_child(card)
		cards.append(card)
	_cards_by_branch[branch_number] = cards


## The steps of a walking trigger or story, listed in one column.
func _walking_steps() -> void:
	for child in _steps_column.get_children():
		_steps_column.remove_child(child)
		if child != _steps_title: child.queue_free()
	_steps_column.add_child(_steps_title)
	_cards_by_branch.clear()
	_branch_titles.clear()
	_step_cards(_steps_column, 0)


func _show_cards() -> void:
	if program.is_empty(): return
	for branch_number in _cards_by_branch:
		var cards: Array = _cards_by_branch[branch_number]
		if not branch_programs.has(branch_number) or not branch_programs[branch_number].has("steps"): continue
		var used := 0
		for slot in range(cards.size()):
			if not is_instance_valid(cards[slot]): continue
			var view := _view(branch_number, slot)
			if int(view.opcode) != 0: used += 1
			var message_text := ""
			if int(view.opcode) == 1 and _messages.has(absi(int(view.operand))): message_text = str(_messages[absi(int(view.operand))].text).replace("\n", " ").left(40)
			var warns: bool = view.authorable and Capability.row(int(view.opcode)).get("editor", "") == "warn"
			cards[slot].show_step(view, Capability.name_of(int(view.opcode), view.authorable), Capability.subtitle(int(view.opcode), int(view.operand), view.authorable, message_text), Capability.kind_of(int(view.opcode), view.authorable), view.drafted, warns)
			cards[slot].set_pressed_no_signal(branch_number == branch and slot == selected_slot)
		if family in ["walking", "story"]: _steps_title.text = "ORDERED STEPS  %d of 8 used" % used
		if _branch_titles.has(branch_number): _branch_titles[branch_number].text = "%d/8" % used


func _encounter() -> void:
	for child in _branch_row.get_children(): _branch_row.remove_child(child); child.queue_free()
	_cards_by_branch.clear()
	_branch_titles.clear()
	_info()
	for branch_number in range(4):
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 4)
		var head := HBoxContainer.new()
		var name := Label.new()
		name.theme_type_variation = &"Heading"
		name.add_theme_font_size_override("font_size", 14)
		name.text = "Branch %d" % branch_number
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name)
		var used := Label.new()
		used.theme_type_variation = &"MonoDim"
		head.add_child(used)
		_branch_titles[branch_number] = used
		column.add_child(head)
		var info: Dictionary = branch_programs.get(branch_number, {})
		var opens := Label.new()
		opens.theme_type_variation = &"Dim"
		opens.clip_text = true
		opens.text = "Choice %d · %s" % [branch_number + 1, _choice_label(branch_number)] if family == "menu" else " "
		_branch_opens[branch_number] = opens
		column.add_child(opens)
		_step_cards(column, branch_number)
		_branch_row.add_child(column)


func _info() -> void:
	for child in _info_column.get_children(): _info_column.remove_child(child); child.queue_free()
	var prompt := Card.new()
	prompt.title = "Prompt"
	prompt.dot_color = Capability.colour("encounter")
	_info_column.add_child(prompt)
	var dialogue := int(program.get("dialogue", 0))
	if family == "menu":
		_prompt_editor(prompt)
	else:
		_kv(prompt.body, "Message", str(dialogue), true)
		var text: String = str(_messages.get(dialogue, {}).get("text", ""))
		if not text.is_empty(): _note(prompt.body, text.replace("\n", " ").left(160))
	var choices := Card.new()
	choices.title = "Choices" if family == "menu" else "Selectors"
	choices.dot_color = Capability.colour("encounter")
	_info_column.add_child(choices)
	if family == "menu":
		_choice_boxes.clear()
		for branch_number in range(4):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var number := Label.new()
			number.theme_type_variation = &"MonoDim"
			number.text = str(branch_number + 1)
			number.custom_minimum_size.x = 14
			row.add_child(number)
			var box := LineEdit.new()
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.placeholder_text = "empty"
			box.max_length = 79
			box.text = _choice_label(branch_number)
			var which := branch_number
			box.text_changed.connect(func(text): _choice_edited(which, text))
			_choice_boxes[branch_number] = box
			row.add_child(box)
			choices.add_row(row)
		_note(choices.body, "Each label is at most 79 characters.")
	else:
		var selectors: Dictionary = program.get("selectors", {})
		_kv(choices.body, "Physical", str(int(selectors.get("physical", 0))), true)
		_kv(choices.body, "Password", str(int(selectors.get("password", 0))), true)
		_kv(choices.body, "Attempts", str(int(selectors.get("attempts", 0))), true)
		_note(choices.body, "Selectors are edited in Conditions.")
	_after_card.title = "Linked records"
	_after_card.visible = family == "menu"
	_info_column.add_child(_after_card)


## The label of choice `branch_number` of the open choice encounter: the unapplied one, else the saved one.
func _choice_label(branch_number: int) -> String:
	var key := "choice_label:%d:%d" % [id, branch_number]
	if shell.drafts.has(key): return str(shell.drafts[key].text)
	return str(branch_programs.get(branch_number, {}).get("label", ""))


func _choice_edited(branch_number: int, text: String) -> void:
	var key := "choice_label:%d:%d" % [id, branch_number]
	if text == str(branch_programs.get(branch_number, {}).get("label", "")): shell.drafts.erase(key)
	else: shell.drafts[key] = {"kind": "choice_label", "id": id, "choice": branch_number, "text": text}
	if _branch_opens.has(branch_number) and is_instance_valid(_branch_opens[branch_number]): _branch_opens[branch_number].text = "Choice %d · %s" % [branch_number + 1, text]
	shell._invalidate_receipt()
	shell._update_buttons()


## The prompt of a choice encounter: the message it shows, its number and its words, editable here.
func _prompt_editor(card: Card) -> void:
	var saved := int(program.get("dialogue", 0))
	var key := "choice_prompt:%d" % id
	var shown := int(shell.drafts.get(key, {}).get("message", saved))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var caption := Label.new()
	caption.theme_type_variation = &"Dim"
	caption.text = "Message"
	line.add_child(caption)
	var number := SpinBox.new()
	number.min_value = 0
	number.max_value = 32767
	number.rounded = true
	number.custom_minimum_size.x = 100
	number.set_value_no_signal(shown)
	line.add_child(number)
	card.add_row(line)
	var words := TextEdit.new()
	words.custom_minimum_size.y = 96
	words.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	card.add_row(words)
	var count := Label.new()
	count.theme_type_variation = &"Dim"
	card.add_row(count)
	var fill := func(message: int) -> void:
		await ensure_message(message)
		if not is_instance_valid(words): return
		words.text = str(_messages.get(message, {}).get("text", ""))
		count.text = "%d bytes of 255" % int(_messages.get(message, {}).get("bytes", 0))
	fill.call(shown)
	number.value_changed.connect(func(value):
		var message := int(value)
		if message == saved: shell.drafts.erase(key)
		else: shell.drafts[key] = {"kind": "choice_prompt", "id": id, "message": message}
		shell._invalidate_receipt()
		shell._update_buttons()
		fill.call(message))
	words.text_changed.connect(func():
		var message := int(number.value)
		var draft_key := "message:%d" % message
		var response: Dictionary = await shell.request_backend({"op": "message", "id": message})
		var stored: String = str(response.result.text) if response.get("ok", false) else ""
		if words.text == stored: shell.drafts.erase(draft_key)
		else: shell.drafts[draft_key] = {"kind": "message", "id": message, "text": words.text}
		_messages.erase(message)
		count.text = "%d bytes of 255" % words.text.to_utf8_buffer().size()
		shell._invalidate_receipt()
		shell._update_buttons())


func select_step(branch_number: int, slot: int) -> void:
	selected_slot = slot
	if branch_number != branch:
		await choose(family, id, branch_number)
		return
	_show_cards()
	_show_step()


var _extra_cache: Dictionary = {}
var _extra_revision := -1


## The Extra Codes row the chosen step names, with the steps that name it, as read when the program was loaded.
func _extra_for(view: Dictionary) -> Dictionary:
	var record := int(view.operand)
	if not Capability.uses_extra(int(view.opcode)) or record < 0: return {}
	return _extra_cache.get(record, {})


## Reads the row once for the program being loaded; requests are never overlapped.
func ensure_extra(record: int) -> void:
	if _extra_cache.has(record) or record < 0: return
	var response: Dictionary = await shell.request_backend({"op": "extra_impact", "record": record})
	if response.get("ok", false): _extra_cache[record] = response.result


## The words of the row as the author sees them: the draft over the saved ones.
func _extra_words_of(record: int) -> Array:
	var draft: Dictionary = shell.drafts.get("extra_row:%d" % record, {})
	if not draft.is_empty(): return draft.words.map(func(word): return int(word))
	return _extra_cache.get(record, {}).get("words", []).map(func(word): return int(word))


## A word of the row changes; the row becomes one draft, or none when it is as saved, so a jump type and its target change together.
func _extra_word_edited(record: int, index: int, value: int) -> void:
	var saved: Dictionary = _extra_cache.get(record, {})
	if saved.is_empty(): return
	var words := _extra_words_of(record)
	words[index] = value
	var draft_key := "extra_row:%d" % record
	if words == saved.words.map(func(word): return int(word)): shell.drafts.erase(draft_key)
	else: shell.drafts[draft_key] = {"kind": "extra_row", "record": record, "words": words}
	shell._invalidate_receipt()
	shell._update_buttons()


func _extra_key() -> String:
	return "extra_independent:%s:%d:%d:%d" % [family, id, branch, selected_slot]


func _extra_independent() -> void:
	shell.drafts[_extra_key()] = {"kind": "extra_independent", "family": family, "id": id, "branch": branch, "slot": selected_slot}
	shell._invalidate_receipt()
	shell._update_buttons()
	_show_step()


func _show_step() -> void:
	if program.is_empty(): return
	var view := _current(selected_slot)
	var extra := _extra_for(view)
	var words: Array = _extra_words_of(int(extra.record)) if not extra.is_empty() else []
	var companion: Dictionary = _extra_cache.get(int(view.operand) + 1, {}) if Capability.has_companion(int(view.opcode)) else {}
	var companion_words: Array = _extra_words_of(int(companion.record)) if not companion.is_empty() else []
	var message: Dictionary = _messages.get(absi(int(view.operand)), {}) if int(view.opcode) == 1 else {}
	panel.show_step({"family": family, "branch": branch, "slot": selected_slot, "opcode": int(view.opcode), "operand": int(view.operand), "authorable": view.authorable,
		"summary": _summary_with_counts(), "message": message, "extra": extra, "extra_words": words, "extra_companion": companion, "extra_companion_words": companion_words, "extra_independent": shell.drafts.has(_extra_key()), "has_free": _has_free(), "count": 8, "branch_label": "Branch %d" % branch if family in ["menu", "typed"] else ""})
	_show_details()
	if helper.visible: helper.show_step(_where(), int(view.opcode), view.authorable)


func _summary_with_counts() -> Dictionary:
	var summary: Dictionary = shell.summary.duplicate()
	for table in shell.summary.get("tables", []):
		if table.file == "Data SD2": summary["messages"] = int(table.complete_records)
	return summary


func _has_free() -> bool:
	for slot in range(8):
		var view := _view(branch, slot)
		if slot != selected_slot and int(view.opcode) == 0 and view.authorable: return true
	return false


func _where() -> String:
	return "%s · %sstep %d" % [_record_label(), ("branch %d · " % branch) if family in ["menu", "typed"] else "", selected_slot + 1]


func _show_details() -> void:
	if panel.details_button.button_pressed: _show_bytes()


func _show_bytes() -> void:
	if not panel.details_button.button_pressed or program.is_empty(): return
	var response: Dictionary = await shell.request_backend({"op": "program_bytes", "family": family, "id": id})
	if response.get("ok", false):
		var view := _current(selected_slot)
		panel.show_bytes(response.result, family, branch, selected_slot, int(view.opcode), int(view.operand))
		# The details open below the form; bring them into view.
		await get_tree().process_frame
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


## Shows the code helper for the chosen step, or hides it.
func toggle_helper() -> void:
	if helper.visible:
		helper.hide()
		return
	if program.is_empty(): return
	var view := _current(selected_slot)
	helper.show_step(_where(), int(view.opcode), view.authorable)
	helper.show()


# ── links ──

func reveal_on_map() -> void:
	if family != "walking" or program.is_empty(): return
	var key_value := int(program.location_key)
	shell.maps.map_id = key_value / 10000
	await shell._show_route(shell.ROUTES.find("Maps"))
	var cell := Vector2i(key_value % 100, (key_value / 100) % 100)
	shell.maps.canvas.selected_cell = cell
	shell.maps.canvas.center_on(cell)
	shell.maps.cell_selected(cell, 0)


## Opens what the step names: its message, record, stage or program. The
## guard has applied or discarded drafts first, so the saved step is read.
func follow_step(slot: int) -> void:
	if program.is_empty(): return
	var step: Dictionary = program.steps[slot]
	var target := absi(int(step.operand))
	match int(step.opcode):
		1: await shell._show_route(2); await shell.messages.load_message(target)
		2, 10: await shell.record_ui.open_record({2: "battle_extra", 10: "reward"}[int(step.opcode)], target)
		110: shell.stages.stage_id = target - 1; await shell._show_route(1)
		4, 5, 39: await choose({4: "menu", 5: "typed", 39: "story"}[int(step.opcode)], target, 0)


## Cards and titles that are taken out of the page while another family shows are freed with it.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE: return
	for node in [_after_card, _steps_title]:
		if is_instance_valid(node) and node.get_parent() == null: node.free()
