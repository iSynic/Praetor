extends HBoxContainer
## Stages and startup: each stage's name, arrival cell and start story, and
## the header opening of the mission pack. Every change is a draft for Apply.
const Capability = preload("res://src/scripts/capability.gd")
const Card = preload("res://src/widgets/card.gd")
const CheckRow = preload("res://src/widgets/check_row.gd")
const PageHeader = preload("res://src/widgets/page_header.gd")
const KeyValueRow = preload("res://src/widgets/key_value_row.gd")
const RecordList = preload("res://src/widgets/record_list.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

var shell: Control
var stage_id := 0
var list := RecordList.new()
var _scope := "all"
var _name := LineEdit.new()
var _name_count := Label.new()
var _map := SpinBox.new()
var _x := SpinBox.new()
var _y := SpinBox.new()
var _grid := Control.new()
var _story := SpinBox.new()
var _story_steps := VBoxContainer.new()
var _story_note := Label.new()
var _opening_map := SpinBox.new()
var _opening_x := SpinBox.new()
var _opening_y := SpinBox.new()
var _matches := CheckRow.new()
var header := PageHeader.new()
var _draft := Label.new()
var _open_story := Button.new()


func _init() -> void:
	add_theme_constant_override("separation", 12)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 270
	add_child(left)
	list.title = "Stages"
	list.filter_placeholder = "Filter stages"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.set_columns([{"title": "", "width": 34, "mono": true}, {"title": "", "width": 0}, {"title": "", "width": 90, "mono": true, "right": true}])
	list.set_scopes([{"id": "all", "label": "All"}, {"id": "used", "label": "In use"}, {"id": "unused", "label": "Unused"}])
	list.row_selected.connect(func(id): if id != null: shell.guard(select_stage.bind(int(id))))
	list.scope_changed.connect(func(id): _scope = str(id); list_stages(shell.summary))
	left.add_child(list)
	var foot := Label.new()
	foot.theme_type_variation = &"Dim"
	foot.add_theme_font_size_override("font_size", 12)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.text = "Stage numbers in transitions are one-based: step operand 3 starts stage 2."
	left.add_child(foot)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 12)
	scroll.add_child(centre)
	centre.add_child(_header())
	var name_card := Card.new()
	name_card.title = "Name"
	_name_count.theme_type_variation = &"MonoDim"
	name_card.right.add_child(_name_count)
	_name.name = "StageName"
	name_card.add_row(_name)
	centre.add_child(name_card)
	centre.add_child(_arrival_card())
	centre.add_child(_script_card())
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 260
	side.add_theme_constant_override("separation", 12)
	add_child(side)
	side.add_child(_opening_card())
	var preserved := Card.new()
	preserved.title = "Preserved"
	var badge := Label.new()
	badge.theme_type_variation = &"BadgeDim"
	badge.text = "read-only"
	preserved.right.add_child(badge)
	var kept := Label.new()
	kept.theme_type_variation = &"Muted"
	kept.add_theme_font_size_override("font_size", 12)
	kept.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kept.text = "Unlisted stage fields are kept exactly as imported."
	preserved.add_row(kept)
	side.add_child(preserved)
	_draft.theme_type_variation = &"Dim"
	side.add_child(_draft)


func _header() -> Control:
	header.mark(Tokens.START)
	header.show_badges([["mission record", &"BadgeDim"], ["464 bytes", &"BadgeDim"]])
	header.add_button("Callers").pressed.connect(func(): shell.find_uses("stage", stage_id))
	header.add_button("View flow").pressed.connect(func(): shell.view_stage_flow())
	header.add_button("Reveal on map").pressed.connect(func(): shell.guard(reveal_on_map))
	return header


