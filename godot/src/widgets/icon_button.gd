extends Button
## A square button that shows one glyph.
const Glyph = preload("res://src/widgets/glyph.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

@export var glyph := "":
	set(value): glyph = value; queue_redraw()
@export var extent := 16.0


func _init() -> void:
	theme_type_variation = &"IconButton"
	custom_minimum_size = Vector2(Tokens.CONTROL_HEIGHT, Tokens.CONTROL_HEIGHT)


func _draw() -> void:
	var color := Tokens.MUTED
	if disabled: color = Tokens.tint(Tokens.DIM, 0.6)
	elif button_pressed: color = Tokens.ACCENT
	elif is_hovered(): color = Tokens.TEXT
	Glyph.paint(self, glyph, Rect2((size - Vector2(extent, extent)) / 2.0, Vector2(extent, extent)), color)
