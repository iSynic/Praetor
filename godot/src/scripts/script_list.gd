extends VBoxContainer
## The programs of one family: walking triggers, stories, choice encounters or
## typed encounters, with what each one is at a glance.
signal record_chosen(family: String, id: int)
const Capability = preload("res://src/scripts/capability.gd")
const RecordList = preload("res://src/widgets/record_list.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

const FAMILIES := [["walking", "Walking"], ["story", "Stories"], ["menu", "Choices"], ["typed", "Typed"]]

var shell: Control
var family := "walking"
var list := RecordList.new()
var scope := "map"
## The map the walking triggers are limited to when it is not the one open on the Maps page; -1 follows that map.
var picked_map := -1
var _tabs := ButtonGroup.new()
var _buttons: Dictionary = {}
var _foot := Label.new()
var _key := ""
var _stories: Array = []
var _records: Dictionary = {}
var _refreshing := false


func _init() -> void:
	add_theme_constant_override("separation", 8)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 4)
	add_child(strip)
	for entry in FAMILIES:
		var button := Button.new()
		button.theme_type_variation = &"Chip"
		button.toggle_mode = true
		button.button_group = _tabs
		button.text = entry[1]
		button.set_pressed_no_signal(entry[0] == family)
		button.pressed.connect(func(): show_family(entry[0]))
		strip.add_child(button)
		_buttons[entry[0]] = button
	list.filter_placeholder = "Filter by id, cell, step or message…"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.row_selected.connect(func(id): if id != null: record_chosen.emit(family, int(id)))
	list.scope_changed.connect(func(id):
		scope = str(id)
		picked_map = -1
		if scope.begins_with("pick:"):
			picked_map = int(scope.substr(5))
			scope = "map"
		refresh())
	add_child(list)
	_foot.theme_type_variation = &"Dim"
	_foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_foot)


func setup(owner_shell: Control) -> void:
	shell = owner_shell


## Forgets what was read, because another project or another set of edits is in.
func invalidate() -> void:
	_key = ""
	_stories.clear()
	_records.clear()


func show_family(name: String) -> void:
	family = name
	_buttons[name].set_pressed_no_signal(true)
	scope = "map"
	picked_map = -1
	refresh()


## Marks the open record without reporting a choice.
func select(name: String, id: int) -> void:
	if name != family:
		family = name
		_buttons[name].set_pressed_no_signal(true)
		scope = "map"
		picked_map = -1
		await refresh()
	list.select(id)


func _counts() -> Dictionary:
	var rows := {}
	for table in shell.summary.get("tables", []): rows[table.file] = int(table.complete_records)
	return rows


func refresh() -> void:
	if shell == null or shell.summary.is_empty() or _refreshing: return
	_refreshing = true
	var rows := _counts()
	var key := "%s:%d" % [str(shell.summary.get("path", "")), shell.bridge.revision]
	if key != _key:
		_key = key
		_stories.clear()
		_records.clear()
	var placed := 0
	for id in shell.maps.counts: placed += int(shell.maps.counts[id])
	_buttons.walking.text = "Walking %d" % placed if not shell.maps.counts.is_empty() else "Walking"
	_buttons.story.text = "Stories %d" % int(rows.get("Data ED3", 0))
	_buttons.menu.text = "Choices %d" % int(rows.get("Data ED", 0))
	_buttons.typed.text = "Typed %d" % int(rows.get("Data ED2", 0))
	match family:
		"walking": await _walking()
		"story": await _stories_rows(int(rows.get("Data ED3", 0)))
		_: await _encounters(int(rows.get("Data ED" if family == "menu" else "Data ED2", 0)))
	_refreshing = false


func _walking() -> void:
	var maps: Control = shell.maps
	var count := int(shell.summary.get("maps", 0))
	var all: Array = []
	var shown: int = picked_map if picked_map >= 0 else int(maps.map_id)
	for map in range(count):
		if scope == "map" and map != shown: continue
		var triggers: Array = await maps.triggers_of(map)
		for trigger in triggers:
			var name := "W%d" % int(trigger.slot) if scope == "map" else "M%d W%d" % [map, int(trigger.slot)]
			all.append({"id": int(trigger.id), "cells": [name, "%d, %d" % [int(trigger.x), int(trigger.y)], "%d%%" % int(trigger.chance), "shadowed" if trigger.get("shadowed", false) else ""]})
	list.title = "Walking triggers"
	list.set_columns([{"title": "ID", "width": 74, "mono": true}, {"title": "Cell", "width": 70, "mono": true}, {"title": "Chance", "width": 56, "mono": true, "right": true}, {"title": "", "width": 70, "mono": true, "right": true}])
	var picks: Array = []
	for map in range(count): picks.append({"id": "pick:%d" % map, "label": "Map %d" % map})
	list.set_scopes([{"id": "map", "label": "Map %d" % shown}, {"id": "all", "label": "All maps"}], picks, "Other map")
	list.press_scope(0 if scope == "map" else 1)
	list.set_rows(all)
	list.set_count(all.size())
	_foot.text = "%d placed on %s" % [all.size(), ("Map %d" % shown) if scope == "map" else "all maps"]


func _stories_rows(total: int) -> void:
	if _stories.is_empty() and total > 0:
		for offset in range(0, total, 128):
			var response: Dictionary = await shell.request_backend({"op": "stories", "offset": offset, "limit": 128})
			if response.get("ok", false): _stories.append_array(response.result.rows)
	var rows: Array = []
	for story in _stories:
		var steps: Array = story.actions.filter(func(action): return int(action.opcode) != 0)
		var first := ""
		if not steps.is_empty(): first = Capability.subtitle(int(steps[0].opcode), int(steps[0].operand), bool(steps[0].get("authorable", Capability.has_form(int(steps[0].opcode)))))
		rows.append({"id": int(story.id), "cells": ["S%d" % int(story.id), first, "%d/8" % steps.size()]})
	list.title = "Stories"
	list.set_columns([{"title": "ID", "width": 54, "mono": true}, {"title": "First step", "width": 0}, {"title": "Steps", "width": 44, "mono": true, "right": true}])
	list.set_scopes([])
	list.set_rows(rows)
	list.set_count(total)
	_foot.text = "%d stories · ED3" % total


func _encounters(total: int) -> void:
	var tag := "C" if family == "menu" else "T"
	var rows: Array = []
	for id in range(mini(total, 120)):
		var key := "%s:%d" % [family, id]
		if not _records.has(key):
			var response: Dictionary = await shell.request_backend({"op": "program", "family": family, "id": id, "branch": 0})
			_records[key] = response.result if response.get("ok", false) else {}
		var program: Dictionary = _records[key]
		var used := 0
		if not program.is_empty(): used = program.steps.filter(func(step): return int(step.opcode) != 0).size()
		rows.append({"id": id, "cells": ["%s%d" % [tag, id], str(program.get("label", "")) if family == "menu" else "", "%d/8" % used]})
	list.title = "Choice encounters" if family == "menu" else "Typed encounters"
	list.set_columns([{"title": "ID", "width": 40, "mono": true}, {"title": "First choice" if family == "menu" else "", "width": 0}, {"title": "Branch 0", "width": 60, "mono": true, "right": true}])
	list.set_scopes([])
	list.set_rows(rows)
	list.set_count(total)
	_foot.text = "%d %s encounters · %s" % [total, "choice" if family == "menu" else "typed", "ED" if family == "menu" else "ED2"]
