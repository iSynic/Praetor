extends HBoxContainer
## A labelled pair for dense rows: a dim key of fixed width and its value.

@export var key := "":
	set(value): key = value; _key.text = value
@export var value := "":
	set(text): value = text; _value.text = text
@export var key_width := 96.0:
	set(width): key_width = width; _key.custom_minimum_size.x = width
@export var mono := false:
	set(enabled): mono = enabled; _value.theme_type_variation = &"Mono" if enabled else &""

var _key := Label.new()
var _value := Label.new()


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_key.theme_type_variation = &"Dim"
	_key.custom_minimum_size.x = key_width
	_key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_child(_key)
	_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_value)


## Replaces the value label with a control, for rows that hold a field.
func set_control(control: Control) -> void:
	_value.visible = false
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(control)
