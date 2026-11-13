extends HBoxContainer
## The steps of a dialog in a row: finished steps carry a tick, the current
## step its number, the rest are dim.
const Tokens = preload("res://theme/editor_tokens.gd")

var _marks: Array = []
var _labels: Array = []
var _current := 0
var _failed := -1


func _init() -> void:
	add_theme_constant_override("separation", 10)


## `steps` are the names in order; the step at `current` is under way, and
## every step before it is done. Pass `current == steps.size()` when all are done.
func show_steps(steps: Array, current: int, failed := -1) -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	_marks.clear()
	_labels.clear()
	_current = current
	_failed = failed
	for index in range(steps.size()):
		if index > 0:
			var line := ColorRect.new()
			line.color = Tokens.ACCENT if index <= current and failed < 0 else Tokens.LINE2
			line.custom_minimum_size = Vector2(36, 1)
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			add_child(line)
		var mark := Control.new()
		mark.custom_minimum_size = Vector2(20, 20)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.draw.connect(_paint.bind(mark, index))
		add_child(mark)
		var label := Label.new()
		label.text = str(steps[index])
		label.theme_type_variation = &"Strong" if index <= current else &"Muted"
		add_child(label)
		_marks.append(mark)
		_labels.append(label)


func _paint(mark: Control, index: int) -> void:
	var centre := mark.size / 2.0
	if index < _current:
		mark.draw_circle(centre, 10.0, Tokens.ACCENT, true, -1.0, true)
		mark.draw_polyline(PackedVector2Array([centre + Vector2(-4, 0.5), centre + Vector2(-1.2, 3.4), centre + Vector2(4.2, -3.2)]), Tokens.ACCENT_INK, 2.0, true)
	else:
		var color := Tokens.ACCENT if index == _current else Tokens.LINE2
		if index == _failed: color = Tokens.ERR
		mark.draw_arc(centre, 9.2, 0.0, TAU, 28, color, 1.4, true)
		var font: Font = mark.get_theme_font("bold", "EditorTokens")
		var number := str(index + 1)
		var width := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		mark.draw_string(font, centre + Vector2(-width / 2.0, 4.0), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color if index == _current else Tokens.DIM)
