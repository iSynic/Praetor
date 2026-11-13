extends "res://src/widgets/modal_overlay.gd"
## Choose message: the rows of the message table, searched by number or text,
## with the one in hand shown as it reads in the game. Choosing changes only the
## step's operand; the message stays in the table.
signal message_chosen(id: int)
const KbdButton = preload("res://src/widgets/kbd_button.gd")
const RecordList = preload("res://src/widgets/record_list.gd")

const PAGE := 128

var shell: Control
var list := RecordList.new()
var _rows: Array = []
var _offset := 0
var _total := 0
var _current := 0
var _picked := 0
var _query := ""
var _title_label := Label.new()
var _preview := Label.new()
var _range := Label.new()
var _use: KbdButton
var _previous: Button
var _next: Button
var _timer := Timer.new()


func _init() -> void:
	super()
	title = "Choose message"
	panel_size = Vector2(1100, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	body.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	list.filter_placeholder = "Filter by id or text…"
	list.filter_locally = false
	list.custom_minimum_size = Vector2(640, 420)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.set_columns([{"title": "ID", "width": 54, "mono": true}, {"title": "Text", "width": 0}])
	list.row_selected.connect(func(id): if id != null: _pick(int(id)))
	list.row_activated.connect(func(id): if id != null: _picked = int(id); _commit())
	list.filter_changed.connect(func(text): _query = text; _timer.start())
	row.add_child(list)
	var side := PanelContainer.new()
	side.theme_type_variation = &"Detail"
	side.custom_minimum_size.x = 340
	row.add_child(side)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	side.add_child(stack)
	_title_label.theme_type_variation = &"Heading"
	stack.add_child(_title_label)
	var window := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.BLACK
	style.border_color = Color.WHITE
	for side_name in ["left", "top", "right", "bottom"]: style.set("border_width_" + side_name, 2)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	window.add_theme_stylebox_override("panel", style)
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.add_theme_color_override("font_color", Color(0.93, 0.78, 0.16))
	window.add_child(_preview)
	stack.add_child(window)
	var note := Label.new()
	note.theme_type_variation = &"Muted"
	note.add_theme_font_size_override("font_size", 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Choosing another message changes only this step's operand; the message stays in the table."
	stack.add_child(note)
	var pager := HBoxContainer.new()
	pager.add_theme_constant_override("separation", 6)
	_range.theme_type_variation = &"Dim"
	_range.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pager.add_child(_range)
	_previous = Button.new()
	_previous.text = "‹"
	_previous.pressed.connect(func(): _load(maxi(0, _offset - PAGE)))
	pager.add_child(_previous)
	_next = Button.new()
	_next.text = "›"
	_next.pressed.connect(func(): _load(_offset + PAGE))
	pager.add_child(_next)
	column.add_child(pager)
	var new_message := Button.new()
	new_message.text = "New message"
	new_message.disabled = true
	new_message.tooltip_text = "Messages are added in Messages"
	add_footer_button(new_message)
	new_message.reparent(footer_left)
	new_message.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_button("Cancel").pressed.connect(close)
	_use = KbdButton.new()
	_use.theme_type_variation = &"PrimaryButton"
	_use.hint = "Enter"
	_use.pressed.connect(_commit)
	add_footer_button(_use)
	_timer.wait_time = 0.3
	_timer.one_shot = true
	_timer.timeout.connect(func(): _load(0))
	add_child(_timer)


func setup(owner_shell: Control) -> void:
	shell = owner_shell


## Opens on the row of `id`, for the step described by `where`.
func show_for(id: int, where: String) -> void:
	_current = id
	_picked = id
	_query = ""
	subtitle = where
	list.clear_filter()
	open()
	_load((maxi(id, 0) / PAGE) * PAGE)


func _load(start: int) -> void:
	var response: Dictionary = await shell.request_backend({"op": "messages", "offset": start, "limit": PAGE, "query": _query})
	if not response.get("ok", false): return
	_rows = response.result.rows
	_offset = start
	_total = int(response.result.total)
	var shown: Array = []
	for item in _rows: shown.append({"id": int(item.id), "cells": ["%d" % int(item.id), str(item.text).replace("\n", " ").left(110) if str(item.text) != "" else "empty"]})
	list.set_rows(shown)
	list.set_count(_total)
	_range.text = "Rows %d–%d of %d" % [start + 1, start + _rows.size(), _total] if not _rows.is_empty() else "No message matches"
	_previous.disabled = start == 0
	_next.disabled = start + PAGE >= _total
	if _query.is_empty() and _current >= start and _current < start + _rows.size():
		list.select(_current)
		_pick(_current)
	elif not _rows.is_empty(): _pick(int(_rows[0].id))


func _pick(id: int) -> void:
	_picked = id
	_title_label.text = "Message %d%s" % [id, "  · current" if id == _current else ""]
	_use.text = "Use message %d" % id
	for item in _rows:
		if int(item.id) == id: _preview.text = str(item.text)


func _commit() -> void:
	close()
	message_chosen.emit(_picked)


func _unhandled_key_input(event: InputEvent) -> void:
	super(event)
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_commit()
		get_viewport().set_input_as_handled()
