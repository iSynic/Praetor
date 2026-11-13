extends Control
## The floor of one map as the squad sees it, with the layers the author works
## on: triggers, regions (read only), stage starts and the paint preview. Each
## tool reports what the author did; the page decides what that means.
## Interaction patterns adapted from Providence.
signal program_requested(id: int)
signal selected(cell: Vector2i, tile: int)
signal sampled(tile: int)
signal stroke_requested(cells: Array)
signal hovered(cell: Vector2i)
signal view_changed
## A click of the Trigger, Region, Start or Erase tool on a cell.
signal tool_clicked(tool: String, cell: Vector2i)
## A region being drawn, moved or resized: its slot (-1 for a new one) and the rectangle it now covers.
signal region_dragged(slot: int, rectangle: Rect2i)
signal region_drag_ended
const Stroke = preload("res://src/map_paint_stroke.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

const CELL := 32.0
const SIDE := 90

var floor_values: Array = []
var atlas: Texture2D
var icons: Dictionary = {}
var default_tile := 0
var triggers: Array = []
var regions: Array = []
## Stage starts on this map: {id, name, x, y}.
var stage_starts: Array = []
var show_floor := true
## The object layer: a word for each cell, 0 for nothing, a building (the picture 23000 plus the value) or minus an icon.
var objects: Array = []
## The art of the values the layer holds: building pictures and icons.
var object_art: Dictionary = {}
var show_objects := true
## Whether strokes paint the object layer, and the value they paint.
var paint_objects := false
var object_brush := 0
var show_triggers := true
var show_regions := true
var show_starts := true
var show_secrets := true
var show_grid := true
## The tool the author holds: select, sample, paint, line, rectangle, fill, trigger, region, start or erase.
var tool := "select"
var brush := 1
var selected_cell := Vector2i(-1, -1)
var selected_region := -1
var hover_cell := Vector2i(-1, -1)
## The trigger slot the Trigger tool places, and the stage the Start tool moves.
var active_slot := 0
var active_stage := 0
var zoom := 0.5
var pan := Vector2.ZERO
var _panning := false
var _stroke := Stroke.new()
var _anchor := Vector2i(-1, -1)
var _shape: Array[Vector2i] = []
## The drag of the Region tool: {mode, slot, anchor, origin}.
var _region_drag: Dictionary = {}


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	get_window().focus_exited.connect(cancel_stroke)
	resized.connect(func(): view_changed.emit())


## `keep_selection` holds the selected cell when the same map is shown again.
func set_map(values: Array, keep_selection := false) -> void:
	floor_values = values
	if not keep_selection:
		selected_cell = Vector2i(-1, -1)
		selected_region = -1
	cancel_stroke()
	queue_redraw()
	view_changed.emit()


func cancel_stroke() -> void:
	_stroke.clear()
	_region_drag = {}
	_anchor = Vector2i(-1, -1)
	_shape.clear()
	_panning = false
	queue_redraw()


func cell_pixels() -> float:
	return CELL * zoom


## The cells in view, as a rectangle in cell units.
func visible_cells() -> Rect2:
	var unit := cell_pixels()
	return Rect2(-pan / unit, size / unit)


func set_view(new_zoom: float, new_pan: Vector2) -> void:
	zoom = new_zoom
	pan = new_pan
	queue_redraw()
	view_changed.emit()


## Zooms about the middle of the canvas.
func zoom_to(level: float) -> void:
	var middle := size / 2.0
	var at := (middle - pan) / zoom
	set_view(level, middle - at * level)


## Scrolls so `cell` is in the middle.
func center_on(cell: Vector2i) -> void:
	set_view(zoom, size / 2.0 - (Vector2(cell) + Vector2(0.5, 0.5)) * cell_pixels())


func _cell(point: Vector2) -> Vector2i:
	return Vector2i(((point - pan) / cell_pixels()).floor())


func _valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < SIDE and cell.y < SIDE and floor_values.size() == SIDE * SIDE


func _tile(cell: Vector2i) -> int:
	return int(floor_values[cell.x * SIDE + cell.y])


## What a drag with the Line or Rectangle tool covers.
func _shape_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if tool == "rectangle":
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1): cells.append(Vector2i(x, y))
	else:
		var line := Stroke.new()
		line.begin(a)
		line.append(b)
		cells = line.cells.duplicate()
	return cells


