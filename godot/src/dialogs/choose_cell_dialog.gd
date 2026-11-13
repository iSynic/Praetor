extends "res://src/widgets/modal_overlay.gd"
## Choose a cell: one map with its floor and regions, a click that picks a cell, the cell's column and row,
## and the regions that hold it. The calendar uses it for the place an entry waits for the party at.
signal cell_chosen(map_id: int, cell: Vector2i)
signal none_chosen

const MapCanvas = preload("res://src/map_canvas.gd")

var canvas := MapCanvas.new()
var column := SpinBox.new()
var row := SpinBox.new()
var _shell: Control
var _map := 0
var _info := Label.new()
var _regions := Label.new()
var _use: Button
var _loading := false


func _init() -> void:
	super()
	title = "Choose a cell"
	panel_size = Vector2(820, 0)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	body.add_child(stack)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 18)
	stack.add_child(line)
	canvas.custom_minimum_size = Vector2(460, 420)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.tool = "select"
	canvas.show_triggers = false
	canvas.show_starts = false
	canvas.show_grid = true
	canvas.selected.connect(func(cell, _tile): _pick(cell))
	line.add_child(canvas)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 250
	side.add_theme_constant_override("separation", 10)
	line.add_child(side)
	var fields := HBoxContainer.new()
	fields.add_theme_constant_override("separation", 10)
	for entry in [["Column", column], ["Row", row]]:
		var cell := VBoxContainer.new()
		var caption := Label.new()
		caption.theme_type_variation = &"Dim"
		caption.text = entry[0]
		cell.add_child(caption)
		entry[1].min_value = 0
		entry[1].max_value = 89
		entry[1].custom_minimum_size.x = 90
		entry[1].value_changed.connect(func(_value): if not _loading: _pick(Vector2i(int(column.value), int(row.value)), true))
		cell.add_child(entry[1])
		fields.add_child(cell)
	side.add_child(fields)
	_info.theme_type_variation = &"MonoDim"
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_info)
	var caption := Label.new()
	caption.theme_type_variation = &"CaptionMuted"
	caption.uppercase = true
	caption.text = "Inside regions"
	side.add_child(caption)
	_regions.theme_type_variation = &"Muted"
	_regions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_regions)
	var rule := Label.new()
	rule.theme_type_variation = &"Dim"
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule.text = "The calendar leaves out a region's last row and last column."
	side.add_child(rule)
	var none := Button.new()
	none.text = "Use no cell"
	none.theme_type_variation = &"GhostButton"
	none.tooltip_text = "The entry then tests only the map and the region"
	none.pressed.connect(func(): close(); none_chosen.emit())
	side.add_child(none)
	add_button("Cancel").pressed.connect(close)
	_use = add_button("Use cell", "primary")
	_use.pressed.connect(func(): close(); cell_chosen.emit(_map, Vector2i(int(column.value), int(row.value))))


func setup(owner_shell: Control) -> void:
	_shell = owner_shell


## Opens on a map with a cell chosen, or the middle of the map when `cell` is below zero.
func show_for(map_id: int, cell: Vector2i) -> void:
	_map = map_id
	subtitle = "Map %d" % map_id
	title = "Choose a cell on Map %d" % map_id
	var response: Dictionary = await _shell.request_backend({"op": "map", "id": map_id})
	if not response.get("ok", false): return
	canvas.set_map(response.result.floor)
	canvas.regions = response.result.get("regions", [])
	canvas.atlas = null
	canvas.icons.clear()
	var art: Dictionary = await _shell.request_backend({"op": "artwork", "map": map_id, "installation": _shell.folder})
	if art.get("ok", false) and art.result.get("status") == "available":
		var image := Image.load_from_file(str(art.result.png).replace("\\\\?\\", ""))
		if image != null: canvas.atlas = ImageTexture.create_from_image(image)
		canvas.default_tile = int(art.result.default_tile) if art.result.get("default_tile") != null else 0
		for key in art.result.get("icons", {}):
			var icon_image := Image.load_from_file(str(art.result.icons[key].png).replace("\\\\?\\", ""))
			if icon_image != null: canvas.icons[int(key)] = ImageTexture.create_from_image(icon_image)
	open()
	var start := cell if cell.x >= 0 and cell.y >= 0 else Vector2i(45, 45)
	canvas.zoom = 0.5
	while canvas.size.x < 100: await get_tree().process_frame
	await get_tree().process_frame
	canvas.center_on(start)
	_pick(start, false, cell.x < 0)


func _pick(cell: Vector2i, centre := false, quiet := false) -> void:
	_loading = true
	column.value = cell.x
	row.value = cell.y
	_loading = false
	canvas.selected_cell = cell
	if centre: canvas.center_on(cell)
	canvas.queue_redraw()
	_use.text = "Use cell (%d, %d)" % [cell.x, cell.y]
	var tile := int(canvas.floor_values[cell.x * 90 + cell.y]) if canvas.floor_values.size() == 8100 else 0
	_info.text = "Floor tile %d" % tile
	var inside: Array = []
	for region in canvas.regions:
		var all_zero: bool = int(region.first_y) == 0 and int(region.first_x) == 0 and int(region.last_y) == 0 and int(region.last_x) == 0
		if all_zero: continue
		# The calendar tests the stored rectangle as the game's point-in-rectangle does: its last row and column are outside it.
		if cell.y >= int(region.first_y) and cell.y < int(region.last_y) and cell.x >= int(region.first_x) and cell.x < int(region.last_x):
			inside.append("R%d" % int(region.slot))
	_regions.text = ", ".join(inside) if not inside.is_empty() else "none"
