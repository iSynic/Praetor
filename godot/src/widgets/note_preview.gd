extends Control
## A map note as the game draws it in its 320-pixel window: a section of a map with its marks, a picture centred in the window, or
## the scrolling-text window. The words of the note follow in a dialog the preview does not show.
const Tokens = preload("res://theme/editor_tokens.gd")

const WINDOW := 320.0

## "section", "picture" or "text".
var mode := "section"
var floor_values: Array = []
var atlas: Texture2D
var default_tile := 0
## cicn number -> texture, for the marks and for icons that stand as floor.
var icons: Dictionary = {}
var start := Vector2i.ZERO
var size_of_cell := 16
## Each mark is [icon, column, row].
var marks: Array = []
var picture: Texture2D
var picture_size := Vector2.ZERO


func _init() -> void:
	custom_minimum_size = Vector2(WINDOW, WINDOW)
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _tile(column: int, row: int) -> int:
	var index := column * 90 + row
	return int(floor_values[index]) if index >= 0 and index < floor_values.size() else 0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0b0f14"))
	match mode:
		"picture": _draw_picture()
		"text": _draw_text()
		_: _draw_section()


func _draw_text() -> void:
	draw_rect(Rect2(Vector2(10, 10), Vector2(WINDOW - 20, WINDOW - 20)), Color("1a1408"), true)
	draw_rect(Rect2(Vector2(10, 10), Vector2(WINDOW - 20, WINDOW - 20)), Tokens.LINE, false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(24, 40), "The scrolling-text window", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Tokens.TEXT)
	draw_string(ThemeDB.fallback_font, Vector2(24, 62), "plays the text and nothing else", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Tokens.DIM)


func _draw_picture() -> void:
	if picture == null:
		draw_string(ThemeDB.fallback_font, Vector2(24, 40), "No picture with this number", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Tokens.WARN)
		return
	var shown := picture_size if picture_size.x > 0 and picture_size.y > 0 else picture.get_size()
	var at := Vector2(floorf((WINDOW - shown.x) / 2.0), floorf((WINDOW - shown.y) / 2.0))
	draw_texture_rect(picture, Rect2(at, picture.get_size()), false)


func _draw_section() -> void:
	if floor_values.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(24, 40), "No map to show", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Tokens.WARN)
		return
	var unit := maxi(1, size_of_cell)
	var cells := int(WINDOW) / unit
	if cells * unit < int(WINDOW): cells += 1
	cells = maxi(cells, 1)
	for row in range(cells):
		for column in range(cells):
			var tile := _tile(start.x + column, start.y + row)
			var rect := Rect2(Vector2(column * unit, row * unit), Vector2(unit, unit))
			if tile > 0:
				if atlas != null and tile <= 300:
					var index := tile - 1
					draw_texture_rect_region(atlas, rect, Rect2(Vector2((index % 20) * 32, (index / 20) * 32), Vector2(32, 32)))
			else:
				if atlas != null and default_tile >= 1 and default_tile <= 300:
					var index := default_tile - 1
					draw_texture_rect_region(atlas, rect, Rect2(Vector2((index % 20) * 32, (index / 20) * 32), Vector2(32, 32)))
				if icons.get(-tile) != null: draw_texture_rect(icons[-tile], rect, false)
	for mark in marks:
		var icon := int(mark[0])
		if icon == 0: continue
		var cell := Vector2(int(mark[1]) * unit, int(mark[2]) * unit)
		# An icon is drawn at 32 pixels, centred on its cell, whatever the cell size is.
		var art: Texture2D = icons.get(icon)
		var rect := Rect2(cell + Vector2.ONE * (unit - 32) / 2.0, Vector2(32, 32))
		if art != null: draw_texture_rect(art, rect, false)
		else: draw_rect(rect.grow(-6), Color(0.95, 0.55, 0.2, 0.45))