## The cells joined to `start` by edges that hold the same tile.
func flood(start: Vector2i) -> Array:
	var wanted := _tile(start)
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var cells: Array = []
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		cells.append({"x": cell.x, "y": cell.y})
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if _valid(next) and not seen.has(next) and _tile(next) == wanted:
				seen[next] = true
				queue.append(next)
	return cells


func _cells_of(items: Array) -> Array:
	return items.map(func(item): return {"x": item.x, "y": item.y})


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var cell := _cell(event.position)
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var at: Vector2 = (event.position - pan) / zoom
			var level := clampf(zoom * (1.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 0.35, 4.0)
			set_view(level, event.position - at * level)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and _valid(cell):
			sampled.emit(_tile(cell))
		elif event.button_index == MOUSE_BUTTON_LEFT:
			grab_focus()
			if event.pressed and _valid(cell):
				_press(cell, event)
			elif not event.pressed:
				_release(cell)
		accept_event()
		queue_redraw()
	elif event is InputEventMouseMotion:
		var cell := _cell(event.position)
		if _panning:
			pan += event.relative
			view_changed.emit()
		if cell != hover_cell:
			hover_cell = cell
			hovered.emit(cell if _valid(cell) else Vector2i(-1, -1))
		if _stroke.active: _stroke.append(cell)
		if not _region_drag.is_empty() and _valid(cell): _drag_region(cell)
		if _anchor.x >= 0 and _valid(cell): _shape = _shape_cells(_anchor, cell)
		queue_redraw()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_stroke()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_DELETE and tool in ["trigger", "erase"] and _valid(selected_cell):
		tool_clicked.emit("erase", selected_cell)
		accept_event()


func _press(cell: Vector2i, event: InputEventMouseButton) -> void:
	selected_cell = cell
	selected.emit(cell, _tile(cell))
	if event.alt_pressed or tool == "sample":
		sampled.emit(_tile(cell))
		return
	match tool:
		"select":
			if event.double_click and show_triggers:
				for trigger in triggers:
					if int(trigger.x) == cell.x and int(trigger.y) == cell.y: program_requested.emit(int(trigger.id)); break
		"paint": _stroke.begin(cell)
		"line", "rectangle":
			_anchor = cell
			_shape = _shape_cells(cell, cell)
		"fill": stroke_requested.emit(flood(cell))
		"region":
			tool_clicked.emit(tool, cell)
			_begin_region_drag(cell)
		"trigger", "start", "erase": tool_clicked.emit(tool, cell)


func _release(cell: Vector2i) -> void:
	if not _region_drag.is_empty():
		_region_drag = {}
		region_drag_ended.emit()
		return
	if _stroke.active:
		var cells := _cells_of(_stroke.cells)
		_stroke.clear()
		stroke_requested.emit(cells)
	elif _anchor.x >= 0:
		var cells := _cells_of(_shape)
		cancel_stroke()
		if not cells.is_empty(): stroke_requested.emit(cells)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Tokens.INK)
	if floor_values.size() != SIDE * SIDE: return
	var unit := cell_pixels()
	var lo := Vector2i((-pan / unit).floor()).clamp(Vector2i.ZERO, Vector2i(SIDE - 1, SIDE - 1))
	var hi := Vector2i(((size - pan) / unit).ceil()).clamp(Vector2i.ZERO, Vector2i(SIDE, SIDE))
	if show_floor: _draw_floor(lo, hi, unit)
	if show_objects: _draw_objects(lo, hi, unit)
	if show_secrets: _draw_secrets(lo, hi, unit)
	if show_grid and unit >= 8.0:
		var lines := PackedVector2Array()
		for x in range(lo.x, hi.x + 1):
			lines.append(pan + Vector2(x * unit, lo.y * unit))
			lines.append(pan + Vector2(x * unit, hi.y * unit))
		for y in range(lo.y, hi.y + 1):
			lines.append(pan + Vector2(lo.x * unit, y * unit))
			lines.append(pan + Vector2(hi.x * unit, y * unit))
		draw_multiline(lines, Color(0, 0, 0, 0.34), 1.0)
	if show_regions: _draw_regions(unit)
	if show_triggers: _draw_triggers(unit)
	if show_starts: _draw_starts(unit)
	if _valid(hover_cell) and tool != "select": draw_rect(_rect(hover_cell, unit), Color(1, 1, 1, 0.5), false, 1.0)
	if _valid(selected_cell): draw_rect(_rect(selected_cell, unit).grow(-1), Tokens.SELECTED, false, 2.0)


