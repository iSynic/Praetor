extends Control
## The whole map in miniature, each cell one pixel of its tile's average
## colour, with the part the canvas shows outlined. A click or drag moves the view.
signal center_requested(cell: Vector2i)
const Tokens = preload("res://theme/editor_tokens.gd")

const SIDE := 90

var texture: ImageTexture
## The cells the canvas shows, in cell units.
var view := Rect2()
var _dragging := false


func _init() -> void:
	custom_minimum_size = Vector2(132, 132)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP


## `colors` maps a tile number to its average colour; a tile without one is grey.
func show_floor(floor_values: Array, colors: Dictionary, default_tile: int) -> void:
	if floor_values.size() != SIDE * SIDE:
		texture = null
		queue_redraw()
		return
	var image := Image.create(SIDE, SIDE, false, Image.FORMAT_RGB8)
	for x in range(SIDE):
		for y in range(SIDE):
			var tile := int(floor_values[x * SIDE + y])
			image.set_pixel(x, y, colors.get(default_tile if tile <= 0 else tile, Tokens.RAISED))
	texture = ImageTexture.create_from_image(image)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Tokens.INK)
	if texture == null: return
	draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)
	var unit := size / float(SIDE)
	var area := Rect2(view.position * unit, view.size * unit).intersection(Rect2(Vector2.ZERO, size))
	if area.size.x > 0.0 and area.size.y > 0.0: draw_rect(area, Tokens.SELECTED, false, 1.5)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed: _move(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_move(event.position)
		accept_event()


func _move(point: Vector2) -> void:
	var cell := Vector2i((point / size * float(SIDE)).floor()).clamp(Vector2i.ZERO, Vector2i(SIDE - 1, SIDE - 1))
	center_requested.emit(cell)
