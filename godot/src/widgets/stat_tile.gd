extends PanelContainer
## A count with its name beneath it, for the contents of a project.

@export var value := "":
	set(text): value = text; _value.text = text
@export var caption := "":
	set(text): caption = text; _caption.text = text

var _value := Label.new()
var _caption := Label.new()


func _init() -> void:
	theme_type_variation = &"Tile"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	_value.theme_type_variation = &"Mono"
	_value.add_theme_font_size_override("font_size", 13)
	column.add_child(_value)
	_caption.theme_type_variation = &"Dim"
	column.add_child(_caption)