func _rect(cell: Vector2i, unit: float) -> Rect2:
	return Rect2(pan + Vector2(cell) * unit, Vector2.ONE * unit)


func _draw_floor(lo: Vector2i, hi: Vector2i, unit: float) -> void:
	var preview: Dictionary = {}
	for cell in (_stroke.cells if _stroke.active else _shape): preview[cell] = true
	for x in range(lo.x, hi.x):
		for y in range(lo.y, hi.y):
			var cell := Vector2i(x, y)
			var tile := _tile(cell)
			# A secret keeps the tile it hides: the editor draws that tile, and the overlay marks the cell.
			if absi(tile) > 1999: tile = signi(tile) * (absi(tile) % 1000)
			var previewed := preview.has(cell)
			if previewed and not paint_objects: tile = brush
			var rect := _rect(cell, unit)
			var tint := Color(1, 1, 1, 0.7) if previewed else Color.WHITE
			var base := default_tile if tile <= 0 else tile
			if atlas != null and base >= 1 and base <= 300 and (tile > 0 or icons.has(tile)):
				var index := base - 1
				draw_texture_rect_region(atlas, rect, Rect2(Vector2((index % 20) * 32, (index / 20) * 32), Vector2(32, 32)), tint)
			else:
				draw_rect(rect, Color("243449") if (x + y) % 2 == 0 else Color("1c2c3e"))
				if zoom >= 0.9: draw_string(ThemeDB.fallback_font, rect.position + Vector2(2, unit * 0.65), str(tile), HORIZONTAL_ALIGNMENT_LEFT, -1, clampi(int(12 * zoom), 9, 18), Color("9aacc1"))
			if tile <= 0 and icons.has(tile): draw_texture_rect(icons[tile], rect, false, tint)
			if previewed: draw_rect(rect, Tokens.tint(Tokens.ACCENT, 0.25))


## The secret overlay: a big S over the tile of a cell the search looks for (a number above 2999, red) or has found (2000 to
## 2999, orange).
func _draw_secrets(lo: Vector2i, hi: Vector2i, unit: float) -> void:
	for x in range(lo.x, hi.x):
		for y in range(lo.y, hi.y):
			var number := absi(_tile(Vector2i(x, y)))
			if number > 1999: _draw_secret(_rect(Vector2i(x, y), unit), number > 2999)


func _draw_secret(rect: Rect2, hidden: bool) -> void:
	var size_of_s := clampi(int(rect.size.y * 0.9), 10, 64)
	var colour := Color("ff3b30") if hidden else Color("ff9f0a")
	var font := ThemeDB.fallback_font
	var width := font.get_string_size("S", HORIZONTAL_ALIGNMENT_LEFT, -1, size_of_s).x
	var at := rect.position + Vector2((rect.size.x - width) / 2.0, rect.size.y * 0.5 + size_of_s * 0.36)
	draw_string_outline(font, at, "S", HORIZONTAL_ALIGNMENT_LEFT, -1, size_of_s, maxi(3, size_of_s / 6), Color(0, 0, 0, 0.9))
	draw_string(font, at, "S", HORIZONTAL_ALIGNMENT_LEFT, -1, size_of_s, colour)


## The object layer over the floor: tiles from the atlas, building pictures on the cell's lower right, icons in the cell.
func _draw_objects(lo: Vector2i, hi: Vector2i, unit: float) -> void:
	if objects.size() != SIDE * SIDE: return
	var preview: Dictionary = {}
	if paint_objects:
		for cell in (_stroke.cells if _stroke.active else _shape): preview[cell] = true
	for x in range(lo.x, hi.x):
		for y in range(lo.y, hi.y):
			var cell := Vector2i(x, y)
			var value := int(objects[x * SIDE + y])
			if preview.has(cell): value = object_brush
			if value == 0: continue
			var rect := _rect(cell, unit)
			var tint := Color(1, 1, 1, 0.7) if preview.has(cell) else Color.WHITE
			if object_art.get(value) != null:
				var art: Texture2D = object_art[value]
				if value > 0:
					var drawn := art.get_size() * zoom
					draw_texture_rect(art, Rect2(rect.end - drawn, drawn), false, tint)
				else:
					draw_texture_rect(art, rect, false, tint)
			else:
				draw_rect(rect.grow(-unit * 0.15), Color(0.95, 0.55, 0.2, 0.35))
				draw_rect(rect.grow(-unit * 0.15), Color(0.95, 0.55, 0.2), false, 1.0)
				if zoom >= 0.9: draw_string(ThemeDB.fallback_font, rect.position + Vector2(2, unit * 0.65), str(value), HORIZONTAL_ALIGNMENT_LEFT, -1, clampi(int(11 * zoom), 8, 16), Color("f0c58a"))


