extends "res://src/widgets/modal_overlay.gd"
## Choose battle and Choose reward: the rows of a table, filtered, with the one
## in hand marked and a preview of the chosen row. Choosing changes only the
## field's operand; the record stays in its table.
signal record_chosen(kind: String, id: int)
const KbdButton = preload("res://src/widgets/kbd_button.gd")
const KeyValueRow = preload("res://src/widgets/key_value_row.gd")
const RecordList = preload("res://src/widgets/record_list.gd")

const KINDS := {
	"battle": {"title": "Choose battle", "noun": "Battle", "file": "Data BD"},
	"reward": {"title": "Choose reward", "noun": "Reward", "file": "Data TD"},
	"text": {"title": "Choose text", "noun": "Text", "file": "Scenario.rsrc"},
}

var shell: Control
var kind := "battle"
var list := RecordList.new()
var _current := 0
var _picked := 0
var _count := 0
var _title_label := Label.new()
var _facts := VBoxContainer.new()
var _use: KbdButton
var _preview_for := -1
var _on_chosen := Callable()


func _init() -> void:
	super()
	title = "Choose battle"
	panel_size = Vector2(620, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	body.add_child(column)
	list.filter_placeholder = "Filter by id…"
	list.custom_minimum_size = Vector2(560, 380)
	list.set_columns([{"title": "ID", "width": 60, "mono": true}, {"title": "Record", "width": 0}])
	list.row_selected.connect(func(id): if id != null: _pick(int(id)))
	list.row_activated.connect(func(id): if id != null: _picked = int(id); _commit())
	column.add_child(list)
	var detail := PanelContainer.new()
	detail.theme_type_variation = &"Detail"
	column.add_child(detail)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	detail.add_child(stack)
	_title_label.theme_type_variation = &"Heading"
	stack.add_child(_title_label)
	_facts.add_theme_constant_override("separation", 4)
	stack.add_child(_facts)
	add_button("Cancel").pressed.connect(close)
	_use = KbdButton.new()
	_use.theme_type_variation = &"PrimaryButton"
	_use.hint = "Enter"
	_use.pressed.connect(_commit)
	add_footer_button(_use)


func setup(owner_shell: Control) -> void:
	shell = owner_shell


## Opens on the row of `current`, for the field described by `where`.
func show_for(record_kind: String, current: int, where: String, on_chosen := Callable()) -> void:
	kind = record_kind
	_on_chosen = on_chosen
	_current = current
	_picked = current
	title = KINDS[kind].title
	subtitle = where
	list.title = "%ss" % KINDS[kind].noun
	list.clear_filter()
	open()
	await _load()


func _load() -> void:
	var rows: Array = []
	if kind == "battle":
		var response: Dictionary = await shell.request_backend({"op": "combat_catalogue", "monsters": false, "offset": 0, "query": ""})
		if not response.get("ok", false): return
		_count = int(response.result.total)
		var start := 0
		while true:
			for row in response.result.rows: rows.append({"id": int(row.id), "cells": ["B%d" % int(row.id), str(row.name)]})
			start += 128
			if start >= _count: break
			response = await shell.request_backend({"op": "combat_catalogue", "monsters": false, "offset": start, "query": ""})
			if not response.get("ok", false): break
	elif kind == "text":
		var response: Dictionary = await shell.request_backend({"op": "scroll_texts"})
		if not response.get("ok", false): return
		for row in response.result.rows: rows.append({"id": int(row.id), "cells": [str(int(row.id)), str(row.first)]})
		_count = rows.size()
	else:
		var response: Dictionary = await shell.request_backend({"op": "authored_records"})
		if not response.get("ok", false): return
		for table in response.result.families:
			if table.family == "reward": _count = int(table.count)
		for index in range(_count): rows.append({"id": index, "cells": [str(index), "Reward %d" % index]})
	list.set_rows(rows)
	list.set_count(rows.size())
	if kind == "text":
		list.select(_current)
		await _pick(_current if rows.any(func(row): return int(row.id) == _current) else (int(rows[0].id) if not rows.is_empty() else 0))
		return
	if _current >= 0 and _current < rows.size(): list.select(_current)
	await _pick(clampi(_current, 0, maxi(0, rows.size() - 1)))


func _pick(id: int) -> void:
	_picked = id
	_title_label.text = "%s %d%s" % [KINDS[kind].noun, id, "  · current" if id == _current else ""]
	_use.text = "Use %s %d" % [KINDS[kind].noun.to_lower(), id]
	_preview_for = id
	var facts: Array = []
	if kind == "battle":
		var response: Dictionary = await shell.request_backend({"op": "combat_record", "monsters": false, "id": id})
		if _preview_for != id or not response.get("ok", false): return
		var names: Array = []
		for actor in response.result.actors:
			var name := str(actor.name)
			if name not in names: names.append(name)
		facts = [["Monsters", str(response.result.actors.size())], ["Squad start", "%d, %d" % [int(response.result.fields["Squad start X"]), int(response.result.fields["Squad start Y"])]], ["Roster", ", ".join(names)]]
	elif kind == "text":
		var response: Dictionary = await shell.request_backend({"op": "scroll_text", "id": id})
		if _preview_for != id or not response.get("ok", false): return
		var begins := ""
		for line in str(response.result.text).split("\n"):
			if not line.strip_edges().is_empty() and not line.strip_edges().begins_with("<<<"): begins = line.strip_edges().left(80); break
		facts = [["Length", "%d characters" % int(response.result.length)], ["Style runs", str(response.result.runs.size())], ["Shown by", "%d steps" % response.result.uses.size()], ["Begins", begins]]
	else:
		var response: Dictionary = await shell.request_backend({"op": "authored_record", "family": "reward", "id": id})
		if _preview_for != id or not response.get("ok", false): return
		facts = [["Experience", str(int(response.result.experience))], ["Credits", str(int(response.result.credits))]]
	for child in _facts.get_children(): _facts.remove_child(child); child.queue_free()
	for entry in facts:
		var row := KeyValueRow.new()
		row.key = entry[0]
		row.value = entry[1]
		row.mono = true
		_facts.add_child(row)


func _commit() -> void:
	close()
	record_chosen.emit(kind, _picked)
	if _on_chosen.is_valid(): _on_chosen.call(_picked)


func _unhandled_key_input(event: InputEvent) -> void:
	super(event)
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_commit()
		get_viewport().set_input_as_handled()
