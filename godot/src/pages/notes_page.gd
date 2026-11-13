extends HBoxContainer
## Notes: the map notes of the Maps and Notes menu. A note shows a section of a map with marks, a picture, or a scrolling text; a
## story gives the party a note with code 29, and the menu then shows its second label. Every change is a draft that waits for Apply.
const Card = preload("res://src/widgets/card.gd")
const NotePreview = preload("res://src/widgets/note_preview.gd")
const PageHeader = preload("res://src/widgets/page_header.gd")
const RecordList = preload("res://src/widgets/record_list.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

const NOTES := 19
const DASHES := "--------------------"
const FIELDS := ["start_x", "start_y", "level", "picture", "icon_size", "show", "bottom", "right"]

var shell: Control
var note := 0
var list := RecordList.new()
var header := PageHeader.new()
var before := LineEdit.new()
var after := LineEdit.new()
var mode := OptionButton.new()
var map := OptionButton.new()
var start_x := SpinBox.new()
var start_y := SpinBox.new()
var icon_size := SpinBox.new()
var picture := SpinBox.new()
var bottom := SpinBox.new()
var right := SpinBox.new()
var show_text := SpinBox.new()
var words := TextEdit.new()
var preview := NotePreview.new()
var _marks: Array = []
var _section := VBoxContainer.new()
var _picture_box := VBoxContainer.new()
var _text_box := VBoxContainer.new()
var _marks_card := Card.new()
var _count := Label.new()
var _section_note := Label.new()
var _problems := VBoxContainer.new()
var _labels: Dictionary = {}
var _saved: Array = []
var _level := 0
var _record: Dictionary = {}
var _loading := false


func _init() -> void:
	list.title = "Notes"
	list.filter_placeholder = "Filter notes"
	list.custom_minimum_size.x = 220
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.can_add = true
	list.set_columns([{"title": "#", "width": 34, "mono": true}, {"title": "Note", "width": 0}])
	list.row_selected.connect(func(id): if id != null and not _loading: shell.guard(show_note.bind(int(id))))
	list.add_requested.connect(add_note)
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
	centre.add_child(header)
	centre.add_child(_labels_card())
	# What the note shows, and the window as the game draws it, side by side while there is room.
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 10)
	top.add_theme_constant_override("v_separation", 10)
	var shows := _shows_card()
	shows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shows.custom_minimum_size.x = 330
	top.add_child(shows)
	var shown := Card.new()
	shown.title = "As the game draws it"
	shown.add_row(preview)
	shown.add_row(_note("A 320-pixel window. The words follow in a dialog, and the game waits for a click."))
	top.add_child(shown)
	centre.add_child(top)
	_marks_card.title = "Marks"
	for index in range(10): _marks_card.add_row(_mark_row(index))
	centre.add_child(_marks_card)
	centre.add_child(_words_card())
	var problems := Card.new()
	problems.title = "Problems"
	_problems.add_theme_constant_override("separation", 6)
	problems.add_row(_problems)
	centre.add_child(problems)


func setup(owner_shell: Control) -> void:
	shell = owner_shell