## The rectangle a region covers, in cells.
static func region_rectangle(area: Dictionary) -> Rect2i:
	return Rect2i(int(area.first_x), int(area.first_y), int(area.last_x) - int(area.first_x) + 1, int(area.last_y) - int(area.first_y) + 1)


## A press of the Region tool: on the border of the chosen region it resizes it,
## inside any region it moves it, on empty floor it draws a new one.
func _begin_region_drag(cell: Vector2i) -> void:
	var chosen: Dictionary = {}
	for area in regions:
		if int(area.slot) == selected_region: chosen = area
	if not chosen.is_empty():
		var rect := region_rectangle(chosen)
		if rect.has_point(cell):
			var edges := Vector2i.ZERO
			if cell.x == rect.position.x: edges.x = -1
			elif cell.x == rect.end.x - 1: edges.x = 1
			if cell.y == rect.position.y: edges.y = -1
			elif cell.y == rect.end.y - 1: edges.y = 1
			var interior := rect.size.x > 2 and rect.size.y > 2
			var resize := edges != Vector2i.ZERO and interior
			_region_drag = {"mode": "resize" if resize else "move", "slot": selected_region, "anchor": cell, "origin": rect, "edges": edges}
			return
	for area in regions:
		if region_rectangle(area).has_point(cell): return
	_region_drag = {"mode": "draw", "slot": -1, "anchor": cell, "origin": Rect2i(cell, Vector2i.ONE)}


func _drag_region(cell: Vector2i) -> void:
	var anchor: Vector2i = _region_drag.anchor
	var origin: Rect2i = _region_drag.origin
	var rect := origin
	match _region_drag.mode:
		"draw":
			var low := Vector2i(mini(anchor.x, cell.x), mini(anchor.y, cell.y))
			var high := Vector2i(maxi(anchor.x, cell.x), maxi(anchor.y, cell.y))
			rect = Rect2i(low, high - low + Vector2i.ONE)
		"move":
			var delta := cell - anchor
			delta.x = clampi(delta.x, -origin.position.x, SIDE - origin.end.x)
			delta.y = clampi(delta.y, -origin.position.y, SIDE - origin.end.y)
			rect = Rect2i(origin.position + delta, origin.size)
		"resize":
			var edges: Vector2i = _region_drag.edges
			var low := origin.position
			var high := origin.end - Vector2i.ONE
			if edges.x < 0: low.x = mini(cell.x, high.x)
			elif edges.x > 0: high.x = maxi(cell.x, low.x)
			if edges.y < 0: low.y = mini(cell.y, high.y)
			elif edges.y > 0: high.y = maxi(cell.y, low.y)
			rect = Rect2i(low, high - low + Vector2i.ONE)
	region_dragged.emit(int(_region_drag.slot), rect)
	if int(_region_drag.slot) < 0: _region_drag["slot"] = -2


## A dashed rectangle, because regions are drawn apart from the floor.
func _dashed(rect: Rect2, color: Color) -> void:
	for edge in [[rect.position, Vector2(rect.end.x, rect.position.y)], [Vector2(rect.position.x, rect.end.y), rect.end], [rect.position, Vector2(rect.position.x, rect.end.y)], [Vector2(rect.end.x, rect.position.y), rect.end]]:
		var along: Vector2 = edge[1] - edge[0]
		var length := along.length()
		if length < 1.0: continue
		var step := along / length
		var at := 0.0
		while at < length:
			draw_line(edge[0] + step * at, edge[0] + step * minf(at + 6.0, length), color, 1.5)
			at += 10.0


## A label on a small dark plate, placed with its lower left at `at`.
func _plate(at: Vector2, text: String, ink: Color, edge := Color.TRANSPARENT) -> void:
	var font: Font = get_theme_font("mono", "EditorTokens")
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 10.0
	var plate := Rect2(at - Vector2(0, 15), Vector2(width, 15))
	draw_rect(plate, Tokens.tint(Tokens.INK, 0.82))
	if edge.a > 0.0: draw_rect(plate, edge, false, 1.0)
	draw_string(font, plate.position + Vector2(5, 11), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ink)


