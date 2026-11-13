extends Button
## A tool of the map toolbar: its name and, small and dim after it, the key
## that selects it. The tool in hand is drawn filled.
const Tokens = preload("res://theme/editor_tokens.gd")

@export var key := "":
	set(value): key = value; _reserve()

var _width := 0.0


func _init() -> void:
	theme_type_variation = &"ToolButton"
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	_reserve()


func _reserve() -> void:
	if not is_inside_tree(): return
	_width = 0.0
	if not key.is_empty():
		_width = get_theme_font("mono", "EditorTokens").get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 4.0
	if _width > 0.0:
		icon = ImageTexture.create_from_image(Image.create(int(_width) + 2, 1, false, Image.FORMAT_RGBA8))
		icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		icon = null
	queue_redraw()


func _draw() -> void:
	if _width <= 0.0: return
	var font: Font = get_theme_font("mono", "EditorTokens")
	var ink := Tokens.tint(Tokens.ACCENT_INK, 0.6) if button_pressed else Tokens.tint(Tokens.DIM, 0.5 if disabled else 1.0)
	draw_string(font, Vector2(size.x - 10.0 - _width + 4.0, size.y / 2.0 - 1.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ink)
