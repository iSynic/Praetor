extends HBoxContainer
## Texts: the scrolling texts of the scenario, each a TEXT and the styl that sets its fonts. Code 62 and the
## opening prologue show them in the scrolling window. Every change is a draft that waits for Apply.
const Card = preload("res://src/widgets/card.gd")
const PageHeader = preload("res://src/widgets/page_header.gd")
const RecordList = preload("res://src/widgets/record_list.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

## The fonts the original names by number.
const FONTS := {0: "System", 1: "Application", 2: "New York", 3: "Geneva", 4: "Monaco", 20: "Times", 21: "Helvetica", 22: "Courier", 23: "Symbol"}
const LIMIT := 32000

var shell: Control
var text_id := 1000
var list := RecordList.new()
var header := PageHeader.new()
var editor := TextEdit.new()
var _number := SpinBox.new()
var _meter := ProgressBar.new()
var _left := Label.new()
var _runs_box := VBoxContainer.new()
var _runs: Array = []
var _preview := RichTextLabel.new()
var _uses := VBoxContainer.new()
var _saved: Dictionary = {}
var _rows: Array = []
var _loading := false
var _delete: Button
var _import_dialog := FileDialog.new()
var _export_dialog := FileDialog.new()


func _init() -> void:
	add_theme_constant_override("separation", 12)
	list.title = "Texts"
	list.filter_placeholder = "Filter by number or words"
	# The filter looks in the whole text, not only in the words it begins with, so the list does it.
	list.filter_locally = false
	list.filter_changed.connect(func(_text): _show_rows())
	list.custom_minimum_size.x = 250
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.set_columns([{"title": "ID", "width": 52, "mono": true}, {"title": "Begins", "width": 0}, {"title": "Size", "width": 56, "mono": true, "right": true}])
	list.row_selected.connect(func(row): if row != null and not _loading: shell.guard(show_text.bind(int(row))))
	var new_line := HBoxContainer.new()
	new_line.add_theme_constant_override("separation", 8)
	var new_label := Label.new()
	new_label.theme_type_variation = &"Dim"
	new_label.text = "New text number"
	new_line.add_child(new_label)
	_number.min_value = 1
	_number.max_value = 32767
	_number.value = 1000
	_number.custom_minimum_size.x = 90
	new_line.add_child(_number)
	var create := Button.new()
	create.text = "Add"
	create.pressed.connect(func(): shell.guard(add_text))
	new_line.add_child(create)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size.x = 250
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(list)
	left.add_child(new_line)
	add_child(left)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 10)
	scroll.add_child(centre)
	header.mark(Tokens.FAMILY.media)
	centre.add_child(header)
	var import_button := header.add_button("Import file…")
	import_button.pressed.connect(func(): _import_dialog.popup_centered_ratio(0.6))
	var export_button := header.add_button("Export…")
	export_button.pressed.connect(func(): _export_dialog.popup_centered_ratio(0.6))
	_delete = header.add_button("Delete")
	_delete.pressed.connect(func(): shell.guard(remove_text))
	var text_card := Card.new()
	text_card.title = "Text"
	editor.custom_minimum_size.y = 260
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.text_changed.connect(func(): if not _loading: _edited())
	text_card.add_row(editor)
	var meter := HBoxContainer.new()
	meter.add_theme_constant_override("separation", 10)
	_meter.show_percentage = false
	_meter.max_value = LIMIT
	_meter.custom_minimum_size = Vector2(160, 6)
	_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.add_child(_meter)
	_left.theme_type_variation = &"Dim"
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.clip_text = true
	meter.add_child(_left)
	var tokens := Label.new()
	tokens.theme_type_variation = &"Dim"
	tokens.text = "^1 to ^6 and ^9 name warriors"
	meter.add_child(tokens)
	text_card.add_row(meter)
	centre.add_child(text_card)
	var styles := Card.new()
	styles.title = "Style runs"
	var add_run := Button.new()
	add_run.text = "Add a run at the cursor"
	add_run.pressed.connect(_add_run)
	styles.right.add_child(add_run)
	_runs_box.add_theme_constant_override("separation", 6)
	styles.add_row(_runs_box)
	centre.add_child(styles)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 250
	side.add_theme_constant_override("separation", 10)
	add_child(side)
	var window := Card.new()
	window.title = "Scroll window"
	_preview.bbcode_enabled = true
	_preview.fit_content = false
	_preview.custom_minimum_size = Vector2(0, 220)
	_preview.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_preview.scroll_active = true
	window.add_row(_preview)
	var note := Label.new()
	note.theme_type_variation = &"Dim"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "The game scrolls this window one pixel every four ticks and closes it on a double click."
	window.add_row(note)
	side.add_child(window)
	var used := Card.new()
	used.title = "Used by"
	_uses.add_theme_constant_override("separation", 4)
	used.add_row(_uses)
	side.add_child(used)
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.use_native_dialog = true
	_import_dialog.filters = PackedStringArray(["*.txt ; Text files"])
	_import_dialog.file_selected.connect(_import_file)
	add_child(_import_dialog)
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.use_native_dialog = true
	_export_dialog.filters = PackedStringArray(["*.txt ; Text files"])
	_export_dialog.file_selected.connect(_export_file)
	add_child(_export_dialog)


