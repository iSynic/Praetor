extends Button
## One workspace on the rail: its glyph, name, record count and lock.
const Glyph = preload("res://src/widgets/glyph.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

var glyph := ""
var caption := ""
var locked := false
var alert := false
var count := -1:
	set(value): count = value; queue_redraw()
var compact := false:
	set(value):
		compact = value
		custom_minimum_size = Vector2(64, 32 if value else 50)
		queue_redraw()


func _init() -> void:
	theme_type_variation = &"RailButton"
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(64, 50)


func _draw() -> void:
	var on := button_pressed and toggle_mode
	var ink := Tokens.MUTED
	if disabled: ink = Tokens.tint(Tokens.DIM, 0.55)
	elif on: ink = Tokens.ACCENT
	elif is_hovered(): ink = Tokens.TEXT
	if on: draw_rect(Rect2(0, 8, 3, size.y - 16), Tokens.ACCENT)
	var side := 18.0
	var top := (size.y - side) / 2.0 if compact else 8.0
	Glyph.paint(self, glyph, Rect2((size.x - side) / 2.0, top, side, side), ink)
	if not compact:
		var font := get_theme_font("font")
		var label := Tokens.TEXT if on else ink
		draw_string(font, Vector2(0, size.y - 8), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, Tokens.CAPTION_SIZE, label)
	if locked:
		Glyph.paint(self, "lock", Rect2(size.x - 22, top - 4, 9, 9), ink)
	elif count >= 0:
		var mono := get_theme_font("mono", "EditorTokens")
		var text := "1k+" if count > 999 else str(count)
		var width := mono.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 6.0
		var badge := Rect2(size.x - width - 6, top - 5, width, 12)
		draw_style_box(_badge(Tokens.ERR if alert and count > 0 else Tokens.RAISED), badge)
		draw_string(mono, badge.position + Vector2(3, 9.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Tokens.ERR_INK if alert and count > 0 else Tokens.MUTED)


func _badge(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(6)
	return style
