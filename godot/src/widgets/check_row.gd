extends HBoxContainer
## A row of a checklist: a mark for how the check came out, what was checked
## and a mono note at the right.
const Tokens = preload("res://theme/editor_tokens.gd")

## "good", "warn", "err" or "idle" (not checked yet).
@export var state := "good":
	set(value): state = value; _mark.queue_redraw(); _apply_note_color()
@export var text := "":
	set(value): text = value; _label.text = value
@export var note := "":
	set(value): note = value; _note.text = value; _note.visible = not value.is_empty()

var _mark := Control.new()
var _label := Label.new()
var _note := Label.new()


func _init() -> void:
	add_theme_constant_override("separation", 10)
	_mark.custom_minimum_size = Vector2(18, 18)
	_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.draw.connect(_paint)
	add_child(_mark)
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)
	_note.theme_type_variation = &"MonoDim"
	_note.visible = false
	_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_note)


func _apply_note_color() -> void:
	if state == "warn": _note.add_theme_color_override("font_color", Tokens.WARN)
	elif state == "err": _note.add_theme_color_override("font_color", Tokens.ERR)
	else: _note.remove_theme_color_override("font_color")


func _paint() -> void:
	var centre := _mark.size / 2.0
	var color: Color = {"good": Tokens.GOOD, "warn": Tokens.WARN, "err": Tokens.ERR}.get(state, Tokens.DIM)
	if state == "idle":
		_mark.draw_arc(centre, 7.5, 0.0, TAU, 24, color, 1.5, true)
		return
	_mark.draw_circle(centre, 8.5, color, true, -1.0, true)
	match state:
		"good":
			_mark.draw_polyline(PackedVector2Array([centre + Vector2(-3.5, 0.5), centre + Vector2(-1, 3), centre + Vector2(4, -3)]), Tokens.INK, 1.8, true)
		"err":
			_mark.draw_line(centre + Vector2(-3, -3), centre + Vector2(3, 3), Tokens.INK, 1.8, true)
			_mark.draw_line(centre + Vector2(3, -3), centre + Vector2(-3, 3), Tokens.INK, 1.8, true)
		_:
			_mark.draw_line(centre + Vector2(0, -4), centre + Vector2(0, 1), Tokens.INK, 1.9, true)
			_mark.draw_circle(centre + Vector2(0, 4), 1.1, Tokens.INK, true, -1.0, true)