func setup(owner_shell: Control) -> void:
	shell = owner_shell


func _key(id: int) -> String:
	return "scroll_text:%d" % id


func _draft_of(id: int) -> Dictionary:
	return shell.drafts.get(_key(id), {})


## Reads the texts again and shows the one in hand.
func refresh() -> void:
	if shell.summary.is_empty(): return
	var response: Dictionary = await shell.request_backend({"op": "scroll_texts"})
	_rows = response.result.rows if response.get("ok", false) else []
	_loading = true
	var ids: Array = []
	_show_rows(ids)
	_loading = false
	_number.value = _free_number(ids)
	if not ids.has(text_id) and not ids.is_empty(): text_id = int(ids[0])
	if ids.is_empty(): _show_none()
	else: await show_text(text_id)


func _free_number(ids: Array) -> int:
	var next := 1000
	while ids.has(next): next += 1
	return next


func _size(length: int) -> String:
	return "%d B" % length if length < 1024 else "%.1f KB" % (float(length) / 1024.0)


func _begins(text: String) -> String:
	for line in text.split("\n"):
		var clean := line.strip_edges()
		if not clean.is_empty() and not clean.begins_with("<<<"): return clean.left(60)
	return ""


func _show_none() -> void:
	_loading = true
	header.title.text = "No texts"
	header.sub.text = "The scenario holds no scrolling text. Add one with the number below the list."
	header.show_badges([])
	editor.text = ""
	_runs.clear()
	_fill_runs()
	_loading = false


## Shows a text with its unapplied edit over the saved one.
func show_text(id: int) -> void:
	text_id = id
	var draft := _draft_of(id)
	# A text that only exists as an unapplied addition is not in the scenario to ask for.
	var response: Dictionary = {}
	if _rows.any(func(row): return int(row.id) == id): response = await shell.request_backend({"op": "scroll_text", "id": id})
	_saved = response.result if response.get("ok", false) else {"id": id, "text": "", "runs": [_default_run()], "uses": [], "length": 0}
	_loading = true
	list.select(id)
	var removed := str(draft.get("kind", "")) == "scroll_text_remove"
	editor.text = str(draft.text) if str(draft.get("kind", "")) == "scroll_text" else str(_saved.text)
	editor.editable = not removed
	_runs = _whole(draft.runs if str(draft.get("kind", "")) == "scroll_text" and draft.get("runs") != null else _saved.runs)
	if _runs.is_empty(): _runs.append(_default_run())
	_fill_runs()
	_loading = false
	_show_state(removed)
	_show_uses()


## The runs with every number a whole number, as the adapter reads them.
func _whole(runs: Array) -> Array:
	var out: Array = []
	for run in runs:
		out.append({"start": int(run.start), "height": int(run.height), "ascent": int(run.ascent), "font": int(run.font), "face": int(run.face), "size": int(run.size), "color": [int(run.color[0]), int(run.color[1]), int(run.color[2])]})
	return out


func _default_run() -> Dictionary:
	return {"start": 0, "height": 14, "ascent": 11, "font": 3, "face": 0, "size": 12, "color": [0, 0, 0]}


func _show_state(removed: bool) -> void:
	var length := editor.text.length()
	header.title.text = "Text %d" % text_id
	var runs := _runs.size()
	header.sub.text = "TEXT and styl · %d characters · %d style run%s" % [length, runs, "" if runs == 1 else "s"]
	var badges: Array = []
	if _draft_of(text_id).size() > 0: badges.append(["removed" if removed else "unapplied", &"BadgeWarn"])
	header.show_badges(badges)
	_meter.value = length
	_left.text = "%d of %d characters left · Mac Roman" % [maxi(LIMIT - length, 0), LIMIT]
	_delete.disabled = removed
	_show_preview()


