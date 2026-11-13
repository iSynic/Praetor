extends "res://src/widgets/modal_overlay.gd"
## Add a map: a blank one or a copy of another, with a review of what the three map files gain before anything is
## drafted. Adding is one undo step.
signal map_added(id: int)

var _shell: Control
var _blank := CheckBox.new()
var _copy := CheckBox.new()
var _source := OptionButton.new()
var _tile := SpinBox.new()
var _floor := CheckBox.new()
var _objects := CheckBox.new()
var _triggers := CheckBox.new()
var _regions := CheckBox.new()
var _intro := Label.new()
var _review := VBoxContainer.new()
var _add: Button
var _loading := false
var _limit_reached := false


func _init() -> void:
	super()
	title = "Add a map"
	panel_size = Vector2(720, 0)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	body.add_child(stack)
	_intro.theme_type_variation = &"Dim"
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_intro)
	stack.add_child(_heading("Start from"))
	var group := ButtonGroup.new()
	for entry in [[_blank, "A blank map", "Every floor cell is one tile; no objects, event cells, regions or walking triggers."], [_copy, "A copy of another map", "The parts chosen below are copied; the map number inside each trigger's key is renumbered."]]:
		entry[0].button_group = group
		entry[0].text = entry[1]
		entry[0].toggled.connect(func(_on): if not _loading: _changed())
		stack.add_child(entry[0])
		var note := Label.new()
		note.theme_type_variation = &"Dim"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.text = entry[2]
		stack.add_child(note)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	var copy_label := Label.new()
	copy_label.theme_type_variation = &"Dim"
	copy_label.text = "Copy of"
	line.add_child(copy_label)
	_source.custom_minimum_size.x = 170
	_source.item_selected.connect(func(_index): if not _loading: _changed())
	line.add_child(_source)
	var tile_label := Label.new()
	tile_label.theme_type_variation = &"Dim"
	tile_label.text = "Floor tile"
	line.add_child(tile_label)
	_tile.min_value = 0
	_tile.max_value = 300
	_tile.rounded = true
	_tile.custom_minimum_size.x = 90
	_tile.tooltip_text = "Fills the floor that is not copied; 0 shows the terrain's background tile"
	line.add_child(_tile)
	stack.add_child(line)
	stack.add_child(_heading("Copy"))
	for entry in [[_floor, "Floor"], [_objects, "Objects"], [_triggers, "Walking triggers and their event cells"], [_regions, "Regions and the map's look"]]:
		entry[0].text = entry[1]
		entry[0].button_pressed = true
		entry[0].toggled.connect(func(_on): if not _loading: _changed())
		stack.add_child(entry[0])
	stack.add_child(_heading("Review"))
	_review.add_theme_constant_override("separation", 6)
	stack.add_child(_review)
	add_button("Cancel").pressed.connect(close)
	_add = add_button("Add map", "primary")
	_add.pressed.connect(_commit)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"CaptionMuted"
	label.uppercase = true
	label.text = text
	return label


func setup(owner_shell: Control) -> void:
	_shell = owner_shell


## Opens with a copy of `current` chosen, or a blank map when the scenario has none.
func show_for(current: int, tile: int) -> void:
	var maps := int(_shell.summary.get("maps", 0))
	_loading = true
	_source.clear()
	for id in range(maps): _source.add_item("Map %d" % id, id)
	if maps > 0: _source.select(clampi(current, 0, maps - 1))
	_copy.button_pressed = maps > 0
	_blank.button_pressed = maps == 0
	_tile.value = tile
	_loading = false
	open()
	await _changed()


func _copy_of() -> Variant:
	return _source.get_selected_id() if _copy.button_pressed and _source.item_count > 0 else null


func _changed() -> void:
	var copying := _copy.button_pressed
	_source.disabled = not copying
	for box in [_floor, _objects, _triggers, _regions]: box.disabled = not copying
	_tile.editable = not copying or not _floor.button_pressed
	var maps := int(_shell.summary.get("maps", 0))
	var limit := 20
	_limit_reached = maps >= limit
	_intro.text = "The scenario holds %d maps of at most %d. The new map is Map %d." % [maps, limit, maps]
	var response: Dictionary = await _shell.request_backend({"op": "map_review", "copy_of": _copy_of(), "floor": _floor.button_pressed, "objects": _objects.button_pressed, "triggers": _triggers.button_pressed, "regions": _regions.button_pressed})
	for child in _review.get_children(): _review.remove_child(child); child.queue_free()
	_add.text = "Add Map %d" % maps
	_add.disabled = _limit_reached or not response.get("ok", false)
	if not response.get("ok", false):
		_review.add_child(_line("The review could not be made", _shell._error(response)))
		return
	for entry in response.result.adds: _review.add_child(_line(str(entry.file), "+ %s bytes · %s" % [_thousands(int(entry.bytes)), str(entry.note)]))
	for entry in response.result.replaces: _review.add_child(_note(str(entry.note)))
	if bool(_triggers.button_pressed) and copying: _review.add_child(_line("Renumbered keys", "%d cells · %d rows" % [int(response.result.renumbered_cells), int(response.result.renumbered_rows)]))
	_review.add_child(_note("Stages, calendar entries and stories keep naming the maps they name now. Nothing is added to them."))
	if _limit_reached: _review.add_child(_note("A level holds at most %d maps." % limit))
	refit()


func _line(left: String, right: String) -> Control:
	var row := HBoxContainer.new()
	var name := Label.new()
	name.text = left
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var value := Label.new()
	value.theme_type_variation = &"Dim"
	value.text = right
	row.add_child(value)
	return row


func _note(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"Muted"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	return label


func _thousands(number: int) -> String:
	var text := str(number)
	var out := ""
	for index in range(text.length()):
		if index > 0 and (text.length() - index) % 3 == 0: out += ","
		out += text[index]
	return out


func _commit() -> void:
	var maps := int(_shell.summary.get("maps", 0))
	var copy: Variant = _copy_of()
	close()
	var response: Dictionary = await _shell.request_backend({"op": "add_map", "expected_revision": _shell.bridge.revision, "copy_of": copy, "tile": int(_tile.value),
		"floor": _floor.button_pressed or copy == null, "objects": _objects.button_pressed and copy != null,
		"triggers": _triggers.button_pressed and copy != null, "regions": _regions.button_pressed and copy != null})
	if not response.get("ok", false): return
	await _shell._set_summary(response.result)
	_shell.status("Map %d added · one undo step" % maps)
	map_added.emit(maps)
