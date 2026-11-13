extends Button
## One of a program's eight steps as a card: its number, opcode and name, what
## its operand points at, a bar in the colour of its family, and a lock when the
## editor keeps it as recorded. The chosen step is outlined.
const Glyph = preload("res://src/widgets/glyph.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

var slot := 0
var _bar := Tokens.DIM
var _dirty := false
var _number := Label.new()
var _code := Label.new()
var _name := Label.new()
var _sub := Label.new()
var _lock := Glyph.new()
var _warn := Label.new()
var _empty := false


func _init() -> void:
	theme_type_variation = &"RowButton"
	toggle_mode = true
	custom_minimum_size = Vector2(0, 50)
	focus_mode = Control.FOCUS_NONE
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(head)
	_code.theme_type_variation = &"MonoDim"
	_code.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_code)
	_name.theme_type_variation = &"Strong"
	_name.clip_text = true
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_name)
	_sub.theme_type_variation = &"Dim"
	_sub.clip_text = true
	_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(_sub)
	_warn.theme_type_variation = &"BadgeWarn"
	_warn.text = "warn"
	_warn.visible = false
	_warn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_warn)
	_lock.glyph = "lock"
	_lock.extent = 14.0
	_lock.color = Tokens.DIM
	_lock.visible = false
	_lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_lock)
	_number.theme_type_variation = &"MonoDim"
	_number.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_number.offset_left = 24
	_number.offset_right = 36
	_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_number)


## `step` is {slot, opcode, operand, authorable}; `title` and `sub` are the two lines.
func show_step(step: Dictionary, title: String, sub: String, family: String, dirty: bool, warn: bool) -> void:
	slot = int(step.slot)
	_number.text = str(slot + 1)
	_code.text = str(int(step.opcode))
	_name.text = title
	_sub.text = sub
	_bar = Tokens.KIND.get(family, Tokens.DIM)
	_dirty = dirty
	_empty = int(step.opcode) == 0
	_lock.visible = not step.authorable
	_warn.visible = warn
	modulate.a = 0.7 if _empty and not button_pressed else 1.0
	queue_redraw()


func _draw() -> void:
	# The card is filled with the colour of what the step does; an empty slot only hints at it.
	var fill := StyleBoxFlat.new()
	fill.bg_color = Tokens.tint(_bar, 0.05 if _empty else 0.24)
	fill.set_corner_radius_all(Tokens.RADIUS_BUTTON)
	draw_style_box(fill, Rect2(Vector2.ONE, size - Vector2(2, 2)))
	draw_rect(Rect2(0, 6, 4, size.y - 12), _bar if not _empty else Tokens.tint(_bar, 0.5))
	for column in range(2):
		for row in range(3): draw_circle(Vector2(12 + column * 5, size.y / 2.0 - 5 + row * 5), 1.1, Tokens.tint(Tokens.DIM, 0.8), true)
	if _dirty: draw_circle(Vector2(size.x - 8, 8), 3.5, Tokens.WARN, true, -1.0, true)
