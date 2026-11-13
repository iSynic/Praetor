extends HBoxContainer
## Battles: the population of each battle on its 26 × 26 grid, edited by placing
## and erasing monsters. The grid holds signed monster ids, one to a cell; the
## battle's other fields are shown and kept. A placement is a draft for Apply.
## The catalogue also browses monster definitions, read only, for the Monsters
## page and for the verification drivers.
const Card = preload("res://src/widgets/card.gd")
const PageHeader = preload("res://src/widgets/page_header.gd")
const RecordList = preload("res://src/widgets/record_list.gd")
const Tokens = preload("res://theme/editor_tokens.gd")
const ToolButton = preload("res://src/maps/tool_button.gd")

const PAGE := 128

var shell: Control
var kind := OptionButton.new()
var details := TextEdit.new()
var population: Control = preload("res://src/battle_population.gd").new()
var list := RecordList.new()
var rows: Array = []
var offset := 0
var total := 0
var selected_id := 0
var header := PageHeader.new()
var tool := "select"
var monster_names: Dictionary = {}
var _model := Control.new()
var _saved_cells: Array = []
var _fields: Dictionary = {}
var _settings: Array = []
var _brush := SpinBox.new()
var _brush_name := Label.new()
var _fights := CheckBox.new()
var _hint := Label.new()
var _tools: Dictionary = {}
var _group := ButtonGroup.new()
var _cell_card := Card.new()
var _roster := VBoxContainer.new()
var _battle := VBoxContainer.new()
var _page_label := Label.new()
var _previous := Button.new()
var _next := Button.new()
var _search_timer := Timer.new()
var _names_key := ""
var _cell_spin := SpinBox.new()
var _cell_fights := CheckBox.new()
var _cell_name := Label.new()
var _loading := false
var _paging := false


func _init() -> void:
	add_theme_constant_override("separation", 12)
	_model.visible = false
	add_child(_model)
	kind.add_item("Battle populations")
	kind.add_item("Monster definitions")
	_model.add_child(kind)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 270
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	list.title = "Battles"
	list.filter_placeholder = "Filter by id or monster name…"
	list.filter_locally = false
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.set_columns([{"title": "ID", "width": 52, "mono": true}, {"title": "Battle", "width": 0}])
	list.row_selected.connect(func(id): if id != null: shell.guard(record.bind(int(id))))
	list.filter_changed.connect(func(_text): _search_timer.start())
	left.add_child(list)
	var pager := HBoxContainer.new()
	pager.add_theme_constant_override("separation", 6)
	_page_label.theme_type_variation = &"Dim"
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pager.add_child(_page_label)
	_previous.text = "‹"
	_previous.pressed.connect(func(): shell.guard(_page.bind(maxi(0, offset - PAGE))))
	pager.add_child(_previous)
	_next.text = "›"
	_next.pressed.connect(func(): if offset + PAGE < total: shell.guard(_page.bind(offset + PAGE)))
	pager.add_child(_next)
	left.add_child(pager)
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 10)
	add_child(centre)
	header.mark(Tokens.FAMILY.combat)
	header.add_button("Callers").pressed.connect(func(): shell.find_uses("battle", selected_id))
	header.add_button("Play battle", "Play arrives with the runtime")
	header.add_button("Duplicate", "Battles are added from Author records")
	centre.add_child(header)
	centre.add_child(_toolbar())
	population.size_flags_vertical = Control.SIZE_EXPAND_FILL
	population.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_child(population)
	var foot := Label.new()
	foot.theme_type_variation = &"Dim"
	foot.add_theme_font_size_override("font_size", 12)
	foot.text = "26 × 26 population layout · placements, not terrain · terrain and random placement come from the original runtime"
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	centre.add_child(foot)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 300
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 10)
	scroll.add_child(side)
	_cell_card.title = "Cell"
	side.add_child(_cell_card)
	var roster := Card.new()
	roster.title = "Roster"
	roster.add_row(_roster)
	_roster.add_theme_constant_override("separation", 6)
	side.add_child(roster)
	var battle := Card.new()
	battle.title = "Battle"
	battle.add_row(_battle)
	_battle.add_theme_constant_override("separation", 6)
	side.add_child(battle)
	var technical := Card.new()
	technical.title = "Retained record"
	details.editable = false
	details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	details.custom_minimum_size.y = 120
	technical.add_row(details)
	side.add_child(technical)
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.3
	add_child(_search_timer)
	_build_cell_card()