func _note(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"Muted"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	return label


func _spin(spin: SpinBox, low: int, high: int, width := 90) -> SpinBox:
	spin.min_value = low
	spin.max_value = high
	spin.rounded = true
	spin.custom_minimum_size.x = width
	spin.value_changed.connect(func(_value): if not _loading: _edited())
	return spin


func _labelled(text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	var caption := Label.new()
	caption.theme_type_variation = &"Dim"
	caption.text = text
	box.add_child(caption)
	box.add_child(control)
	return box


func _labels_card() -> Card:
	var card := Card.new()
	card.title = "Menu labels"
	var line := HFlowContainer.new()
	line.add_theme_constant_override("h_separation", 14)
	for entry in [["Before the party has it", before, false], ["After", after, true]]:
		var field: LineEdit = entry[1]
		field.custom_minimum_size.x = 230
		field.max_length = 255
		var identified: bool = entry[2]
		field.text_changed.connect(func(_text): if not _loading: _label_edited(identified))
		line.add_child(_labelled(entry[0], field))
	card.add_row(line)
	return card


func _shows_card() -> Card:
	var card := Card.new()
	card.title = "Shows"
	for entry in ["A section of a map", "A picture", "A text window"]: mode.add_item(entry)
	mode.item_selected.connect(func(_index): if not _loading: _edited())
	card.add_row(mode)
	# A section of a map.
	_section.add_theme_constant_override("separation", 8)
	var line := HFlowContainer.new()
	line.add_theme_constant_override("h_separation", 14)
	map.custom_minimum_size.x = 130
	map.fit_to_longest_item = false
	map.item_selected.connect(func(_index): if not _loading: _edited())
	line.add_child(_labelled("Map", map))
	line.add_child(_labelled("Start column", _spin(start_x, 0, 89)))
	line.add_child(_labelled("Start row", _spin(start_y, 0, 89)))
	line.add_child(_labelled("Cell size (pixels)", _spin(icon_size, 1, 320, 110)))
	_section.add_child(line)
	_section_note.theme_type_variation = &"Dim"
	_section.add_child(_section_note)
	card.add_row(_section)
	# A picture.
	_picture_box.add_theme_constant_override("separation", 8)
	var picture_line := HBoxContainer.new()
	picture_line.add_theme_constant_override("separation", 10)
	picture_line.add_child(_labelled("Picture", _spin(picture, 1, 32767, 110)))
	var choose := Button.new()
	choose.text = "Choose…"
	choose.theme_type_variation = &"GhostButton"
	choose.size_flags_vertical = Control.SIZE_SHRINK_END
	choose.pressed.connect(func(): shell.resource_picker.show_for("picture", int(picture.value), "Note %d" % note, func(id): picture.value = id))
	picture_line.add_child(choose)
	_picture_box.add_child(picture_line)
	var size_line := HFlowContainer.new()
	size_line.add_theme_constant_override("h_separation", 14)
	size_line.add_child(_labelled("Height (0 keeps the picture's own)", _spin(bottom, 0, 32767, 110)))
	size_line.add_child(_labelled("Width (0 keeps the picture's own)", _spin(right, 0, 32767, 110)))
	_picture_box.add_child(size_line)
	card.add_row(_picture_box)
	# A text window.
	_text_box.add_child(_labelled("Scrolling text number", _spin(show_text, 1, 32767, 110)))
	card.add_row(_text_box)
	return card


func _mark_row(index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var number := Label.new()
	number.theme_type_variation = &"MonoDim"
	number.text = str(index + 1)
	number.custom_minimum_size.x = 20
	row.add_child(number)
	var icon := _spin(SpinBox.new(), -32768, 32767, 96)
	row.add_child(icon)
	_marks.append({"icon": icon, "column": SpinBox.new(), "row": SpinBox.new()})
	_pending_attach.append([row, icon])
	var column_spin: SpinBox = _marks[index].column
	var row_spin: SpinBox = _marks[index].row
	_spin(column_spin, 0, 255, 74)
	_spin(row_spin, 0, 255, 74)
	column_spin.prefix = "col "
	row_spin.prefix = "row "
	row.add_child(column_spin)
	row.add_child(row_spin)
	return row


var _pending_attach: Array = []


func _words_card() -> Card:
	var card := Card.new()
	card.title = "Words"
	words.custom_minimum_size.y = 90
	words.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	words.text_changed.connect(func(): if not _loading: _edited())
	card.add_row(words)
	_count.theme_type_variation = &"Dim"
	card.add_row(_count)
	return card


func refresh() -> void:
	if shell.summary.is_empty(): return
	if not _pending_attach.is_empty():
		for pending in _pending_attach: shell.references.attach(pending[0], pending[1], "icon")
		_pending_attach.clear()
	var response: Dictionary = await shell.request_backend({"op": "notes"})
	var labels: Dictionary = await shell.request_backend({"op": "note_labels"})
	if not response.get("ok", false) or not labels.get("ok", false): return
	_saved = response.result.notes
	_labels = labels.result
	map.clear()
	for id in range(int(shell.summary.get("maps", 0))): map.add_item("Map %d" % id, id)
	_rebuild_list()
	note = clampi(note, 0, maxi(0, _all().size() - 1))
	await show_note(note)


## The notes as saved with the unapplied edits of them put over them.
func _all() -> Array:
	var all: Array = []
	for saved in _saved: all.append(_with_draft(saved))
	var next := _saved.size()
	while shell.drafts.has("map_note:%d" % next):
		all.append(_with_draft({"note": next}))
		next += 1
	return all


func _with_draft(saved: Dictionary) -> Dictionary:
	var merged := saved.duplicate(true)
	var draft: Dictionary = shell.drafts.get("map_note:%d" % int(saved.note), {})
	if not draft.is_empty():
		for key in draft:
			if key != "kind": merged[key] = draft[key]
	if not merged.has("marks"):
		merged["marks"] = []
		for index in range(10): merged.marks.append([0, 0, 0])
		for key in FIELDS: merged[key] = 0
		merged["icon_size"] = 16
		merged["text"] = ""
	return merged


func _label_of(index: int, identified: bool) -> String:
	var key := "note_label:%d:%d" % [index + 1, int(identified)]
	if shell.drafts.has(key): return str(shell.drafts[key].text)
	var list_of: Array = _labels.get("known" if identified else "unknown", [])
	return str(list_of[index]) if index < list_of.size() else DASHES


func _kind_of(entry: Dictionary) -> String:
	if int(entry.show) != 0: return "text window"
	if int(entry.picture) != 0: return "picture"
	return "map %d" % int(entry.level)


func _rebuild_list() -> void:
	_loading = true
	var rows: Array = []
	for entry in _all():
		var index := int(entry.note)
		var title := _label_of(index, true)
		if title == DASHES: title = "Note %d" % index
		rows.append({"id": index, "cells": [str(index), "%s · %s" % [title, _kind_of(entry)]], "dirty": shell.drafts.has("map_note:%d" % index) or shell.drafts.has("note_label:%d:0" % (index + 1)) or shell.drafts.has("note_label:%d:1" % (index + 1))})
	list.set_rows(rows)
	list.set_count(rows.size())
	_loading = false


func show_note(id: int) -> void:
	note = id
	var all := _all()
	if all.is_empty(): _record = {}; return
	_record = all[clampi(id, 0, all.size() - 1)]
	_loading = true
	list.select(id)
	before.text = _label_of(id, false)
	after.text = _label_of(id, true)
	mode.select(2 if int(_record.show) != 0 else (1 if int(_record.picture) != 0 else 0))
	var map_index := map.get_item_index(int(_record.level))
	map.select(maxi(0, map_index))
	start_x.value = clampi(int(_record.start_x), 0, 89)
	start_y.value = clampi(int(_record.start_y), 0, 89)
	icon_size.value = clampi(int(_record.icon_size), 1, 320)
	picture.value = maxi(1, int(_record.picture))
	bottom.value = clampi(int(_record.bottom), 0, 32767)
	right.value = clampi(int(_record.right), 0, 32767)
	show_text.value = maxi(1, int(_record.show))
	words.text = str(_record.text)
	for index in range(10):
		var mark: Array = _record.marks[index]
		_marks[index].icon.value = int(mark[0])
		_marks[index].column.value = clampi(int(mark[1]), 0, 255)
		_marks[index].row.value = clampi(int(mark[2]), 0, 255)
	_loading = false
	await _refresh_view()


## The record as the form holds it.
func _form() -> Dictionary:
	var kind := mode.selected
	var marks: Array = []
	for index in range(10): marks.append([int(_marks[index].icon.value), int(_marks[index].column.value), int(_marks[index].row.value)])
	return {"kind": "map_note", "note": note, "marks": marks,
		"start_x": int(start_x.value), "start_y": int(start_y.value), "level": int(map.get_selected_id()) if map.item_count > 0 else 0,
		"picture": int(picture.value) if kind == 1 else 0, "icon_size": int(icon_size.value), "show": int(show_text.value) if kind == 2 else 0,
		"bottom": int(bottom.value) if kind == 1 else 0, "right": int(right.value) if kind == 1 else 0, "text": words.text}


func _edited() -> void:
	var form := _form()
	var key := "map_note:%d" % note
	var saved: Dictionary = {}
	for entry in _saved:
		if int(entry.note) == note: saved = entry
	var same := not saved.is_empty()
	if same:
		for field in FIELDS:
			if int(saved[field]) != int(form[field]): same = false
		if str(saved.text) != str(form.text): same = false
		for index in range(10):
			for part in range(3):
				if int(saved.marks[index][part]) != int(form.marks[index][part]): same = false
	if same: shell.drafts.erase(key)
	else: shell.drafts[key] = form
	_record = _with_draft({"note": note})
	shell._invalidate_receipt()
	shell._update_buttons()
	_rebuild_list()
	list.select(note)
	_refresh_view.call_deferred()


func _label_edited(identified: bool) -> void:
	var key := "note_label:%d:%d" % [note + 1, int(identified)]
	var text: String = (after if identified else before).text
	var list_of: Array = _labels.get("known" if identified else "unknown", [])
	var saved_text := str(list_of[note]) if note < list_of.size() else DASHES
	if text == saved_text: shell.drafts.erase(key)
	else: shell.drafts[key] = {"kind": "note_label", "note": note + 1, "identified": identified, "text": text}
	shell._invalidate_receipt()
	shell._update_buttons()
	_rebuild_list()
	list.select(note)
	_mark()


## Adds a note after the last: a section of Map 0 with no marks and no words.
func add_note() -> void:
	var next := _all().size()
	if next >= NOTES:
		shell.status("The menu holds notes 0 to 18", "warn")
		return
	note = next
	var form := _with_draft({"note": next})
	form["kind"] = "map_note"
	form["icon_size"] = 16
	shell.drafts["map_note:%d" % next] = form
	shell._invalidate_receipt()
	shell._update_buttons()
	_rebuild_list()
	await show_note(next)


## The sections and fields that suit the mode, the words' size, the preview and what is wrong with the note.
func _refresh_view() -> void:
	var kind := mode.selected
	_section.visible = kind == 0
	_picture_box.visible = kind == 1
	_text_box.visible = kind == 2
	_marks_card.visible = kind == 0
	header.title.text = "Note %d" % note
	header.sub.text = "Data MD2 · record %d · code 29 with %d gives it · menu item %d" % [note, note, note + 4]
	header.show_badges([["unapplied", &"BadgeWarn"]] if shell.drafts.has("map_note:%d" % note) or shell.drafts.has("note_label:%d:0" % (note + 1)) or shell.drafts.has("note_label:%d:1" % (note + 1)) else [])
	_count.text = "%d / 255 bytes · shown in the note's dialog" % words.text.to_utf8_buffer().size()
	var unit := maxi(1, int(icon_size.value))
	var cells := 320 / unit + (1 if 320 / unit * unit < 320 else 0)
	_section_note.text = "The section is %d cells across: columns %d to %d, rows %d to %d." % [cells, int(start_x.value), int(start_x.value) + cells - 1, int(start_y.value), int(start_y.value) + cells - 1]
	preview.mode = ["section", "picture", "text"][kind]
	preview.start = Vector2i(int(start_x.value), int(start_y.value))
	preview.size_of_cell = unit
	preview.marks = _form().marks
	await _load_view()
	preview.queue_redraw()
	_mark()
	_show_problems(cells)


func _load_view() -> void:
	var kind := mode.selected
	if kind == 1:
		preview.picture = await shell.references.picture(int(picture.value))
		preview.picture_size = Vector2(int(right.value), int(bottom.value))
		return
	if kind != 0: return
	var level := int(map.get_selected_id()) if map.item_count > 0 else 0
	if level != _level or preview.floor_values.is_empty():
		_level = level
		var response: Dictionary = await shell.request_backend({"op": "map", "id": level})
		preview.floor_values = response.result.floor if response.get("ok", false) else []
		preview.atlas = null
		preview.default_tile = 0
		var art: Dictionary = await shell.request_backend({"op": "artwork", "map": level, "installation": shell.folder})
		if art.get("ok", false) and art.result.get("status") == "available":
			var image := Image.load_from_file(str(art.result.png).replace("\\\\?\\", ""))
			if image != null: preview.atlas = ImageTexture.create_from_image(image)
			preview.default_tile = int(art.result.default_tile) if art.result.get("default_tile") != null else 0
	var wanted: Array = []
	for mark in preview.marks:
		if int(mark[0]) != 0: wanted.append(int(mark[0]))
	for tile in preview.floor_values:
		if int(tile) < 0 and not wanted.has(-int(tile)) and wanted.size() < 400: wanted.append(-int(tile))
	await shell.references.fetch(wanted)
	preview.icons.clear()
	for id in wanted:
		var texture: Texture2D = shell.references.icon(int(id))
		if texture != null: preview.icons[int(id)] = texture


func _show_problems(cells: int) -> void:
	for child in _problems.get_children(): _problems.remove_child(child); child.queue_free()
	var lines: PackedStringArray = []
	var kind := mode.selected
	if kind == 0 and (int(start_x.value) + cells > 90 or int(start_y.value) + cells > 90):
		lines.append("The section runs past the edge of the map; the game reads what follows the map's cells there.")
	if kind == 1 and preview.picture == null: lines.append("No resource file holds picture %d, so nothing is drawn." % int(picture.value))
	if kind == 0:
		for mark in preview.marks:
			if int(mark[0]) != 0 and not preview.icons.has(int(mark[0])): lines.append("No resource file holds icon %d, so its mark draws nothing." % int(mark[0]))
	if lines.is_empty(): lines.append("Nothing to report for this note.")
	for line in lines: _problems.add_child(_note(line))


func _mark() -> void:
	var drafted: bool = shell.drafts.keys().any(func(key): return str(key).begins_with("note_label:") or str(key).begins_with("map_note:"))
	header.show_badges([["unapplied", &"BadgeWarn"]] if drafted else [])
