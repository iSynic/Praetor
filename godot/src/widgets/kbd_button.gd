extends Button
## A button that shows the key which runs it, as a small keycap at its right.
const Tokens = preload("res://theme/editor_tokens.gd")

@export var hint := "":
	set(value): hint = value; _reserve()

## A dot at the button's corner, for a button whose subject is behind its edits.
@export var marked := false:
	set(value): marked = value; queue_redraw()

var _chip := 0.0


func _ready() -> void:
	_reserve()


func _reserve() -> void:
	if not is_inside_tree(): return
	_chip = 0.0
	if not hint.is_empty():
		_chip = get_theme_font("mono", "EditorTokens").get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.KEY_SIZE).x + 12.0
	# A transparent icon at the right of the text keeps the room for the keycap.
	if _chip > 0.0:
		icon = ImageTexture.create_from_image(Image.create(int(_chip) + 4, 1, false, Image.FORMAT_RGBA8))
		icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		icon = null
	queue_redraw()


func _draw() -> void:
	if marked: draw_circle(Vector2(size.x - 7.0, 7.0), 3.5, Tokens.WARN, true, -1.0, true)
	if _chip <= 0.0: return
	var font: Font = get_theme_font("mono", "EditorTokens")
	var strength := 0.4 if disabled else 1.0
	var primary := theme_type_variation == &"PrimaryButton"
	var rect := Rect2(size.x - 12.0 - _chip, (size.y - 17.0) / 2.0, _chip, 17.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Tokens.tint(Tokens.ACCENT_INK if primary and not disabled else Tokens.LINE2, 0.45 if primary and not disabled else strength)
	for side in ["left", "top", "right", "bottom"]: style.set("border_width_" + side, 1)
	style.set_corner_radius_all(Tokens.RADIUS_KEY)
	style.anti_aliasing = true
	draw_style_box(style, rect)
	var ink := Tokens.tint(Tokens.ACCENT_INK, 0.75) if primary and not disabled else Tokens.tint(Tokens.MUTED, strength)
	draw_string(font, rect.position + Vector2(6.0, 12.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.KEY_SIZE, ink)