func _toolbar() -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	for entry in [["select", "Select"], ["place", "Place"], ["erase", "Erase"]]:
		var button := ToolButton.new()
		button.text = entry[1]
		button.button_group = _group
		button.set_pressed_no_signal(entry[0] == tool)
		button.pressed.connect(func(): select_tool(entry[0]))
		row.add_child(button)
		_tools[entry[0]] = button
	var brush_label := Label.new()
	brush_label.theme_type_variation = &"Dim"
	brush_label.text = "Brush"
	row.add_child(brush_label)
	_brush.min_value = 1
	_brush.max_value = 32767
	_brush.value = 1
	_brush.custom_minimum_size.x = 90
	_brush.value_changed.connect(func(_value): _show_brush())
	row.add_child(_brush)
	_brush_name.theme_type_variation = &"Muted"
	row.add_child(_brush_name)
	_fights.text = "Fights for the squad"
	row.add_child(_fights)
	_hint.theme_type_variation = &"Dim"
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_hint)
	_show_hint()
	return row


func _build_cell_card() -> void:
	_cell_spin.min_value = 1
	_cell_spin.max_value = 32767
	_cell_spin.custom_minimum_size.x = 100
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.theme_type_variation = &"Dim"
	label.text = "Monster"
	row.add_child(label)
	row.add_child(_cell_spin)
	_cell_name.theme_type_variation = &"Muted"
	_cell_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cell_name.clip_text = true
	row.add_child(_cell_name)
	_cell_card.add_row(row)
	_cell_fights.text = "Fights for the squad"
	_cell_card.add_row(_cell_fights)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	var open := Button.new()
	open.text = "Open monster"
	open.pressed.connect(func(): shell.guard(open_monster))
	buttons.add_child(open)
	var clear := Button.new()
	clear.text = "Clear cell"
	clear.pressed.connect(func(): _put(population.selected, 0))
	buttons.add_child(clear)
	_cell_card.add_row(buttons)
	_cell_spin.value_changed.connect(func(_value): _cell_edited())
	_cell_fights.toggled.connect(func(_on): _cell_edited())


func setup(owner_shell: Control) -> void:
	shell = owner_shell
	shell.name_node("BattleBrush", _brush)
	kind.item_selected.connect(func(_index): shell.guard(catalogue.bind(0)))
	_search_timer.timeout.connect(func(): shell.guard(catalogue.bind(0)))
	population.cell_clicked.connect(_cell_clicked)
	population.cell_erase_requested.connect(func(cell): _put(cell, 0))
	population.cell_hovered.connect(func(_cell): population.queue_redraw())
	population.monster_requested.connect(func(id): shell.guard(open_monster_id.bind(id)))


func select_tool(name: String) -> void:
	tool = name
	population.tool = name
	for key in _tools: _tools[key].set_pressed_no_signal(key == name)
	_show_hint()
	population.queue_redraw()


func _show_hint() -> void:
	_hint.text = {"select": "Click a cell to inspect it · double-click a monster to open it", "place": "Click a cell to place monster %d · right-click erases" % int(_brush.value), "erase": "Click a cell to clear it"}.get(tool, "")


func _show_brush() -> void:
	_brush_name.text = str(monster_names.get(int(_brush.value), ""))
	_show_hint()


## Shows a battle on the Battles page, on the page of the list that holds it.
func open_battle(battle_id: int) -> void:
	kind.select(0)
	list.clear_filter()
	selected_id = battle_id
	await shell._show_route(6)


func _page(start: int) -> void:
	_paging = true
	await catalogue(start)
	_paging = false


## Fills the list from `start`; a refresh from the first page keeps the battle in hand.
func catalogue(start: int) -> void:
	if shell.summary.is_empty(): return
	if start == 0 and not _paging and list.filter_text().is_empty() and kind.selected == 0: start = floori(selected_id / float(PAGE)) * PAGE
	var response: Dictionary = await shell.request_backend({"op": "combat_catalogue", "monsters": kind.selected == 1, "offset": start, "query": list.filter_text()})
	population.set_cells([])
	details.text = ""
	if not response.get("ok", false): details.text = shell._error(response); return
	offset = start
	total = int(response.result.total)
	rows = response.result.rows
	var shown: Array = []
	for row in rows: shown.append({"id": int(row.id), "cells": ["%s%d" % ["M" if kind.selected == 1 else "B", int(row.id)], str(row.name)]})
	list.title = "Monsters" if kind.selected == 1 else "Battles"
	list.set_rows(shown)
	list.set_count(total)
	_page_label.text = "%d–%d of %d" % [mini(start + 1, total), mini(start + PAGE, total), total]
	_previous.disabled = start == 0
	_next.disabled = start + PAGE >= total
	if not rows.is_empty():
		var pick := int(rows[0].id)
		for row in rows:
			if int(row.id) == selected_id: pick = selected_id
		list.select(pick)
		await record(pick)


