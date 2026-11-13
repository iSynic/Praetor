extends Control
## A battle's 26 × 26 population: where each monster stands when the battle
## begins. These are placements, not terrain. A negative id fights for the squad.
signal monster_requested(id: int)
signal cell_clicked(cell: Vector2i)
signal cell_erase_requested(cell: Vector2i)
signal cell_hovered(cell: Vector2i)
const Tokens = preload("res://theme/editor_tokens.gd")

const SIDE := 26

var cells: Array = []
var names: Dictionary = {}
## The picture of each monster in the grid, by monster id; a monster without one shows its number.
var icons: Dictionary = {}
var squad_start := Vector2i(-1, -1)
var selected := Vector2i(-1, -1)
var hover := Vector2i(-1, -1)
var tool := "select"
var _colours: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(240, 240)
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func set_cells(values: Array) -> void:
	cells = values
	_colours.clear()
	for value in cells:
		var id := absi(int(value))
		if id != 0 and not _colours.has(id): _colours[id] = _pick(_colours.size())
	queue_redraw()


## The colour of a monster, so a roster and the grid agree.
func colour_of(id: int) -> Color:
	return _colours.get(absi(id), Tokens.DIM)


## A monster that is placed for the first time takes the next colour.
func take_colour(id: int) -> void:
	if id != 0 and not _colours.has(absi(id)): _colours[absi(id)] = _pick(_colours.size())


static func _pick(index: int) -> Color:
	var picks := [Color("ef8159"), Color("d9b85c"), Color("6fb3e8"), Color("b28df2"), Color("79c77f"), Color("e07aa8"), Color("7fc0b4"), Color("c9c86a")]
	return picks[index % picks.size()]


func _margin() -> float:
	return 22.0


func cell_size() -> float:
	return minf(size.x - _margin(), size.y - _margin()) / float(SIDE)


func _cell_at(point: Vector2) -> Vector2i:
	var cell := Vector2i(((point - Vector2.ONE * _margin()) / cell_size()).floor())
	return cell if cell.x >= 0 and cell.y >= 0 and cell.x < SIDE and cell.y < SIDE else Vector2i(-1, -1)


## The middle of a cell, in this control's own pixels.
func centre_of(cell: Vector2i) -> Vector2:
	return Vector2.ONE * _margin() + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size()


func _draw() -> void:
	var step := cell_size()
	var origin := Vector2.ONE * _margin()
	var font: Font = get_theme_font("mono", "EditorTokens")
	draw_rect(Rect2(origin, Vector2.ONE * step * SIDE), Tokens.FIELD)
	for index in range(0, SIDE + 1):
		var color := Tokens.tint(Tokens.LINE, 0.9 if index % 5 == 0 else 0.5)
		draw_line(origin + Vector2(index * step, 0), origin + Vector2(index * step, SIDE * step), color, 1.0)
		draw_line(origin + Vector2(0, index * step), origin + Vector2(SIDE * step, index * step), color, 1.0)
	for index in range(0, SIDE, 5):
		draw_string(font, Vector2(origin.x + index * step + 2, 14), str(index), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Tokens.DIM)
		draw_string(font, Vector2(2, origin.y + index * step + 12), str(index), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Tokens.DIM)
	if squad_start.x >= 0:
		var at := centre_of(squad_start)
		draw_arc(at, step * 0.42, 0.0, TAU, 24, Tokens.START, 2.0, true)
		draw_string(font, at + Vector2(-30, step * 0.95), "Squad start", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Tokens.START)
	if cells.size() == SIDE * SIDE:
		for x in range(SIDE):
			for y in range(SIDE):
				var id := int(cells[x * SIDE + y])
				if id == 0: continue
				var rect := Rect2(origin + Vector2(x, y) * step, Vector2.ONE * step).grow(-1.5)
				var colour := colour_of(id)
				draw_rect(rect, Tokens.tint(colour, 0.22))
				draw_rect(rect, colour, false, 1.5)
				if id < 0: draw_rect(rect.grow(-3), colour, false, 1.0)
				if icons.has(absi(id)): draw_texture_rect(icons[absi(id)], rect.grow(-1), false)
				elif step >= 16: draw_string(font, rect.position + Vector2(2, step * 0.62), str(absi(id)), HORIZONTAL_ALIGNMENT_LEFT, step - 2, clampi(int(step * 0.36), 8, 12), Tokens.TEXT)
	if selected.x >= 0: draw_rect(Rect2(origin + Vector2(selected) * step, Vector2.ONE * step), Tokens.SELECTED, false, 2.0)
	if hover.x >= 0 and tool != "select": draw_rect(Rect2(origin + Vector2(hover) * step, Vector2.ONE * step), Tokens.tint(Tokens.SELECTED, 0.5), false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if cells.size() != SIDE * SIDE: return
	if event is InputEventMouseMotion:
		var cell := _cell_at(event.position)
		if cell != hover:
			hover = cell
			cell_hovered.emit(cell)
			queue_redraw()
		if cell.x >= 0:
			var id := int(cells[cell.x * SIDE + cell.y])
			tooltip_text = "(%d, %d) · %s" % [cell.x, cell.y, ("signed monster %d · %s" % [id, names.get(absi(id), "Unresolved definition")]) if id != 0 else "empty"]
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var cell := _cell_at(event.position)
		if cell.x < 0: return
		selected = cell
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			var id := absi(int(cells[cell.x * SIDE + cell.y]))
			if id != 0: monster_requested.emit(id)
		if event.button_index == MOUSE_BUTTON_LEFT: cell_clicked.emit(cell)
		else: cell_erase_requested.emit(cell)
		queue_redraw()
