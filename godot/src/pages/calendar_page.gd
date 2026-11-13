extends HBoxContainer
## Calendar: the entries the game checks each time a day turns over. An entry runs a story on its day and comes due
## again after its interval, when its chance, its item, its mission flag and its place allow. Every change is a draft
## that waits for Apply.
const Card = preload("res://src/widgets/card.gd")
const PageHeader = preload("res://src/widgets/page_header.gd")
const RecordList = preload("res://src/widgets/record_list.gd")
const ChooseCellDialog = preload("res://src/dialogs/choose_cell_dialog.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

## How an entry that is switched off is written, as the bundled scenario writes its own.
const UNUSED := {"day": -1, "interval": 0, "chance": -1, "story": 0, "map": -1, "region": -1, "x": -1, "y": -1, "item": -1, "flag": -1, "place": -1}
const FIELDS := ["day", "interval", "chance", "story", "map", "region", "x", "y", "item", "flag", "place"]
const REACHED := 151

var shell: Control
var slot := 0
var list := RecordList.new()
var header := PageHeader.new()
var day := SpinBox.new()
var interval := SpinBox.new()
var chance := SpinBox.new()
var story := SpinBox.new()
var item := SpinBox.new()
var flag := SpinBox.new()
var column := SpinBox.new()
var row := SpinBox.new()
var item_check := CheckBox.new()
var flag_check := CheckBox.new()
var cell_check := CheckBox.new()
var place := OptionButton.new()
var map := OptionButton.new()
var region := OptionButton.new()
var _story_note := Label.new()
var _summary := VBoxContainer.new()
var _order := VBoxContainer.new()
var _where := VBoxContainer.new()
var _unuse: Button
var _cell_dialog := ChooseCellDialog.new()
var _saved: Array = []
var _ends_at: Variant = null
var _entry: Dictionary = {}
var _regions: Array = []
var _loading := false


func _init() -> void:
	list.title = "Calendar"
	list.filter_placeholder = "Filter entries"
	list.custom_minimum_size.x = 270
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.can_add = true
	list.set_columns([{"title": "#", "width": 44, "mono": true}, {"title": "Entry", "width": 0}])
	list.row_selected.connect(func(id): if id != null and not _loading: shell.guard(show_entry.bind(int(id))))
	list.add_requested.connect(add_entry)
	add_child(list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 10)
	scroll.add_child(centre)
	header.mark(Tokens.FAMILY.world)
	_unuse = header.add_button("Make unused")
	_unuse.tooltip_text = "Writes the entry the way the bundled scenario writes one that never comes due"
	_unuse.pressed.connect(_make_unused)
	centre.add_child(header)
	centre.add_child(_when_card())
	centre.add_child(_runs_card())
	centre.add_child(_only_if_card())
	centre.add_child(_where_card())
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 270
	side.add_theme_constant_override("separation", 10)
	add_child(side)
	var summary := Card.new()
	summary.title = "Eligibility"
	_summary.add_theme_constant_override("separation", 6)
	summary.add_row(_summary)
	side.add_child(summary)
	var order := Card.new()
	order.title = "Scan order"
	_order.add_theme_constant_override("separation", 8)
	order.add_row(_order)
	side.add_child(order)
	_cell_dialog.cell_chosen.connect(func(map_id, cell): _cell_picked(map_id, cell))
	_cell_dialog.none_chosen.connect(func(): cell_check.button_pressed = false)


func setup(owner_shell: Control) -> void:
	shell = owner_shell
	_cell_dialog.setup(shell)
	_cell_dialog.name = "ChooseCellDialog"
	if _cell_dialog.get_parent() == null: shell.add_child(_cell_dialog)


func _field(label_text: String, spin: SpinBox, low: int, high: int, width := 100) -> VBoxContainer:
	var box := VBoxContainer.new()
	var caption := Label.new()
	caption.theme_type_variation = &"Dim"
	caption.text = label_text
	box.add_child(caption)
	spin.min_value = low
	spin.max_value = high
	spin.rounded = true
	spin.custom_minimum_size.x = width
	spin.value_changed.connect(func(_value): if not _loading: _read_fields())
	box.add_child(spin)
	return box


func _note(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"Muted"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	return label


func _when_card() -> Card:
	var card := Card.new()
	card.title = "When"
	var line := HFlowContainer.new()
	line.add_theme_constant_override("h_separation", 14)
	line.add_child(_field("Day", day, -32768, 32767))
	line.add_child(_field("Repeat every (days)", interval, -32768, 32767, 130))
	line.add_child(_field("Chance (%)", chance, -32768, 32767))
	card.add_row(line)
	card.add_row(_note("A draw from 1 to 100 must not be above the chance: 100 always runs, 0 or less never does. Day 0 ends the calendar; a day that never arrives, such as -1, switches the entry off."))
	return card


func _runs_card() -> Card:
	var card := Card.new()
	card.title = "Runs"
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.add_child(_field("Story", story, 0, 32767, 110))
	_story_note.theme_type_variation = &"Dim"
	_story_note.size_flags_vertical = Control.SIZE_SHRINK_END
	line.add_child(_story_note)
	card.add_row(line)
	return card


func _only_if_card() -> Card:
	var card := Card.new()
	card.title = "Only if"
	var carries := HBoxContainer.new()
	carries.add_theme_constant_override("separation", 10)
	item_check.text = "A warrior carries"
	item_check.toggled.connect(func(_on): if not _loading: _read_fields())
	carries.add_child(item_check)
	item.min_value = 1
	item.max_value = 999
	item.rounded = true
	item.custom_minimum_size.x = 100
	item.value_changed.connect(func(_value): if not _loading: _read_fields())
	carries.add_child(item)
	shell_attach_later(carries, item, "item")
	card.add_row(carries)
	var flags := HBoxContainer.new()
	flags.add_theme_constant_override("separation", 10)
	flag_check.text = "Mission flag is set"
	flag_check.toggled.connect(func(_on): if not _loading: _read_fields())
	flags.add_child(flag_check)
	flag.min_value = 0
	flag.max_value = 127
	flag.rounded = true
	flag.custom_minimum_size.x = 90
	flag.value_changed.connect(func(_value): if not _loading: _read_fields())
	flags.add_child(flag)
	var range_note := Label.new()
	range_note.theme_type_variation = &"Dim"
	range_note.text = "flags 0 to 127"
	flags.add_child(range_note)
	card.add_row(flags)
	return card


## The item's icon and name follow its number once the shell is there to read them.
func shell_attach_later(line: HBoxContainer, spin: SpinBox, kind: String) -> void:
	_pending_attach.append([line, spin, kind])


var _pending_attach: Array = []


func _where_card() -> Card:
	var card := Card.new()
	card.title = "Where"
	place.fit_to_longest_item = false
	place.add_item("Anywhere")
	place.add_item("At a place")
	place.item_selected.connect(func(_index): if not _loading: _read_fields())
	card.add_row(place)
	_where.add_theme_constant_override("separation", 10)
	var line := HFlowContainer.new()
	line.add_theme_constant_override("h_separation", 14)
	var map_box := VBoxContainer.new()
	var map_caption := Label.new()
	map_caption.theme_type_variation = &"Dim"
	map_caption.text = "Map"
	map_box.add_child(map_caption)
	map.custom_minimum_size.x = 130
	map.fit_to_longest_item = false
	map.item_selected.connect(func(_index): if not _loading: _map_changed())
	map_box.add_child(map)
	line.add_child(map_box)
	var region_box := VBoxContainer.new()
	var region_caption := Label.new()
	region_caption.theme_type_variation = &"Dim"
	region_caption.text = "Region"
	region_box.add_child(region_caption)
	region.custom_minimum_size.x = 170
	region.fit_to_longest_item = false
	region.clip_text = true
	region.item_selected.connect(func(_index): if not _loading: _read_fields())
	region_box.add_child(region)
	line.add_child(region_box)
	_where.add_child(line)
	var cells := HFlowContainer.new()
	cells.add_theme_constant_override("h_separation", 14)
	cell_check.text = "Standing on a cell"
	cell_check.toggled.connect(func(_on): if not _loading: _read_fields())
	cells.add_child(cell_check)
	cells.add_child(_field("Column", column, 0, 89, 80))
	cells.add_child(_field("Row", row, 0, 89, 80))
	var pick := Button.new()
	pick.text = "Pick on map…"
	pick.theme_type_variation = &"GhostButton"
	pick.size_flags_vertical = Control.SIZE_SHRINK_END
	pick.pressed.connect(func(): _cell_dialog.show_for(_entry_map(), Vector2i(int(column.value), int(row.value)) if cell_check.button_pressed else Vector2i(-1, -1)))
	cells.add_child(pick)
	_where.add_child(cells)
	card.add_row(_where)
	card.add_row(_note("Tested once, at the turn of the entry's day: the party must be on the map, inside the region and on the cell (the one it stands on, or is moving onto). An entry that is not there is skipped and not tried again."))
	return card


func _entry_map() -> int:
	return maxi(0, int(map.get_item_id(map.selected))) if map.selected >= 0 else 0


func entry_count() -> int:
	return _saved.size()


func refresh() -> void:
	if shell.summary.is_empty(): return
	await shell.ensure_item_names()
	for pending in _pending_attach: shell.references.attach(pending[0], pending[1], pending[2])
	_pending_attach.clear()
	var response: Dictionary = await shell.request_backend({"op": "calendar"})
	if not response.get("ok", false): return
	_saved = response.result.entries
	_ends_at = response.result.get("ends_at")
	_fill_maps()
	_rebuild_list()
	slot = clampi(slot, 0, maxi(0, _all().size() - 1))
	await show_entry(slot)


func _fill_maps() -> void:
	map.clear()
	for id in range(int(shell.summary.get("maps", 0))): map.add_item("Map %d" % id, id)


## The entries as saved with the unapplied edits of them put over them.
func _all() -> Array:
	var entries: Array = []
	for entry in _saved: entries.append(_with_draft(entry))
	var next := _saved.size()
	while _drafts().has(next):
		entries.append(_with_draft({"slot": next}))
		next += 1
	return entries


func _drafts() -> Dictionary:
	var found: Dictionary = {}
	for draft in shell.drafts.values():
		if str(draft.get("kind", "")) == "calendar_entry": found[int(draft.slot)] = draft
	return found


func _with_draft(entry: Dictionary) -> Dictionary:
	var draft: Dictionary = _drafts().get(int(entry.slot), {})
	var merged := {"slot": int(entry.slot)}
	for name in FIELDS: merged[name] = int(draft.get(name, entry.get(name, UNUSED[name])))
	merged["reached"] = entry.get("reached", true)
	return merged


func _rebuild_list() -> void:
	_loading = true
	var rows: Array = []
	for entry in _all(): rows.append({"id": int(entry.slot), "cells": [str(entry.slot), _describe(entry)], "dirty": _drafts().has(int(entry.slot))})
	list.set_rows(rows)
	list.set_count(rows.size())
	_loading = false


func _describe(entry: Dictionary) -> String:
	var when := "Never due"
	if int(entry.day) == 0: when = "Ends the calendar"
	elif int(entry.day) > 0:
		when = "Day %d" % int(entry.day)
		if int(entry.interval) != 0: when += " · every %d days" % int(entry.interval)
		when += " · story %d" % int(entry.story)
	return when


func show_entry(id: int) -> void:
	slot = id
	var all := _all()
	if all.is_empty(): _entry = {}; return
	_entry = all[clampi(id, 0, all.size() - 1)]
	_loading = true
	list.select(id)
	day.value = int(_entry.day)
	interval.value = int(_entry.interval)
	chance.value = int(_entry.chance)
	story.value = int(_entry.story)
	item_check.button_pressed = int(_entry.item) > 0
	if int(_entry.item) > 0: item.value = int(_entry.item)
	flag_check.button_pressed = int(_entry.flag) >= 0
	if int(_entry.flag) >= 0: flag.value = int(_entry.flag)
	place.clear()
	place.add_item("Anywhere")
	place.add_item("At a place")
	if int(_entry.place) > 1: place.add_item("Skipped: place test %d" % int(_entry.place))
	place.select(1 if int(_entry.place) == 1 else (2 if int(_entry.place) > 1 else 0))
	var map_index := map.get_item_index(int(_entry.map)) if int(_entry.map) >= 0 else 0
	map.select(maxi(0, map_index))
	cell_check.button_pressed = int(_entry.x) >= 0
	if int(_entry.x) >= 0:
		column.value = int(_entry.x)
		row.value = clampi(int(_entry.y), 0, 89)
	_loading = false
	await _load_regions(int(_entry.region))
	_refresh_text()


## The regions of the entry's map, for the Region choice.
func _load_regions(wanted: int) -> void:
	_regions = []
	if map.item_count > 0:
		var response: Dictionary = await shell.request_backend({"op": "map", "id": _entry_map()})
		if response.get("ok", false): _regions = response.result.get("regions", [])
	_loading = true
	region.clear()
	# An item id of -1 would mean "the next number", so a region is its slot plus one and "any region" is zero.
	region.add_item("Any region", 0)
	for entry in _regions:
		var empty: bool = int(entry.first_y) == 0 and int(entry.first_x) == 0 and int(entry.last_y) == 0 and int(entry.last_x) == 0
		if empty and int(entry.slot) != wanted: continue
		region.add_item("R%d · rows %d to %d, columns %d to %d" % [int(entry.slot), int(entry.first_y), int(entry.last_y), int(entry.first_x), int(entry.last_x)] if not empty else "R%d · empty" % int(entry.slot), int(entry.slot) + 1)
	var at := region.get_item_index(wanted + 1) if wanted >= 0 else 0
	region.select(maxi(0, at))
	_loading = false


func _map_changed() -> void:
	await _load_regions(-1)
	_read_fields()


## The fields as the form holds them now.
func _form() -> Dictionary:
	var at_place := place.selected == 1
	var skipped := place.selected == 2
	return {
		"slot": slot,
		"day": int(day.value), "interval": int(interval.value), "chance": int(chance.value), "story": int(story.value),
		"map": _entry_map() if at_place else int(_entry.get("map", -1)),
		"region": int(region.get_item_id(region.selected)) - 1 if at_place and region.selected >= 0 else (int(_entry.get("region", -1)) if skipped else -1),
		"x": int(column.value) if at_place and cell_check.button_pressed else -1,
		"y": int(row.value) if at_place and cell_check.button_pressed else -1,
		"item": int(item.value) if item_check.button_pressed else -1,
		"flag": int(flag.value) if flag_check.button_pressed else -1,
		"place": 1 if at_place else (int(_entry.get("place", -1)) if skipped else -1),
	}


func _read_fields() -> void:
	var form := _form()
	_entry = form.duplicate()
	_entry["reached"] = true
	_write_draft(form)
	_where.visible = place.selected == 1
	_refresh_text()


func _write_draft(form: Dictionary) -> void:
	var key := "calendar_entry:%d" % slot
	var saved := {}
	for entry in _saved:
		if int(entry.slot) == slot: saved = entry
	var same := not saved.is_empty()
	if same:
		for name in FIELDS:
			if int(saved[name]) != int(form[name]): same = false
	if same: shell.drafts.erase(key)
	else:
		var draft := {"kind": "calendar_entry"}
		draft.merge(form)
		shell.drafts[key] = draft
	shell._invalidate_receipt()
	shell._update_buttons()
	_rebuild_list()
	list.select(slot)


func _cell_picked(map_id: int, cell: Vector2i) -> void:
	_loading = true
	map.select(maxi(0, map.get_item_index(map_id)))
	column.value = cell.x
	row.value = cell.y
	cell_check.button_pressed = true
	_loading = false
	_read_fields()


## Switches the entry off the way the bundled scenario does.
func _make_unused() -> void:
	var form := UNUSED.duplicate()
	form["slot"] = slot
	_write_draft(form)
	await show_entry(slot)


## A new entry after the last, switched off until it is given a day.
func add_entry() -> void:
	var next := _all().size()
	if next >= REACHED:
		shell.status("The game reads calendar entries 0 to 150 and no more", "warn")
		return
	slot = next
	var form := UNUSED.duplicate()
	form["slot"] = next
	var draft := {"kind": "calendar_entry"}
	draft.merge(form)
	shell.drafts["calendar_entry:%d" % next] = draft
	shell._invalidate_receipt()
	shell._update_buttons()
	_rebuild_list()
	await show_entry(next)


func _refresh_text() -> void:
	_where.visible = place.selected == 1
	header.title.text = "Entry %d" % slot
	header.sub.text = "Data TD3 · record %d" % slot
	header.show_badges([["unapplied", &"BadgeWarn"]] if _drafts().has(slot) else [])
	var stories := 0
	for table in shell.summary.get("tables", []):
		if table.file == "Data ED3": stories = int(table.complete_records)
	_story_note.text = "Story %d" % int(_entry.story) if int(_entry.story) < stories else "Story %d is not in the scenario" % int(_entry.story)
	for child in _summary.get_children(): _summary.remove_child(child); child.queue_free()
	for line in _lines():
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.theme_type_variation = &"Dim" if line.begins_with("On day") else &""
		label.text = line
		_summary.add_child(label)
	for child in _order.get_children(): _order.remove_child(child); child.queue_free()
	_order.add_child(_note("Entries are read from 0 to 150, and the scan ends at an entry with day 0. A due entry that fails its chance, item or flag ends the day's scan, so the entries after it are not read. An entry at the wrong place is passed over."))
	var reason := _unreached()
	if not reason.is_empty():
		var warn := Label.new()
		warn.theme_type_variation = &"BadgeWarn"
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.text = reason
		_order.add_child(warn)


func _unreached() -> String:
	if slot >= REACHED: return "The game reads no entry past 150."
	if _ends_at != null and slot > int(_ends_at) and int(_entry.day) != 0: return "Entry %d has day 0, which ends the calendar before this entry." % int(_ends_at)
	var all := _all()
	for index in range(mini(slot, all.size())):
		if int(all[index].day) == 0: return "Entry %d has day 0, which ends the calendar before this entry." % index
	return ""


## What the game does with the entry on its day, in the order it does it.
func _lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var d := int(_entry.day)
	if d == 0: return PackedStringArray(["Day 0 ends the calendar: the game reads no entry after this one."])
	if d < 0: return PackedStringArray(["Never due: the day counter does not reach %d." % d])
	lines.append("On day %d, at the turn of the day, the game:" % d)
	var c := int(_entry.chance)
	if c >= 100: lines.append("1  Draws 1 to 100: always passes")
	elif c <= 0: lines.append("1  Draws 1 to 100: never passes (the chance is %d)" % c)
	else: lines.append("1  Draws 1 to 100: passes on %d or less" % c)
	var step := 2
	if int(_entry.item) > 0:
		var name: String = shell.item_name(int(_entry.item))
		lines.append("%d  Needs a warrior carrying %s" % [step, name if not name.is_empty() else "item %d" % int(_entry.item)])
		step += 1
	if int(_entry.flag) >= 0:
		lines.append("%d  Needs mission flag %d set" % [step, int(_entry.flag)])
		step += 1
	var p := int(_entry.place)
	if p == 1:
		var text := "Needs the party on Map %d" % int(_entry.map)
		if int(_entry.region) >= 0: text += ", inside R%d" % int(_entry.region)
		if int(_entry.x) >= 0: text += ", standing on (%d, %d)" % [int(_entry.x), int(_entry.y)]
		lines.append("%d  %s" % [step, text])
		step += 1
	elif p > 1:
		lines.append("%d  Skips the entry: a place test of %d is never met" % [step, p])
		return lines
	var next := (d + int(_entry.interval) + 32768) % 65536 - 32768
	lines.append("%d  Runs Story %d, then sets the entry's day to %d" % [step, int(_entry.story), next])
	return lines
