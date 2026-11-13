extends Control
## The floors of the map's terrain, 20 across, and its special icons. The tile
## in use is outlined; a click or the arrow keys choose another.
signal chosen(tile: int, alt: bool)
const Tokens = preload("res://theme/editor_tokens.gd")

const ICON_CELL := 44.0

var atlas: Texture2D
var icons: Dictionary = {}
## The tile in use.
var current := 0:
	set(value): current = value; queue_redraw()
## "floor" shows the atlas; "icons" the masked icons the map uses.
var mode := "floor":
	set(value): mode = value; _fit(); queue_redraw()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	focus_mode = Control.FOCUS_ALL
	resized.connect(_fit)


func _fit() -> void:
	if mode == "floor":
		custom_minimum_size.y = size.x * 0.75
	else:
		var columns := maxi(1, int(size.x / ICON_CELL))
		custom_minimum_size.y = maxf(ICON_CELL, ceilf(icons.size() / float(columns)) * ICON_CELL)


func _ids() -> Array:
	var ids := icons.keys()
	ids.sort()
	return ids


func _draw() -> void:
	if mode == "icons":
		_draw_icons()
		return
	if atlas == null:
		draw_string(ThemeDB.fallback_font, Vector2(8, 24), "No artwork loaded", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Tokens.DIM)
		return
	var unit := size.x / 20.0
	draw_texture_rect(atlas, Rect2(Vector2.ZERO, Vector2(size.x, unit * 15.0)), false)
	if current >= 1 and current <= 300:
		var index := current - 1
		var rect := Rect2(Vector2((index % 20) * unit, (index / 20) * unit), Vector2.ONE * unit)
		draw_rect(rect, Color.BLACK, false, 3.0)
		draw_rect(rect, Tokens.SELECTED, false, 1.5)


func _draw_icons() -> void:
	var ids := _ids()
	if ids.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(8, 24), "This map uses no special icons", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Tokens.DIM)
		return
	var columns := maxi(1, int(size.x / ICON_CELL))
	for index in range(ids.size()):
		var rect := Rect2(Vector2((index % columns) * ICON_CELL + 4, (index / columns) * ICON_CELL + 4), Vector2(32, 32))
		draw_texture_rect(icons[ids[index]], rect, false)
		if int(ids[index]) == current: draw_rect(rect.grow(2), Tokens.SELECTED, false, 1.5)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(2, 44 - 6), str(ids[index]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Tokens.MUTED)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		grab_focus()
		if mode == "floor":
			var unit := size.x / 20.0
			var cell := Vector2i((event.position / unit).floor())
			if cell.x >= 0 and cell.x < 20 and cell.y >= 0 and cell.y < 15: chosen.emit(cell.y * 20 + cell.x + 1, event.alt_pressed)
		else:
			var ids := _ids()
			var columns := maxi(1, int(size.x / ICON_CELL))
			var index := int(event.position.y / ICON_CELL) * columns + int(event.position.x / ICON_CELL)
			if index >= 0 and index < ids.size() and int(event.position.x / ICON_CELL) < columns: chosen.emit(int(ids[index]), event.alt_pressed)
		accept_event()
	elif event is InputEventKey and event.pressed and mode == "floor" and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		var step: Vector2i = {KEY_LEFT: Vector2i(-1, 0), KEY_RIGHT: Vector2i(1, 0), KEY_UP: Vector2i(0, -1), KEY_DOWN: Vector2i(0, 1)}[event.keycode]
		var index := maxi(current, 1) - 1
		var moved: Vector2i = Vector2i(index % 20, index / 20) + step
		if moved.x >= 0 and moved.x < 20 and moved.y >= 0 and moved.y < 15: chosen.emit(moved.y * 20 + moved.x + 1, false)
		accept_event()