## The monsters' names, read once for each project, for the brush and the roster.
func _ensure_names() -> void:
	var key := str(shell.summary.get("path", ""))
	if key == _names_key: return
	_names_key = key
	monster_names.clear()
	var start := 0
	while true:
		var response: Dictionary = await shell.request_backend({"op": "combat_catalogue", "monsters": true, "offset": start, "query": ""})
		if not response.get("ok", false): break
		for row in response.result.rows: monster_names[int(row.id)] = str(row.name)
		start += PAGE
		if start >= int(response.result.total): break


func record(id: int) -> void:
	selected_id = id
	var monsters := kind.selected == 1
	var response: Dictionary = await shell.request_backend({"op": "combat_record", "monsters": monsters, "id": id})
	population.visible = not monsters
	if not response.get("ok", false):
		details.text = shell._error(response)
		population.set_cells([])
		return
	var result: Dictionary = response.result
	var text := "%s · record %d · read-only\n" % [result.file, id]
	for key in result.fields: text += "%s: %s\n" % [key, str(int(result.fields[key])) if result.fields[key] is float else str(result.fields[key])]
	text += "\nRetained native record (hex):\n" + str(result.raw_hex)
	details.text = text
	list.select(id)
	if monsters:
		header.title.text = "Monster %d · %s" % [id, str(result.fields.get("Name", ""))]
		header.sub.text = "Monster table MD · record %d · read-only here; the Monsters page edits it" % id
		header.show_badges([["monster record", &"BadgeDim"]])
		return
	await _ensure_names()
	_fields = result.fields
	_settings = result.get("settings", [])
	_saved_cells = result.cells.map(func(value): return int(value))
	var cells: Array = _saved_cells.duplicate()
	var draft: Dictionary = shell.drafts.get("battle_population:%d" % id, {})
	if not draft.is_empty(): cells = _cells_of(draft.units)
	population.names = monster_names.duplicate()
	for actor in result.actors: population.names[absi(int(actor.monster))] = str(actor.name)
	population.squad_start = Vector2i(int(_fields.get("Squad start X", -1)), int(_fields.get("Squad start Y", -1)))
	population.selected = Vector2i(-1, -1)
	population.set_cells(cells)
	await _load_icons()
	_show_battle()


## Reads the pictures of the monsters in the grid and the brush, and draws the grid with them.
func _load_icons() -> void:
	await shell.references.ensure_monsters()
	var wanted: Array = []
	var ids: Array = []
	for value in population.cells:
		var id := absi(int(value))
		if id != 0 and not ids.has(id): ids.append(id)
	if not ids.has(int(_brush.value)): ids.append(int(_brush.value))
	for id in ids: wanted.append(int(shell.references.monsters.get(id, {}).get("icon", 0)))
	await shell.references.fetch(wanted)
	var textures := {}
	for id in ids:
		var texture: Texture2D = shell.references.icon(int(shell.references.monsters.get(id, {}).get("icon", 0)))
		if texture != null: textures[id] = texture
	population.icons = textures
	population.queue_redraw()
	_show_roster()


func _cells_of(units: Array) -> Array:
	var cells: Array = []
	cells.resize(676)
	cells.fill(0)
	for unit in units: cells[int(unit.x) * 26 + int(unit.y)] = int(unit.monster)
	return cells


func _units_of(cells: Array) -> Array:
	var units: Array = []
	for x in range(26):
		for y in range(26):
			var id := int(cells[x * 26 + y])
			if id != 0: units.append({"x": x, "y": y, "monster": id})
	return units


## The battle's header, roster, fixed fields and the cell in hand.
func _show_battle() -> void:
	var cells: Array = population.cells
	var placed := 0
	var counts: Dictionary = {}
	for value in cells:
		var id := int(value)
		if id == 0: continue
		placed += 1
		counts[absi(id)] = int(counts.get(absi(id), 0)) + 1
	header.title.text = "Battle %d" % selected_id
	header.sub.text = "Battle table BD · record %d · %d monsters from %d records" % [selected_id, placed, counts.size()]
	header.show_badges([["battle grid", &"BadgeDim"]] + ([["unapplied", &"BadgeWarn"]] if shell.drafts.has("battle_population:%d" % selected_id) else []))
	_show_roster()
	for child in _battle.get_children(): _battle.remove_child(child); child.queue_free()
	for setting in _settings:
		_battle.add_child(_setting_row(setting))
	var kept := Label.new()
	kept.theme_type_variation = &"Dim"
	kept.add_theme_font_size_override("font_size", 12)
	kept.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kept.text = "The population and these settings are edited; the other bytes are kept from the record."
	_battle.add_child(kept)
	_show_cell()


