extends PanelContainer
## A titled card. Children placed under it in a scene move into its body;
## `right` holds controls beside the title.
const Glyph = preload("res://src/widgets/glyph.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

@export var title := "":
	set(value): title = value; _caption.text = value
@export var dot_color := Color.TRANSPARENT:
	set(value): dot_color = value; _dot.color = value; _dot.visible = value.a > 0.0
@export var gap := 10:
	set(value): gap = value; body.add_theme_constant_override("separation", value)

var body := VBoxContainer.new()
var right := HBoxContainer.new()
var _column := VBoxContainer.new()
var _caption := Label.new()
var _dot := Glyph.new()


func _init() -> void:
	theme_type_variation = &"Card"
	_column.add_theme_constant_override("separation", 10)
	add_child(_column, false, Node.INTERNAL_MODE_FRONT)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_column.add_child(head)
	_dot.glyph = "dot"
	_dot.extent = 12.0
	_dot.visible = false
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_dot)
	_caption.theme_type_variation = &"CaptionMuted"
	_caption.uppercase = true
	_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_caption)
	right.add_theme_constant_override("separation", 8)
	head.add_child(right)
	body.add_theme_constant_override("separation", gap)
	_column.add_child(body)


func _ready() -> void:
	for child in get_children(): child.reparent(body, false)


## Adds a row to the body and returns it.
func add_row(row: Control) -> Control:
	body.add_child(row)
	return row