func _draw_regions(unit: float) -> void:
	for area in regions:
		var a := Vector2(int(area.first_x), int(area.first_y))
		var b := Vector2(int(area.last_x) + 1, int(area.last_y) + 1)
		if a.x < 0 or a.y < 0 or b.x <= a.x or b.y <= a.y or b.x > SIDE or b.y > SIDE: continue
		var rect := Rect2(pan + a * unit, (b - a) * unit)
		var chosen := int(area.slot) == selected_region
		_dashed(rect, Tokens.tint(Tokens.REGION, 1.0 if chosen else 0.8))
		if chosen: draw_rect(rect, Tokens.tint(Tokens.REGION, 0.1))
		if unit >= 10.0: _plate(rect.position + Vector2(2, rect.size.y - 2), _region_text(area), Tokens.REGION, Tokens.tint(Tokens.REGION, 0.5))


## What a region does: the story it starts or the battles it draws.
static func _region_text(area: Dictionary) -> String:
	for index in range(area.scripts.size()):
		if int(area.script_chances[index]) != 0: return "R%d · Story %d · %d%%" % [int(area.slot), int(area.scripts[index]), int(area.script_chances[index])]
	return "R%d · battles %d–%d · %d in 10000" % [int(area.slot), int(area.battle_min), int(area.battle_max), int(area.encounter_chance)]


func _draw_triggers(unit: float) -> void:
	var groups: Dictionary = {}
	for trigger in triggers:
		var cell := Vector2i(int(trigger.x), int(trigger.y))
		if not groups.has(cell): groups[cell] = []
		groups[cell].append(trigger)
	for cell in groups:
		var here: Array = groups[cell]
		var live := here.any(func(trigger): return trigger.active)
		var dim := here.all(func(trigger): return int(trigger.chance) <= 0 or trigger.get("shadowed", false))
		var at := pan + (Vector2(cell) + Vector2(0.5, 0.5)) * unit
		var colour := Tokens.TRIGGER if live else (Tokens.DIM if dim else Tokens.INFO)
		draw_arc(at, unit * 0.3, 0.0, TAU, 20, colour, 2.0, true)
		if here.any(func(trigger): return trigger.get("shadowed", false)): draw_line(at - Vector2(1, 1) * unit * 0.2, at + Vector2(1, 1) * unit * 0.2, colour, 1.5)
		if unit >= 12.0:
			var names := here.map(func(trigger): return "W%d" % int(trigger.slot))
			_plate(at + Vector2(unit * 0.3, -unit * 0.2), " · ".join(names), colour if live else Tokens.MUTED)


func _draw_starts(unit: float) -> void:
	for start in stage_starts:
		var cell := Vector2i(int(start.x), int(start.y))
		if not _valid(cell): continue
		var at := pan + (Vector2(cell) + Vector2(0.5, 0.5)) * unit
		var radius := unit * 0.32
		var shape := PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius, 0), at + Vector2(0, radius), at + Vector2(-radius, 0)])
		draw_colored_polygon(shape, Tokens.START)
		draw_polyline(PackedVector2Array([shape[0], shape[1], shape[2], shape[3], shape[0]]), Tokens.INK, 1.0)
		if int(start.id) == active_stage and unit >= 10.0: _plate(at + Vector2(unit * 0.5, -unit * 0.4), "Stage %d starts here" % int(start.id) if tool != "start" else "Stage %d · %s" % [int(start.id), str(start.name)], Tokens.START, Tokens.tint(Tokens.START, 0.5))
	if tool == "start" and _valid(hover_cell):
		var ghost := pan + (Vector2(hover_cell) + Vector2(0.5, 0.5)) * unit
		var span := unit * 0.32
		draw_colored_polygon(PackedVector2Array([ghost + Vector2(0, -span), ghost + Vector2(span, 0), ghost + Vector2(0, span), ghost + Vector2(-span, 0)]), Tokens.tint(Tokens.START, 0.5))
		_plate(ghost + Vector2(unit * 0.6, unit * 0.6), "move to %d, %d" % [hover_cell.x, hover_cell.y], Tokens.TEXT, Tokens.LINE2)