func _arrival_card() -> Control:
	var card := Card.new()
	card.title = "Arrival"
	card.dot_color = Tokens.START
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_row(row)
	var fields := VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation", 8)
	row.add_child(fields)
	for entry in [["Map", _map, 19, "StageMap"], ["X", _x, 89, "StageX"], ["Y", _y, 89, "StageY"]]:
		entry[1].max_value = entry[2]
		entry[1].name = entry[3]
		var line := HBoxContainer.new()
		var label := Label.new()
		label.theme_type_variation = &"Dim"
		label.text = entry[0]
		label.custom_minimum_size.x = 50
		line.add_child(label)
		entry[1].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(entry[1])
		fields.add_child(line)
	var help := Label.new()
	help.theme_type_variation = &"Dim"
	help.add_theme_font_size_override("font_size", 12)
	help.text = "Where the squad lands when the stage begins."
	fields.add_child(help)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	var pick := Button.new()
	pick.text = "Pick on map"
	pick.pressed.connect(func(): shell.guard(pick_on_map))
	buttons.add_child(pick)
	var play := Button.new()
	play.text = "Play from stage start"
	play.disabled = true
	play.tooltip_text = "Play arrives with the runtime"
	buttons.add_child(play)
	fields.add_child(buttons)
	_grid.custom_minimum_size = Vector2(170, 170)
	_grid.draw.connect(_paint_grid)
	row.add_child(_grid)
	return card


## The map as a 90 × 90 field with the arrival cell marked.
func _paint_grid() -> void:
	var side := minf(_grid.size.x, _grid.size.y)
	_grid.draw_rect(Rect2(Vector2.ZERO, Vector2(side, side)), Tokens.FIELD)
	for step in range(0, 91, 10):
		var at := side * step / 90.0
		_grid.draw_line(Vector2(at, 0), Vector2(at, side), Tokens.LINE, 1.0)
		_grid.draw_line(Vector2(0, at), Vector2(side, at), Tokens.LINE, 1.0)
	var cell := Vector2(_x.value, _y.value) * side / 90.0
	_grid.draw_circle(cell + Vector2.ONE * side / 180.0, 5.0, Tokens.START, true, -1.0, true)


func _script_card() -> Control:
	var card := Card.new()
	card.title = "Start script"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.theme_type_variation = &"Dim"
	label.text = "Story"
	row.add_child(label)
	_story.name = "StageStartStory"
	_story.max_value = 32767
	row.add_child(_story)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	_open_story.text = "Open story ↗"
	_open_story.name = "OpenStartStory"
	row.add_child(_open_story)
	card.add_row(row)
	_story_note.theme_type_variation = &"Dim"
	_story_note.add_theme_font_size_override("font_size", 12)
	card.add_row(_story_note)
	_story_steps.add_theme_constant_override("separation", 3)
	card.add_row(_story_steps)
	return card


func _opening_card() -> Control:
	var card := Card.new()
	card.title = "Mission pack opening"
	var badge := Label.new()
	badge.theme_type_variation = &"BadgeDim"
	badge.text = "Data CS"
	card.right.add_child(badge)
	var about := Label.new()
	about.theme_type_variation = &"Muted"
	about.add_theme_font_size_override("font_size", 12)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.text = "Stage zero supplies the final native starting location. These are separate header values; changing them does not change stage-zero arrival."
	card.add_row(about)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for entry in [["Map", _opening_map, 19, "OpeningMap"], ["X", _opening_x, 89, "OpeningX"], ["Y", _opening_y, 89, "OpeningY"]]:
		entry[1].max_value = entry[2]
		entry[1].name = entry[3]
		entry[1].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var caption := Label.new()
		caption.theme_type_variation = &"Caption"
		caption.text = str(entry[0]).to_upper()
		box.add_child(caption)
		box.add_child(entry[1])
		row.add_child(box)
	card.add_row(row)
	card.add_row(_matches)
	return card


func setup(owner_shell: Control) -> void:
	shell = owner_shell
	for control in [_name, _map, _x, _y, _story, _opening_map, _opening_x, _opening_y, _open_story]: shell.name_node(control.name, control)
	_name.text_changed.connect(func(_value): changed())
	for spin in [_map, _x, _y, _opening_map, _opening_x, _opening_y]: spin.value_changed.connect(func(_value): changed())
	_story.value_changed.connect(_start_story_changed)
	_open_story.pressed.connect(func(): shell.guard(func(): await shell._choose_program("story", int(_story.value), 0); await shell._show_route(5)))


