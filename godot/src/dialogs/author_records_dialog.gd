extends "res://src/widgets/modal_overlay.gd"
## Author records: open a row of any record family, or clone an imported row as
## a new one. A clone takes its unresolved bytes from the seed; imported rows
## and tails stay intact. Everything it makes is one undo step.
const CheckRow = preload("res://src/widgets/check_row.gd")
const KbdButton = preload("res://src/widgets/kbd_button.gd")
const RecordList = preload("res://src/widgets/record_list.gd")
const RecordEditor = preload("res://src/record_editor.gd")

var shell: Control
var family := "monster"
var cloning := false
var list := RecordList.new()
var tables: Dictionary = {}
var _open_button: Button
var _clone_button: Button
var _chips: Dictionary = {}
var _checks := VBoxContainer.new()
var _after := CheckBox.new()
var _geometry := Label.new()
var _use: KbdButton
var _picked := 0
var _loading := false


func _init() -> void:
	super()
	title = "Author records"
	subtitle = "Open a row or clone a seed"
	panel_size = Vector2(860, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	body.add_child(column)
	var mode := HBoxContainer.new()
	mode.add_theme_constant_override("separation", 6)
	column.add_child(mode)
	var group := ButtonGroup.new()
	_open_button = _chip("Open existing", group, mode)
	_clone_button = _chip("Clone a seed", group, mode)
	_open_button.set_pressed_no_signal(true)
	_open_button.pressed.connect(func(): _set_mode(false))
	_clone_button.pressed.connect(func(): _set_mode(true))
	var families := HFlowContainer.new()
	families.add_theme_constant_override("h_separation", 6)
	families.add_theme_constant_override("v_separation", 6)
	column.add_child(families)
	var family_group := ButtonGroup.new()
	for name in RecordEditor.FAMILIES:
		var chip := _chip(RecordEditor.NOUNS[name], family_group, families)
		chip.set_pressed_no_signal(name == family)
		chip.pressed.connect(func(): _choose_family(name))
		_chips[name] = chip
	_geometry.theme_type_variation = &"Dim"
	_geometry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_geometry)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	list.filter_placeholder = "Filter by id or name…"
	list.custom_minimum_size = Vector2(380, 340)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.set_columns([{"title": "ID", "width": 60, "mono": true}, {"title": "Name", "width": 0}])
	list.row_selected.connect(func(id): if id != null and not _loading: _pick(int(id)))
	list.row_activated.connect(func(id): if id != null: _picked = int(id); _commit())
	row.add_child(list)
	var side := PanelContainer.new()
	side.theme_type_variation = &"Detail"
	side.custom_minimum_size.x = 380
	row.add_child(side)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	side.add_child(stack)
	var heading := Label.new()
	heading.theme_type_variation = &"CaptionMuted"
	heading.uppercase = true
	heading.text = "New row checks"
	stack.add_child(heading)
	_checks.add_theme_constant_override("separation", 6)
	stack.add_child(_checks)
	_after.text = "Edit after cloning"
	_after.button_pressed = true
	stack.add_child(_after)
	add_button("Cancel").pressed.connect(close)
	_use = KbdButton.new()
	_use.theme_type_variation = &"PrimaryButton"
	_use.hint = "Enter"
	_use.pressed.connect(_commit)
	add_footer_button(_use)


func _chip(text: String, group: ButtonGroup, parent: Control) -> Button:
	var chip := Button.new()
	chip.theme_type_variation = &"Chip"
	chip.toggle_mode = true
	chip.button_group = group
	chip.text = text
	parent.add_child(chip)
	return chip


func setup(owner_shell: Control) -> void:
	shell = owner_shell


## Opens on the family of the page in hand.
func show_for(record_family: String) -> void:
	family = record_family
	for name in _chips: _chips[name].set_pressed_no_signal(name == family)
	list.clear_filter()
	open()
	await _load()


func _set_mode(clone: bool) -> void:
	cloning = clone
	list.title = ("Seeds" if cloning else "Rows")
	_show_checks()


func _choose_family(name: String) -> void:
	family = name
	list.clear_filter()
	await _load()


func _load() -> void:
	if shell.summary.is_empty(): return
	var response: Dictionary = await shell.request_backend({"op": "authored_records"})
	if not response.get("ok", false): return
	tables.clear()
	for table in response.result.families: tables[str(table.family)] = table
	var table: Dictionary = tables[family]
	if family == "monster": await shell.record_ui._ensure_names()
	var rows: Array = []
	var shown := int(table.imported_count) if cloning else int(table.count)
	for index in range(shown):
		var label := "%s %d" % [RecordEditor.NOUNS[family], index]
		if family == "monster": label = str(shell.record_ui.names.get(index, ""))
		if family == "monster" and label.is_empty(): label = "Monster %d" % index
		rows.append({"id": index, "cells": [str(index), label]})
	_loading = true
	list.title = "Seeds" if cloning else "Rows"
	list.set_rows(rows)
	list.set_count(rows.size())
	_loading = false
	_geometry.text = "%s · %d rows (%d imported) · supported limit %d · %d trailing bytes retained" % [table.file, int(table.count), int(table.imported_count), int(table.supported_limit), int(table.trailing_bytes)]
	if not rows.is_empty():
		list.select(mini(_picked, rows.size() - 1))
		_pick(mini(_picked, rows.size() - 1))


func _pick(id: int) -> void:
	_picked = id
	_show_checks()


func _show_checks() -> void:
	for child in _checks.get_children(): _checks.remove_child(child); child.queue_free()
	if not tables.has(family): return
	var table: Dictionary = tables[family]
	var next := int(table.count)
	var room := next < int(table.supported_limit)
	_after.visible = cloning
	_open_button.set_pressed_no_signal(not cloning)
	_clone_button.set_pressed_no_signal(cloning)
	if cloning:
		_check("good" if room else "err", "The new row is %s %d" % [RecordEditor.NOUNS[family].to_lower(), next], "limit %d" % int(table.supported_limit))
		_check("good", "Unresolved bytes come from %s %d" % [RecordEditor.NOUNS[family].to_lower(), _picked])
		_check("good", "Imported rows and tails remain intact", "%d trailing bytes" % int(table.trailing_bytes))
		_check("good", "One undo step")
		_use.text = "Clone %s %d" % [RecordEditor.NOUNS[family].to_lower(), _picked]
	else:
		_check("good", "%s %d opens in its form" % [RecordEditor.NOUNS[family], _picked])
		_check("good", "Forms make drafts; Apply validates the whole batch")
		_use.text = "Open %s %d" % [RecordEditor.NOUNS[family].to_lower(), _picked]
	_use.disabled = cloning and not room


func _check(state: String, text: String, note := "") -> void:
	var row := CheckRow.new()
	row.state = state
	row.text = text
	row.note = note
	_checks.add_child(row)


func _commit() -> void:
	if _use.disabled: return
	close()
	var chosen := _picked
	if cloning:
		shell.record_ui.family.select(RecordEditor.FAMILIES.find(family))
		shell.record_ui.seed.value = chosen
		shell.guard(func():
			await shell.record_ui.clone_record()
			if _after.button_pressed: await shell.record_ui.open_record(family, int(shell.record_ui.id.value)))
	else: shell.guard(shell.record_ui.open_record.bind(family, chosen))


func _unhandled_key_input(event: InputEvent) -> void:
	super(event)
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_commit()
		get_viewport().set_input_as_handled()