func _show_preview() -> void:
	var text := editor.text
	var marks: Array = _runs.duplicate()
	marks.sort_custom(func(a, b): return int(a.start) < int(b.start))
	var out := ""
	for index in range(marks.size()):
		var run: Dictionary = marks[index]
		var from := clampi(int(run.start), 0, text.length())
		var to := clampi(int(marks[index + 1].start) if index + 1 < marks.size() else text.length(), from, text.length())
		var chunk := text.substr(from, to - from).replace("[", "[lb]")
		var color := Color(float(run.color[0]) / 65535.0, float(run.color[1]) / 65535.0, float(run.color[2]) / 65535.0)
		if color.get_luminance() < 0.25: color = Color(0.95, 0.9, 0.78)
		var face := int(run.face)
		var open := "[font_size=%d][color=#%s]" % [clampi(int(round(float(run.size) * 0.6)), 9, 16), color.to_html(false)]
		var close := "[/color][/font_size]"
		if face & 1: open += "[b]"; close = "[/b]" + close
		if face & 2: open += "[i]"; close = "[/i]" + close
		if face & 4: open += "[u]"; close = "[/u]" + close
		out += open + chunk + close
	_preview.text = out
	_preview.scroll_to_line(0)


func _show_uses() -> void:
	for child in _uses.get_children(): _uses.remove_child(child); child.queue_free()
	var uses: Array = _saved.get("uses", [])
	if uses.is_empty():
		var none := Label.new()
		none.theme_type_variation = &"Dim"
		none.text = "No step shows this text."
		_uses.add_child(none)
	for use in uses:
		var line := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s · code 62" % str(use.label)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		line.add_child(label)
		var open := Button.new()
		open.text = "Open ↗"
		open.theme_type_variation = &"GhostButton"
		open.pressed.connect(func(): shell.guard(shell.programs.open_cell_link.bind({"family": str(use.family), "id": int(use.id)})))
		line.add_child(open)
		_uses.add_child(line)


## The style runs as rows of fields; any change is a draft.
func _fill_runs() -> void:
	for child in _runs_box.get_children(): _runs_box.remove_child(child); child.queue_free()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	for entry in [["From", 84], ["Font", 100], ["Size", 72], ["Style", 108], ["Colour", 0]]:
		var title := Label.new()
		title.theme_type_variation = &"Dim"
		title.text = entry[0]
		title.custom_minimum_size.x = entry[1]
		if int(entry[1]) == 0: title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
	_runs_box.add_child(head)
	for index in range(_runs.size()):
		var run: Dictionary = _runs[index]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var start := _spin(int(run.start), 0, 32000, 84)
		start.editable = index > 0
		start.value_changed.connect(func(value): _run_changed(index, "start", int(value)))
		line.add_child(start)
		var font := _spin(int(run.font), -32768, 32767, 100)
		font.tooltip_text = str(FONTS.get(int(run.font), "Font %d" % int(run.font)))
		font.value_changed.connect(func(value): _run_changed(index, "font", int(value)))
		line.add_child(font)
		var size := _spin(int(run.size), 1, 255, 72)
		size.value_changed.connect(func(value): _run_changed(index, "size", int(value)))
		line.add_child(size)
		for bit in [[1, "B"], [2, "I"], [4, "U"]]:
			var toggle := Button.new()
			toggle.text = bit[1]
			toggle.toggle_mode = true
			toggle.button_pressed = (int(run.face) & int(bit[0])) != 0
			toggle.custom_minimum_size.x = 28
			toggle.toggled.connect(func(on): _run_changed(index, "face", (int(_runs[index].face) | int(bit[0])) if on else (int(_runs[index].face) & ~int(bit[0]))))
			line.add_child(toggle)
		var colour := ColorPickerButton.new()
		colour.edit_alpha = false
		colour.custom_minimum_size = Vector2(48, 26)
		colour.color = Color(float(run.color[0]) / 65535.0, float(run.color[1]) / 65535.0, float(run.color[2]) / 65535.0)
		colour.color_changed.connect(func(value): _run_changed(index, "color", [roundi(value.r * 65535.0), roundi(value.g * 65535.0), roundi(value.b * 65535.0)]))
		line.add_child(colour)
		var remove := Button.new()
		remove.text = "✕"
		remove.theme_type_variation = &"GhostButton"
		remove.disabled = index == 0
		remove.tooltip_text = "Remove this run"
		remove.pressed.connect(func(): _remove_run(index))
		line.add_child(remove)
		_runs_box.add_child(line)