func list_stages(summary: Dictionary) -> void:
	var rows: Array = []
	var counts := [0, 0]
	for row in summary.get("stages", []):
		var used: bool = row.active
		counts[0 if used else 1] += 1
		if _scope == "used" and not used or _scope == "unused" and used: continue
		var where := "Map %d · %d, %d" % [int(row.map), int(row.x), int(row.y)]
		rows.append({"id": int(row.id), "cells": ["%02d" % int(row.id), str(row.name) if used else "Unused", where if used else ""]})
	list.set_rows(rows)
	list.set_count(summary.get("stages", []).size())
	list.set_scopes([{"id": "all", "label": "All", "count": counts[0] + counts[1]}, {"id": "used", "label": "In use", "count": counts[0]}, {"id": "unused", "label": "Unused", "count": counts[1]}])


func select_stage(index: int) -> void:
	stage_id = index
	refresh()
	await show_story()


## Shows the selected stage, with any unapplied edits over its saved values.
func refresh() -> void:
	var summary: Dictionary = shell.summary
	if summary.get("stages", []).is_empty(): return
	stage_id = mini(stage_id, summary.stages.size() - 1)
	var row: Dictionary = summary.stages[stage_id]
	shell._loading = true
	list.select(stage_id)
	var name_draft: Dictionary = shell.drafts.get("stage_name:%d" % stage_id, {})
	var start_draft: Dictionary = shell.drafts.get("stage_start:%d" % stage_id, row)
	_name.text = name_draft.get("name", row.name)
	_map.value = start_draft.get("map", row.get("map", 0))
	_x.value = start_draft.get("x", row.get("x", 0))
	_y.value = start_draft.get("y", row.get("y", 0))
	var story := int(shell.drafts.get("stage_script:%d" % stage_id, {}).get("story", row.start_script))
	_story.value = story
	var opening: Variant = shell.drafts.get("opening", summary.get("opening", {}))
	if opening is Dictionary:
		_opening_map.value = opening.get("map", 0)
		_opening_x.value = opening.get("x", 0)
		_opening_y.value = opening.get("y", 0)
	shell._loading = false
	header.title.text = "Stage %d · %s" % [stage_id, str(_name.text)] if row.active else "Stage %d · unused" % stage_id
	header.sub.text = "Data Mission · record %d · arrives on Map %d at %d, %d · runs Story %d" % [stage_id, int(_map.value), int(_x.value), int(_y.value), story]
	_name_count.text = "%d / 255" % _name.text.to_utf8_buffer().size()
	_draft.text = "Unapplied edits · Apply edits to validate" if not shell.drafts.is_empty() else "No unapplied edits"
	_grid.queue_redraw()
	_show_opening_match(summary)


func _show_opening_match(summary: Dictionary) -> void:
	var first: Dictionary = summary.stages[0]
	var same := int(_opening_map.value) == int(first.map) and int(_opening_x.value) == int(first.x) and int(_opening_y.value) == int(first.y)
	_matches.state = "good" if same else "warn"
	_matches.text = "Matches stage 0 · %s · Map %d · %d, %d" % [str(first.name), int(first.map), int(first.x), int(first.y)] if same else "Differs from stage 0 · Map %d · %d, %d" % [int(first.map), int(first.x), int(first.y)]


## The eight steps of the start story, read from the program table.
func show_story() -> void:
	var story := int(_story.value)
	for child in _story_steps.get_children(): _story_steps.remove_child(child); child.queue_free()
	_story_note.text = "The stage's story record · 0 runs nothing" if story == 0 else "The stage's story record"
	if story == 0 or shell.bridge.busy: return
	var response: Dictionary = await shell.request_backend({"op": "program", "family": "story", "id": story, "branch": 0})
	if not response.get("ok", false): return
	for step in response.result.steps:
		if int(step.opcode) == 0: continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var slot := Label.new()
		slot.theme_type_variation = &"MonoDim"
		slot.text = str(int(step.slot) + 1)
		row.add_child(slot)
		var code := Label.new()
		code.theme_type_variation = &"MonoDim"
		code.text = str(int(step.opcode))
		code.custom_minimum_size.x = 30
		row.add_child(code)
		var name := Label.new()
		name.theme_type_variation = &"Strong"
		name.text = Capability.name_of(int(step.opcode), step.authorable)
		name.custom_minimum_size.x = 150
		name.clip_text = true
		row.add_child(name)
		var sub := Label.new()
		sub.theme_type_variation = &"Dim"
		sub.text = Capability.subtitle(int(step.opcode), int(step.operand), step.authorable)
		row.add_child(sub)
		_story_steps.add_child(row)


