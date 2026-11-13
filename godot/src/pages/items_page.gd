extends HBoxContainer
## Items: the scenario's own items, ids 800 and up. Each has a 150-byte
## definition and a description; every change is a draft that waits for Apply.
const Card = preload("res://src/widgets/card.gd")
const PageHeader = preload("res://src/widgets/page_header.gd")
const RecordList = preload("res://src/widgets/record_list.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

const FIRST_ID := 800
const GROUPS := ["Identity", "Sounds", "Attack", "Ammunition", "Defence", "Charge", "Effect", "Worn", "New copy", "Who may use it"]
const LIMIT := 255
## The longest item name the game and the scenario hold; a longer one is allowed and advised against.
const USUAL_NAME := 30

var shell: Control
var index := 0
var list := RecordList.new()
var header := PageHeader.new()
var description := TextEdit.new()
var name_field := LineEdit.new()
var spins: Dictionary = {}
var _cards := VBoxContainer.new()
var _bytes := Label.new()
var _name_note := Label.new()
var _used := VBoxContainer.new()
var _view: Dictionary = {}
var _loading := false


func _init() -> void:
	list.title = "Items"
	list.filter_placeholder = "Filter by id, name or description"
	list.custom_minimum_size.x = 300
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.set_columns([{"title": "ID", "width": 56, "mono": true}, {"title": "Name", "width": 170}, {"title": "Description", "width": 0}])
	list.row_selected.connect(func(row): if row != null and not _loading: shell.guard(show_item.bind(int(row))))
	add_child(list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 10)
	scroll.add_child(centre)
	header.mark(Tokens.FAMILY.reward)
	header.add_button("Callers").pressed.connect(func(): shell.find_uses("item", FIRST_ID + index))
	centre.add_child(header)
	var naming := Card.new()
	naming.title = "Name"
	_name_note.theme_type_variation = &"MonoDim"
	naming.right.add_child(_name_note)
	name_field.placeholder_text = "The item's name, as the game lists it"
	name_field.text_changed.connect(func(_text): _name_changed())
	naming.add_row(name_field)
	centre.add_child(naming)
	var words := Card.new()
	words.title = "Description"
	_bytes.theme_type_variation = &"MonoDim"
	words.right.add_child(_bytes)
	description.custom_minimum_size.y = 90
	description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	description.text_changed.connect(_description_changed)
	words.add_row(description)
	centre.add_child(words)
	_cards.add_theme_constant_override("separation", 10)
	centre.add_child(_cards)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 260
	side.add_theme_constant_override("separation", 10)
	add_child(side)
	var facts := Card.new()
	facts.title = "Record"
	for line in ["Data NI · 150 bytes an item", "Data NI Des · 256 bytes a description", "The game reads the first 200 items, ids 800 to 999", "Stock items below 800 come from the installation and are not edited"]:
		var text := Label.new()
		text.theme_type_variation = &"Muted"
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.text = line
		facts.add_row(text)
	side.add_child(facts)
	var used := Card.new()
	used.title = "Used by"
	_used.add_theme_constant_override("separation", 6)
	used.add_row(_used)
	side.add_child(used)


func setup(owner_shell: Control) -> void:
	shell = owner_shell


func refresh() -> void:
	if shell.summary.is_empty(): return
	await shell.ensure_item_names()
	await shell.references.ensure()
	var response: Dictionary = await shell.request_backend({"op": "items"})
	if not response.get("ok", false): return
	_loading = true
	var rows: Array = []
	for item in response.result: rows.append({"id": int(item.index), "cells": [str(int(item.id)), shell.item_name(int(item.id)), str(item.text)], "dirty": _has_draft(int(item.index))})
	list.set_rows(rows)
	list.set_count(rows.size())
	_loading = false
	index = clampi(index, 0, maxi(0, rows.size() - 1))
	await show_item(index)


func _has_draft(item: int) -> bool:
	for draft in shell.drafts.values():
		if str(draft.get("kind", "")).begins_with("item_") and int(draft.index) == item: return true
	return false


func show_item(item: int) -> void:
	index = item
	await shell.ensure_item_names()
	var response: Dictionary = await shell.request_backend({"op": "item", "id": item})
	if not response.get("ok", false): return
	_view = response.result
	_loading = true
	list.select(item)
	description.text = str(shell.drafts.get("item_description:%d" % item, {}).get("text", _view.description))
	name_field.text = str(shell.drafts.get("item_name:%d" % item, {}).get("name", shell.item_name(FIRST_ID + item)))
	_name_count()
	_loading = false
	_bytes.text = ""
	_description_bytes()
	_build_cards()
	var name: String = shell.item_name(FIRST_ID + item)
	header.title.text = "Item %d%s" % [FIRST_ID + item, " · " + name if not name.is_empty() else ""]
	header.sub.text = "Data NI · record %d · item id %d" % [item, FIRST_ID + item]
	_show_badges()
	await _show_used()


func _show_badges() -> void:
	header.show_badges([["provisional", &"BadgeDim"]] + ([["unapplied", &"BadgeWarn"]] if _has_draft(index) else []))


func _build_cards() -> void:
	spins.clear()
	for child in _cards.get_children(): _cards.remove_child(child); child.queue_free()
	var by_group: Dictionary = {}
	for row in _view.fields:
		if not by_group.has(row.group): by_group[row.group] = []
		by_group[row.group].append(row)
	for group in GROUPS:
		if not by_group.has(group): continue
		var card := Card.new()
		card.title = group
		_cards.add_child(card)
		for row in by_group[group]: card.add_row(_row(row))


## The item fields that hold a number the game gives a name or an icon.
const REFERENCE_KINDS := {"icon": "icon", "class": "item_class", "caliber": "caliber", "reserve_kind": "caliber", "spell": "spell", "required_race": "race", "required_mos": "caste", "sound": "sound", "impact_sound": "sound"}


func _row(row: Dictionary) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.theme_type_variation = &"Dim"
	label.text = str(row.label)
	label.custom_minimum_size.x = 260
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = mini(int(row.minimum), int(row.value))
	spin.max_value = maxi(int(row.maximum), int(row.value))
	var shown := int(row.value)
	var key := "item_field:%d:%s:%d" % [index, row.field, int(row.index)]
	if shell.drafts.has(key): shown = int(shell.drafts[key].value)
	spin.set_value_no_signal(shown)
	spin.editable = bool(row.authorable)
	spin.custom_minimum_size.x = 130
	spin.value_changed.connect(func(value): field_edit(row, int(value)))
	line.add_child(spin)
	if REFERENCE_KINDS.has(str(row.field)): shell.references.attach(line, spin, REFERENCE_KINDS[str(row.field)])
	if not bool(row.authorable):
		var kept := Label.new()
		kept.theme_type_variation = &"Dim"
		kept.text = "kept as recorded"
		line.add_child(kept)
	spins["%s:%d" % [row.field, int(row.index)]] = spin
	return line


## A field's new value, as a draft, or none when it is as saved.
func field_edit(row: Dictionary, value: int) -> void:
	if _loading: return
	var key := "item_field:%d:%s:%d" % [index, row.field, int(row.index)]
	if value == int(row.value): shell.drafts.erase(key)
	else: shell.drafts[key] = {"kind": "item_field", "index": index, "field": row.field, "slot": int(row.index), "value": value}
	_changed()


func _name_count() -> void:
	var length := name_field.text.length()
	_name_note.text = "%d characters" % length if length <= USUAL_NAME else "%d characters · the longest in the game is %d" % [length, USUAL_NAME]


## The name as a draft, or none when it is as saved.
func _name_changed() -> void:
	if _loading: return
	_name_count()
	var key := "item_name:%d" % index
	if name_field.text == shell.item_name(FIRST_ID + index): shell.drafts.erase(key)
	else: shell.drafts[key] = {"kind": "item_name", "index": index, "name": name_field.text}
	_changed()


func _description_bytes() -> void:
	var length := description.text.to_utf8_buffer().size()
	_bytes.text = "%d / %d bytes" % [length, LIMIT]


func _description_changed() -> void:
	if _loading: return
	_description_bytes()
	var key := "item_description:%d" % index
	if description.text == str(_view.description): shell.drafts.erase(key)
	else: shell.drafts[key] = {"kind": "item_description", "index": index, "text": description.text}
	_changed()


func _changed() -> void:
	shell._invalidate_receipt()
	shell._update_buttons()
	_show_badges()


## The shops, monsters and typed encounters that name the item.
func _show_used() -> void:
	for child in _used.get_children(): _used.remove_child(child); child.queue_free()
	var response: Dictionary = await shell.request_backend({"op": "uses", "kind": "item", "id": FIRST_ID + index})
	if not response.get("ok", false): return
	var uses: Dictionary = response.result
	if int(uses.total) == 0:
		var none := Label.new()
		none.theme_type_variation = &"Dim"
		none.text = "No shop stocks it, no monster carries it and no typed encounter asks for it."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_used.add_child(none)
		return
	for row in uses.rows.slice(0, 8):
		var link := Button.new()
		link.theme_type_variation = &"GhostButton"
		link.alignment = HORIZONTAL_ALIGNMENT_LEFT
		link.text = "%s %d · %s" % [str(row.table).trim_suffix("s"), int(row.id), str(row.name)]
		link.pressed.connect(func(): shell.guard(shell.navigator.go.bind(str(row.kind), int(row.id))))
		_used.add_child(link)
	var all := Button.new()
	all.text = "Find all %d uses" % int(uses.total)
	all.theme_type_variation = &"GhostButton"
	all.pressed.connect(func(): shell.find_uses("item", FIRST_ID + index))
	_used.add_child(all)