## The monsters placed in the grid, each with its picture, name and count.
func _show_roster() -> void:
	for child in _roster.get_children(): _roster.remove_child(child); child.queue_free()
	var counts: Dictionary = {}
	for value in population.cells:
		if int(value) != 0: counts[absi(int(value))] = int(counts.get(absi(int(value)), 0)) + 1
	var ids := counts.keys()
	ids.sort()
	for id in ids:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var picture := TextureRect.new()
		picture.custom_minimum_size = Vector2(32, 32)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.texture = population.icons.get(id)
		line.add_child(picture)
		var chip := Label.new()
		chip.theme_type_variation = &"Mono"
		chip.text = str(id)
		chip.add_theme_color_override("font_color", population.colour_of(id))
		chip.custom_minimum_size.x = 34
		line.add_child(chip)
		var name := Label.new()
		name.text = str(monster_names.get(id, population.names.get(id, "Monster %d" % id)))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.clip_text = true
		line.add_child(name)
		var count := Label.new()
		count.theme_type_variation = &"MonoDim"
		count.text = "× %d" % counts[id]
		line.add_child(count)
		var open := Button.new()
		open.text = "↗"
		open.theme_type_variation = &"GhostButton"
		open.pressed.connect(func(): shell.guard(open_monster_id.bind(id)))
		line.add_child(open)
		_roster.add_child(line)


## One setting of the battle after its grid, as a field whose change is a draft.
func _setting_row(setting: Dictionary) -> Control:
	var key := "battle_setting:%d:%s:%d" % [selected_id, setting.field, int(setting.index)]
	var shown := int(shell.drafts.get(key, {}).get("value", setting.value))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = str(setting.label)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	line.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = int(setting.minimum)
	spin.max_value = int(setting.maximum)
	spin.value = shown
	spin.custom_minimum_size.x = 96
	spin.value_changed.connect(func(value):
		if int(value) == int(setting.value): shell.drafts.erase(key)
		else: shell.drafts[key] = {"kind": "battle_setting", "id": selected_id, "field": setting.field, "index": int(setting.index), "value": int(value)}
		shell._invalidate_receipt()
		shell._update_buttons())
	line.add_child(spin)
	return line


func _show_cell() -> void:
	var cell: Vector2i = population.selected
	_cell_card.visible = true
	_loading = true
	if cell.x < 0:
		_cell_card.title = "Cell"
		_cell_spin.editable = false
		_cell_fights.disabled = true
		_cell_name.text = "Select a cell"
	else:
		var id := int(population.cells[cell.x * 26 + cell.y])
		_cell_card.title = "Cell %d, %d" % [cell.x, cell.y]
		_cell_spin.editable = true
		_cell_fights.disabled = false
		_cell_spin.value = maxi(absi(id), 1)
		_cell_fights.button_pressed = id < 0
		_cell_name.text = str(monster_names.get(absi(id), "")) if id != 0 else "empty · set a monster to place it"
	_loading = false


func _cell_clicked(cell: Vector2i) -> void:
	match tool:
		"place": _put(cell, int(_brush.value) * (-1 if _fights.button_pressed else 1))
		"erase": _put(cell, 0)
		_: _show_cell()


## Puts a signed monster id in a cell (0 clears it) and drafts the population.
func _put(cell: Vector2i, signed_id: int) -> void:
	if cell.x < 0 or population.cells.size() != 676 or shell.summary.is_empty(): return
	var cells: Array = population.cells.duplicate()
	cells[cell.x * 26 + cell.y] = signed_id
	population.take_colour(signed_id)
	population.selected = cell
	population.set_cells(cells)
	_draft(cells)
	_load_icons()


func _cell_edited() -> void:
	if _loading or population.selected.x < 0: return
	var id := int(_cell_spin.value) * (-1 if _cell_fights.button_pressed else 1)
	_put(population.selected, id)


func _draft(cells: Array) -> void:
	var key := "battle_population:%d" % selected_id
	if cells == _saved_cells: shell.drafts.erase(key)
	else: shell.drafts[key] = {"kind": "battle_population", "id": selected_id, "units": _units_of(cells)}
	shell._invalidate_receipt()
	shell._update_buttons()
	_show_battle()


func open_monster() -> void:
	var cell: Vector2i = population.selected
	if cell.x < 0: return
	var id := absi(int(population.cells[cell.x * 26 + cell.y]))
	if id != 0: await open_monster_id(id)


func open_monster_id(id: int) -> void:
	await shell.record_ui.open_record("monster", id)
