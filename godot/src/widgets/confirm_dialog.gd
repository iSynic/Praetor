extends Control
## A question asked once. It names the record it is about, offers the safe
## choice as the default (Enter) and covers its parent while open.
signal confirmed
signal canceled
signal custom_action(action: String)
const Tokens = preload("res://theme/editor_tokens.gd")

## "warn", "err", "info" or "good": the circle at the left of the title.
@export var tone := "warn":
	set(value): tone = value; _circle.theme_type_variation = {"warn": &"CircleWarn", "err": &"CircleErr", "info": &"CircleInfo", "good": &"CircleGood"}.get(value, &"CircleWarn"); _mark.text = {"warn": "!", "err": "×", "info": "?", "good": "✓"}.get(value, "!"); _mark.add_theme_color_override("font_color", {"warn": Tokens.WARN, "err": Tokens.ERR, "info": Tokens.INFO, "good": Tokens.GOOD}.get(value, Tokens.WARN))
@export var heading := "":
	set(value): heading = value; _heading.text = value
@export var message := "":
	set(value): message = value; _message.text = value; _message.visible = not value.is_empty()

var _circle := PanelContainer.new()
var _mark := Label.new()
var _heading := Label.new()
var _message := Label.new()
var _details := PanelContainer.new()
var _rows := VBoxContainer.new()
var _note := Label.new()
var _left := HBoxContainer.new()
var _buttons := HBoxContainer.new()
var _default: Button
var _default_action := ""
var _answered := false


func _init() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	var scrim := ColorRect.new()
	scrim.color = Tokens.SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ModalPanel"
	panel.custom_minimum_size = Vector2(520, 0)
	centre.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	column.add_child(head)
	_circle.theme_type_variation = &"CircleWarn"
	_circle.custom_minimum_size = Vector2(34, 34)
	_circle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(_circle)
	_mark.theme_type_variation = &"Strong"
	_mark.text = "!"
	_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_circle.add_child(_mark)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 4)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(words)
	_heading.theme_type_variation = &"Heading"
	_heading.add_theme_font_size_override("font_size", 15)
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(_heading)
	_message.theme_type_variation = &"Muted"
	_message.add_theme_font_size_override("font_size", 12)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(_message)
	_details.theme_type_variation = &"Detail"
	_details.visible = false
	column.add_child(_details)
	_rows.add_theme_constant_override("separation", 5)
	_details.add_child(_rows)
	_note.theme_type_variation = &"Dim"
	_note.visible = false
	column.add_child(_note)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	column.add_child(foot)
	_left.add_theme_constant_override("separation", 8)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_left)
	_buttons.add_theme_constant_override("separation", 8)
	foot.add_child(_buttons)


## Shows what the question is about as rows of key and value. A value may be
## [text, colour].
func set_details(rows: Array) -> void:
	for child in _rows.get_children(): _rows.remove_child(child); child.queue_free()
	_details.visible = not rows.is_empty()
	for row in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		var key := Label.new()
		key.theme_type_variation = &"Dim"
		key.custom_minimum_size.x = 72
		key.text = str(row[0])
		line.add_child(key)
		var value := Label.new()
		value.theme_type_variation = &"Mono"
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		value.text = str(row[1])
		if row.size() > 2: value.add_theme_color_override("font_color", row[2])
		line.add_child(value)
		_rows.add_child(line)


func set_note(text: String) -> void:
	_note.text = text
	_note.visible = not text.is_empty()


## Adds a button. `kind` is "primary", "danger" or "secondary"; `action` is the
## name `custom_action` reports, or "" for the primary choice (`confirmed`) and
## "cancel" for `canceled`. A primary button is the default for Enter, so the
## safe choice should be primary. `left` puts it at the left of the row.
func add_button(text: String, kind := "secondary", action := "", left := false) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = {"primary": &"PrimaryButton", "danger": &"DangerButton"}.get(kind, &"")
	button.pressed.connect(_answer.bind(action if not action.is_empty() else ("confirm" if kind == "primary" else "cancel")))
	(_left if left else _buttons).add_child(button)
	if kind == "primary":
		_default = button
		_default_action = action if not action.is_empty() else "confirm"
	return button


func clear_buttons() -> void:
	for box in [_left, _buttons]:
		for child in box.get_children(): box.remove_child(child); child.queue_free()
	_default = null


func popup_centered(_size := Vector2i.ZERO) -> void:
	_answered = false
	visible = true
	move_to_front()
	grab_focus()
	if _default != null: _default.grab_focus()


func _answer(action: String) -> void:
	if _answered: return
	_answered = true
	visible = false
	match action:
		"confirm": confirmed.emit()
		"cancel": canceled.emit()
		_: custom_action.emit(action)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		_answer("cancel")
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER] and _default != null:
		_answer(_default_action)
		get_viewport().set_input_as_handled()