## Drafts the name, arrival cell and header opening that differ from the
## saved values.
func changed() -> void:
	var summary: Dictionary = shell.summary
	if shell._loading or summary.is_empty() or summary.get("stages", []).is_empty(): return
	var drafts: Dictionary = shell.drafts
	var row: Dictionary = summary.stages[stage_id]
	var name: String = _name.text
	var nk := "stage_name:%d" % stage_id
	if name == row.name: drafts.erase(nk)
	else: drafts[nk] = {"kind": "stage_name", "id": stage_id, "name": name}
	var start := {"kind": "stage_start", "id": stage_id, "map": int(_map.value), "x": int(_x.value), "y": int(_y.value)}
	var sk := "stage_start:%d" % stage_id
	if start.map == row.map and start.x == row.x and start.y == row.y: drafts.erase(sk)
	else: drafts[sk] = start
	var opening := {"kind": "opening", "map": int(_opening_map.value), "x": int(_opening_x.value), "y": int(_opening_y.value)}
	var old: Variant = summary.get("opening", {})
	if old is Dictionary and opening.map == old.get("map") and opening.x == old.get("x") and opening.y == old.get("y"): drafts.erase("opening")
	else: drafts.opening = opening
	_name_count.text = "%d / 255" % name.to_utf8_buffer().size()
	_draft.text = "Unapplied edits · Apply edits to validate" if not drafts.is_empty() else "No unapplied edits"
	_grid.queue_redraw()
	_show_opening_match(summary)
	if not drafts.is_empty(): shell._invalidate_receipt()
	shell._update_buttons()


func _start_story_changed(value: float) -> void:
	if shell._loading or shell.summary.is_empty(): return
	show_story()
	var key := "stage_script:%d" % stage_id
	if int(value) == int(shell.summary.stages[stage_id].start_script): shell.drafts.erase(key)
	else: shell.drafts[key] = {"kind": "stage_script", "id": stage_id, "story": int(value)}
	shell._invalidate_receipt()
	shell._update_buttons()


## Drafts a new name for a stage, as the field does when it changes.
func draft_name(id: int, name: String) -> void:
	var row: Dictionary = shell.summary.stages[id]
	var key := "stage_name:%d" % id
	if name == row.name: shell.drafts.erase(key)
	else: shell.drafts[key] = {"kind": "stage_name", "id": id, "name": name}
	_drafted()


## Drafts where a stage starts.
func draft_start(id: int, map: int, x: int, y: int) -> void:
	var row: Dictionary = shell.summary.stages[id]
	var key := "stage_start:%d" % id
	if map == row.map and x == row.x and y == row.y: shell.drafts.erase(key)
	else: shell.drafts[key] = {"kind": "stage_start", "id": id, "map": map, "x": x, "y": y}
	_drafted()


func _drafted() -> void:
	refresh()
	if not shell.drafts.is_empty(): shell._invalidate_receipt()
	shell._update_buttons()


## Shows the stage's arrival cell on its map.
func reveal_on_map() -> void:
	var row: Dictionary = shell.summary.stages[stage_id]
	shell.maps.map_id = int(row.map)
	await shell._show_route(shell.ROUTES.find("Maps"))
	var cell := Vector2i(int(row.x), int(row.y))
	shell.maps.canvas.selected_cell = cell
	shell.maps.canvas.center_on(cell)
	shell.maps.cell_selected(cell, 0)


## Opens the map with the Start tool, to click the arrival cell.
func pick_on_map() -> void:
	var row: Dictionary = shell.summary.stages[stage_id]
	shell.maps.map_id = int(_map.value)
	shell.maps.canvas.active_stage = stage_id
	await shell._show_route(shell.ROUTES.find("Maps"))
	shell.maps.toolbar.select_tool("start")
	shell.maps.stage_chosen(stage_id)