func _spin(value: int, low: int, high: int, width: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = mini(low, value)
	spin.max_value = maxi(high, value)
	spin.set_value_no_signal(value)
	spin.custom_minimum_size.x = width
	return spin


func _run_changed(index: int, field: String, value: Variant) -> void:
	if _loading or index >= _runs.size(): return
	_runs[index][field] = value
	if field == "height" or field == "size": _runs[index].height = roundi(float(_runs[index].size) * 1.17)
	if field == "size": _runs[index].ascent = roundi(float(_runs[index].size) * 0.92)
	_changed()
	if field == "font": _fill_runs()


## A run begins at the cursor, in the font of the run it splits.
func _add_run() -> void:
	if str(_draft_of(text_id).get("kind", "")) == "scroll_text_remove": return
	var at := _cursor_character()
	for run in _runs:
		if int(run.start) == at: return
	var base: Dictionary = _runs[0].duplicate(true)
	for run in _runs:
		if int(run.start) < at: base = run.duplicate(true)
	base.start = at
	_runs.append(base)
	_runs.sort_custom(func(a, b): return int(a.start) < int(b.start))
	_fill_runs()
	_changed()


func _remove_run(index: int) -> void:
	if index <= 0 or index >= _runs.size(): return
	_runs.remove_at(index)
	_fill_runs()
	_changed()


func _cursor_character() -> int:
	var at := 0
	for line in range(editor.get_caret_line()): at += editor.get_line(line).length() + 1
	return at + editor.get_caret_column()


func _edited() -> void:
	_runs = _runs.filter(func(run): return int(run.start) == 0 or int(run.start) < editor.text.length())
	_changed()


## The text and its runs as one draft, or none when they are as saved.
func _changed() -> void:
	if _loading: return
	var runs: Array = _whole(_runs)
	runs.sort_custom(func(a, b): return int(a.start) < int(b.start))
	var as_saved: bool = editor.text == str(_saved.text) and _same_runs(runs, _saved.runs)
	if as_saved: shell.drafts.erase(_key(text_id))
	else: shell.drafts[_key(text_id)] = {"kind": "scroll_text", "id": text_id, "text": editor.text, "runs": runs}
	shell._invalidate_receipt()
	shell._update_buttons()
	_show_state(false)
	_mark_row()


func _same_runs(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for index in range(a.size()):
		for key in ["start", "height", "ascent", "font", "face", "size"]:
			if int(a[index][key]) != int(b[index][key]): return false
		for channel in range(3):
			if int(a[index].color[channel]) != int(b[index].color[channel]): return false
	return true


func _mark_row() -> void:
	_show_rows()
	list.select(text_id)


## The rows of the list: every text of the scenario and the new ones not yet applied, limited to those whose number or
## whose whole words hold the filter. A text found by words later than its beginning shows the words around the match.
## `ids` collects the numbers of all the texts, whatever the filter.
func _show_rows(ids: Array = []) -> Array:
	var needle := list.filter_text().to_lower()
	var shown: Array = []
	var matches := func(id: int, words: String, begins: String, length: String, dirty: bool) -> void:
		var found := words.to_lower().find(needle) if not needle.is_empty() else -1
		if not needle.is_empty() and str(id).find(needle) < 0 and found < 0: return
		var cell := begins
		if found > begins.length(): cell = "… " + words.substr(maxi(0, found - 30), 70).replace("", " ").replace("
", " ")
		shown.append({"id": id, "cells": [str(id), cell, length], "dirty": dirty})
	for row in _rows:
		var id := int(row.id)
		ids.append(id)
		var draft := _draft_of(id)
		var removed := str(draft.get("kind", "")) == "scroll_text_remove"
		var words := str(draft.text) if str(draft.get("kind", "")) == "scroll_text" else str(row.get("words", row.first))
		matches.call(id, words, "(removed)" if removed else str(row.first), _size(int(row.length)), not draft.is_empty())
	for key in shell.drafts:
		var draft: Dictionary = shell.drafts[key]
		if str(draft.get("kind", "")) == "scroll_text" and not ids.has(int(draft.id)):
			ids.append(int(draft.id))
			matches.call(int(draft.id), str(draft.text), _begins(str(draft.text)), _size(str(draft.text).length()), true)
	shown.sort_custom(func(a, b): return int(a.id) < int(b.id))
	list.set_rows(shown)
	list.set_count(shown.size())
	return shown


## Starts a new text with the number in the box; it is saved when the edits are applied.
func add_text() -> void:
	var id := int(_number.value)
	var taken: bool = _rows.any(func(row): return int(row.id) == id) or str(_draft_of(id).get("kind", "")) == "scroll_text"
	if taken:
		shell.status("Text %d exists" % id, "err")
		return
	shell.drafts[_key(id)] = {"kind": "scroll_text", "id": id, "text": "", "runs": [_default_run()]}
	shell._invalidate_receipt()
	shell._update_buttons()
	text_id = id
	await refresh()


## Marks the text for removal; the step that shows it keeps its number.
func remove_text() -> void:
	var uses: Array = _saved.get("uses", [])
	shell.drafts[_key(text_id)] = {"kind": "scroll_text_remove", "id": text_id}
	shell._invalidate_receipt()
	shell._update_buttons()
	if not uses.is_empty(): shell.status("%d step%s still show text %d" % [uses.size(), "" if uses.size() == 1 else "s", text_id], "warn")
	await refresh()


func _import_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		shell.status("The file could not be read", "err")
		return
	editor.text = file.get_as_text().replace("\r\n", "\n").replace("\r", "\n")
	_edited()


func _export_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		shell.status("The file could not be written", "err")
		return
	file.store_string(editor.text)
	shell.status("Exported text %d" % text_id)
