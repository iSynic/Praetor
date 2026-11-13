extends HBoxContainer
## Maps: the floor of one map with its triggers, regions and stage starts; the
## tools that paint the floor and place triggers and stage starts; and the
## inspector for the cell, the map, its regions and the stages. Its interior is
## built here from src/maps and the shared widgets.
const ChooseTileDialog = preload("res://src/dialogs/choose_tile_dialog.gd")
const AddMapDialog = preload("res://src/dialogs/add_map_dialog.gd")
const ConfirmDialog = preload("res://src/widgets/confirm_dialog.gd")
const MapCanvas = preload("res://src/map_canvas.gd")
const MapInspector = preload("res://src/maps/map_inspector.gd")
const MapMinimap = preload("res://src/maps/map_minimap.gd")
const MapSidebar = preload("res://src/maps/map_sidebar.gd")
const MapToolbar = preload("res://src/maps/map_toolbar.gd")
const Glyph = preload("res://src/widgets/glyph.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

## The zoom levels of the 1×, 2× and 3× buttons, in the canvas's own scale (1.0 is 32 px a cell).
const ZOOMS := {1: 0.5, 2: 1.0, 3: 1.5}
const OVERLAYS := [["floor", "Floor"], ["objects", "Objects"], ["triggers", "Walking triggers"], ["regions", "Regions"], ["starts", "Stage starts"], ["secrets", "Secret cells"]]

var shell: Control
var map_id := 0
var canvas := MapCanvas.new()
var toolbar := MapToolbar.new()
var sidebar := MapSidebar.new()
var inspector := MapInspector.new()
var minimap := MapMinimap.new()
var choose_dialog := ChooseTileDialog.new()
var add_map_dialog := AddMapDialog.new()
var remove_map_dialog := ConfirmDialog.new()
var remove_dialog := ConfirmDialog.new()
## What is known of each map: its walking triggers, and the terrain of those visited.
var counts: Dictionary = {}
var terrains: Dictionary = {}
var picture := 0
var tile_colors: Dictionary = {}
var _counted := ""
var _trigger_cache: Dictionary = {}
var _cache_revision := -1
var _programs: Dictionary = {}
var _proposing := false
var _choose_for_cell := false
var _removing := -1
var _layers := {"floor": true, "objects": true, "triggers": true, "regions": true, "starts": true, "secrets": true}
## What the paint tools write: the "floor" or the "object" layer.
var paint_target := "floor"
var _zoom_buttons: Dictionary = {}
var _grid_toggle := CheckButton.new()
var _overlays := MenuButton.new()
var _hud_cell := Label.new()
var _hud_detail := Label.new()
var _minimap_title := Label.new()
var _ready_to_draw := false
var _hud_info: Control


func _init() -> void:
	add_theme_constant_override("separation", 12)
	var left := ScrollContainer.new()
	left.custom_minimum_size.x = 262
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sidebar)
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(left)
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 8)
	add_child(centre)
	centre.add_child(toolbar)
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.custom_minimum_size = Vector2(300, 200)
	stack.clip_contents = true
	centre.add_child(stack)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_child(canvas)
	_build_hud(stack)
	inspector.custom_minimum_size.x = 326
	add_child(inspector)


func _hud_panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HudPanel"
	parent.add_child(panel)
	return panel


func _build_hud(stack: Control) -> void:
	# Zoom, grid and overlays, over the canvas's top right.
	var controls := _hud_panel(stack)
	controls.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	controls.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	controls.offset_top = 10
	controls.offset_right = -10
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	controls.add_child(row)
	var zoom_label := Label.new()
	zoom_label.theme_type_variation = &"Dim"
	zoom_label.text = "Zoom"
	row.add_child(zoom_label)
	var group := ButtonGroup.new()
	for level in ZOOMS:
		var chip := Button.new()
		chip.theme_type_variation = &"Chip"
		chip.toggle_mode = true
		chip.button_group = group
		chip.text = "%d×" % level
		chip.button_pressed = level == 1
		chip.pressed.connect(func(): canvas.zoom_to(ZOOMS[level]))
		row.add_child(chip)
		_zoom_buttons[level] = chip
	var grid_label := Label.new()
	grid_label.theme_type_variation = &"Dim"
	grid_label.text = "Grid"
	row.add_child(grid_label)
	_grid_toggle.button_pressed = true
	_grid_toggle.toggled.connect(func(on): shell.settings.set_value("grid", on))
	row.add_child(_grid_toggle)
	_overlays.flat = true
	_overlays.focus_mode = Control.FOCUS_NONE
	var popup := _overlays.get_popup()
	for entry in OVERLAYS:
		popup.add_check_item(entry[1])
		popup.set_item_checked(popup.item_count - 1, true)
	popup.hide_on_checkable_item_selection = false
	popup.index_pressed.connect(func(index): set_layer(OVERLAYS[index][0], not _layers[OVERLAYS[index][0]]))
	row.add_child(_overlays)
	# What is under the cursor, over the canvas's lower left.
	var info := _hud_panel(stack)
	_hud_info = info
	info.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info.offset_left = 10
	info.offset_bottom = -10
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 4)
	info.add_child(lines)
	_hud_cell.theme_type_variation = &"Strong"
	lines.add_child(_hud_cell)
	_hud_detail.theme_type_variation = &"MonoDim"
	lines.add_child(_hud_detail)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 12)
	for entry in [["Walking trigger", Tokens.TRIGGER], ["Region", Tokens.REGION], ["Stage start", Tokens.START], ["Selected", Tokens.SELECTED]]:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 4)
		var dot := Glyph.new()
		dot.glyph = "dot"
		dot.extent = 10.0
		dot.color = entry[1]
		item.add_child(dot)
		var name := Label.new()
		name.theme_type_variation = &"Dim"
		name.add_theme_font_size_override("font_size", 11)
		name.text = entry[0]
		item.add_child(name)
		legend.add_child(item)
	lines.add_child(legend)
	# The map in miniature, over the lower right.
	var mini := _hud_panel(stack)
	mini.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	mini.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mini.grow_vertical = Control.GROW_DIRECTION_BEGIN
	mini.offset_right = -10
	mini.offset_bottom = -10
	var mini_column := VBoxContainer.new()
	mini_column.add_theme_constant_override("separation", 4)
	mini.add_child(mini_column)
	_minimap_title.theme_type_variation = &"Dim"
	_minimap_title.add_theme_font_size_override("font_size", 11)
	mini_column.add_child(_minimap_title)
	mini_column.add_child(minimap)


func setup(owner_shell: Control) -> void:
	shell = owner_shell
	shell.name_node("MapCanvas", canvas)
	toolbar.register(shell)
	inspector.setup(shell)
	shell.add_child(choose_dialog)
	choose_dialog.name = "ChooseTileDialog"
	remove_map_dialog.name = "RemoveMapDialog"
	remove_map_dialog.tone = "err"
	remove_map_dialog.custom_action.connect(func(action): if action == "remove": shell.guard(_remove_map_now))
	if remove_map_dialog.get_parent() == null: shell.add_child(remove_map_dialog)
	add_map_dialog.setup(shell)
	add_map_dialog.name = "AddMapDialog"
	if add_map_dialog.get_parent() == null: shell.add_child(add_map_dialog)
	shell.add_child(remove_dialog)
	remove_dialog.name = "RemoveDialog"
	remove_dialog.tone = "err"
	remove_dialog.message = "Remove unplaces the trigger's header and clears the movement gate it owns. Disable keeps its location and steps but stops it firing."
	remove_dialog.set_note("Remove is one undo step.")
	remove_dialog.add_button("Disable instead", "secondary", "disable", true)
	remove_dialog.add_button("Remove", "danger", "remove")
	remove_dialog.add_button("Cancel", "primary", "cancel")
	remove_dialog.custom_action.connect(_remove_answered)
	toolbar.tool_changed.connect(_tool_changed)
	toolbar.new_at_cell_requested.connect(func(): _propose(true))
	toolbar.open_steps_requested.connect(_open_slot_steps)
	toolbar.choose_tile_requested.connect(func(): _choose(false))
	toolbar.tile_id.value_changed.connect(_brush_changed)
	toolbar.slot.value_changed.connect(func(value): canvas.active_slot = int(value); canvas.queue_redraw())
	toolbar.stage.item_selected.connect(func(_index): _stage_picked())
	sidebar.map_requested.connect(func(id): if id != map_id: shell.guard(select_map.bind(id)))
	sidebar.tile_chosen.connect(_palette_chose)
	sidebar.target_changed.connect(_target_changed)
	sidebar.add_map_requested.connect(_add_map)
	sidebar.folder_requested.connect(func(): shell._pick_folder("installation"))
	add_map_dialog.map_added.connect(func(id): shell.guard(select_map.bind(id)))
	toolbar.building_requested.connect(func(): _object_brush_from("picture"))
	toolbar.icon_requested.connect(func(): _object_brush_from("icon"))
	inspector.object_changed.connect(func(value): shell.guard(object_edit.bind(value)))
	inspector.secret_changed.connect(func(state): shell.guard(secret_edit.bind(state)))
	inspector.object_pick_requested.connect(func(kind): shell.resource_picker.show_for(kind, 0, "Object of cell %d, %d" % [canvas.selected_cell.x, canvas.selected_cell.y], func(id): _object_chosen(kind, id, func(value): shell.guard(object_edit.bind(value)))))
	sidebar.layer_toggled.connect(func(layer, on): set_layer(layer, on, false))
	canvas.selected.connect(cell_selected)
	canvas.sampled.connect(func(tile): toolbar.tile_id.value = tile)
	canvas.stroke_requested.connect(func(cells): paint_stroke(cells))
	canvas.program_requested.connect(func(id): shell.guard(shell._open_map_program.bind(id)))
	canvas.tool_clicked.connect(_tool_clicked)
	canvas.hovered.connect(_hovered)
	canvas.view_changed.connect(_view_changed)
	minimap.center_requested.connect(func(cell): canvas.center_on(cell))
	choose_dialog.tile_chosen.connect(_tile_picked)
	inspector.choose_tile_requested.connect(func(): _choose(true))
	inspector.reveal_requested.connect(func(cell): canvas.center_on(cell))
	inspector.callers_requested.connect(func(trigger): shell.find_uses("walking", trigger))
	inspector.remove_requested.connect(ask_remove)
	inspector.region_chosen.connect(select_region)
	inspector.region_changed.connect(region_edit)
	inspector.region_removed.connect(func(slot): region_edit(slot, {"remove": true}))
	inspector.region_new.connect(new_region)
	inspector.land_changed.connect(land_edit)
	canvas.region_dragged.connect(_region_dragged)
	canvas.region_drag_ended.connect(func(): _drawing = -1)
	inspector.open_program.connect(func(family, id): shell.guard(open_program.bind(family, id)))
	inspector.create_confirmed.connect(func(): _proposing = false; await shell.placement_ui.create())
	inspector.create_cancelled.connect(func(): _propose(false))
	inspector.tab_changed.connect(func(tab): if tab == "stage": show_stages())
	shell.settings.changed.connect(func(key): if key == "grid": _grid_changed())
	canvas.show_grid = bool(shell.settings.get_value("grid"))
	_grid_toggle.set_pressed_no_signal(canvas.show_grid)
	shell.header.show_grid(canvas.show_grid)
	_ready_to_draw = true
	set_layer("floor", true)
	_brush_changed(toolbar.tile_id.value)


## Commands of the Map menu and its keys.
func command(name: String) -> void:
	var what := name.trim_prefix("map:")
	if what in MapToolbar.NAMES: toolbar.select_tool(what)
	elif what == "grid": shell.settings.set_value("grid", not canvas.show_grid)
	elif what == "new": _propose(true)
	elif what == "choose_floor": _choose(false)
	elif what == "add_map": _add_map()
	elif what == "remove_map": shell.guard(_remove_map)
	elif what.begins_with("zoom:"): canvas.zoom_to(ZOOMS[int(what.trim_prefix("zoom:"))])


func list_maps(summary: Dictionary) -> void:
	var key := str(summary.get("path", ""))
	if key != _counted:
		counts.clear()
		terrains.clear()
		_counted = key
	_refresh_list()


func _refresh_list() -> void:
	if shell == null: return
	sidebar.show_maps(int(shell.summary.get("maps", 0)), counts, terrains, map_id)


func restore_choice() -> void:
	if shell != null: sidebar.maps.select(map_id)


func select_map(id: int) -> void:
	if shell._loading: return
	map_id = id
	await show_map()


func show_map() -> void:
	var response: Dictionary = await shell.request_backend({"op": "map", "id": map_id})
	if not response.get("ok", false): return
	var same: bool = canvas.floor_values.size() > 0 and map_id == _shown_map
	_shown_map = map_id
	canvas.set_map(response.result.floor, same)
	canvas.objects = response.result.get("objects", [])
	canvas.triggers = response.result.get("triggers", [])
	_saved_regions = response.result.get("regions", [])
	_saved_land = response.result.get("land", {}) if response.result.get("land") != null else {}
	canvas.regions = _with_region_drafts(_saved_regions)
	counts[map_id] = canvas.triggers.size()
	await load_artwork()
	await _load_object_art()
	_after_map()
	await _show_cell()
	await _count_other_maps()


var _shown_map := -1
var _saved_regions: Array = []
var _saved_land: Dictionary = {}
var _drawing := -1


## Everything that follows from the map having changed.
func _after_map() -> void:
	_proposing = false
	toolbar.show_stages(shell.summary.get("stages", []), canvas.active_stage)
	refresh_starts()
	sidebar.show_counts(canvas.triggers.size(), canvas.regions.size(), canvas.stage_starts.size())
	_refresh_list()
	_minimap_title.text = "Map %d · overview" % map_id
	minimap.show_floor(canvas.floor_values, tile_colors, canvas.default_tile)
	_view_changed()
	_show_map_tab()
	inspector.show_regions(canvas.regions, canvas.selected_region)
	show_stages()
	canvas.queue_redraw()
	_hovered(Vector2i(-1, -1))


## The other maps' trigger counts, read once per project for the list.
func _count_other_maps() -> void:
	for id in range(int(shell.summary.get("maps", 0))):
		if id == map_id or counts.has(id): continue
		await triggers_of(id)
	_refresh_list()


## The walking triggers placed on a map, read once for each state of the project.
func triggers_of(id: int) -> Array:
	if _cache_revision != shell.bridge.revision:
		_trigger_cache.clear()
		_cache_revision = shell.bridge.revision
	if id == map_id and not canvas.floor_values.is_empty():
		_trigger_cache[id] = canvas.triggers
	if not _trigger_cache.has(id):
		var response: Dictionary = await shell.request_backend({"op": "map", "id": id})
		_trigger_cache[id] = response.result.get("triggers", []) if response.get("ok", false) else []
		counts[id] = _trigger_cache[id].size()
	return _trigger_cache[id]


## Loads the floor atlas and the masked icons of the map's terrain; without
## them the canvas shows numbered placeholders.
func load_artwork() -> void:
	if shell.summary.is_empty() or shell.bridge.busy: return
	var response: Dictionary = await shell.request_backend({"op": "artwork", "map": map_id, "installation": shell.ui("Installation").text})
	canvas.atlas = null
	sidebar.palette.atlas = null
	canvas.icons.clear()
	canvas.default_tile = 0
	tile_colors.clear()
	var info := "numeric placeholders"
	if response.get("ok", false) and response.result.get("status") == "available":
		var image := Image.load_from_file(str(response.result.png).replace("\\\\?\\", ""))
		if image != null:
			var texture := ImageTexture.create_from_image(image)
			canvas.atlas = texture
			sidebar.palette.atlas = texture
			_average_colors(image)
		canvas.default_tile = int(response.result.default_tile) if response.result.get("default_tile") != null else 0
		for key in response.result.get("icons", {}):
			var icon_image := Image.load_from_file(str(response.result.icons[key].png).replace("\\\\?\\", ""))
			if icon_image != null: canvas.icons[int(key)] = ImageTexture.create_from_image(icon_image)
		terrains[map_id] = int(response.result.terrain)
		picture = int(response.result.picture)
		info = "terrain %d · floor" % int(response.result.terrain)
		if not response.result.get("warnings", []).is_empty(): info += " · " + "; ".join(response.result.warnings)
	else:
		picture = 0
		info = "numeric placeholders · " + str(response.get("result", {}).get("reason", shell._error(response)))
	sidebar.palette.icons = canvas.icons.duplicate()
	sidebar.show_icons_available(not canvas.icons.is_empty())
	sidebar.show_artwork(canvas.atlas != null, shell.folder.is_empty(), not OS.has_feature("template"))
	_tile_note = info
	_brush_changed(toolbar.tile_id.value)
	canvas.queue_redraw()
	sidebar.palette.queue_redraw()


var _tile_note := ""


## One colour per tile of the atlas, for the minimap.
func _average_colors(image: Image) -> void:
	for index in range(300):
		var piece := image.get_region(Rect2i((index % 20) * 32, (index / 20) * 32, 32, 32))
		piece.resize(1, 1, Image.INTERPOLATE_BILINEAR)
		tile_colors[index + 1] = piece.get_pixel(0, 0)


func _brush_changed(value: float) -> void:
	if not _ready_to_draw: return
	var tile := int(value)
	canvas.brush = tile
	canvas.object_brush = tile
	if paint_target == "object":
		var kind := "nothing" if tile == 0 else ("building %d · picture %d" % [tile, 23000 + tile] if tile > 0 else "icon %d" % -tile)
		sidebar.show_tile(tile, "object · " + kind)
		canvas.queue_redraw()
		return
	var kind := "floor" if tile >= 1 and tile <= 300 else ("special icon" if canvas.icons.has(tile) else "not in the atlas")
	sidebar.show_tile(tile, "%s · %s" % [_tile_note.get_slice(" · ", 0), kind] if not _tile_note.is_empty() else kind)
	canvas.queue_redraw()


func _palette_chose(tile: int, _alt: bool) -> void:
	toolbar.tile_id.value = tile


## The palette's tab says what the paint tools write.
func _target_changed(target: String) -> void:
	paint_target = target
	canvas.paint_objects = target == "object"
	toolbar.object_mode = target == "object"
	_brush_changed(toolbar.tile_id.value)


## The art of the object values that the atlas does not draw: building pictures and icons.
func _load_object_art() -> void:
	canvas.object_art.clear()
	var pictures: Dictionary = {}
	var icons: Dictionary = {}
	for value in canvas.objects:
		var number := int(value)
		if number > 0: pictures[number] = true
		elif number < 0: icons[number] = true
	if icons.size() > 0: await shell.references.fetch(icons.keys().map(func(v): return -int(v)))
	for number in icons: canvas.object_art[number] = shell.references.icon(-int(number))
	for number in pictures: canvas.object_art[number] = _white_left_out(await shell.references.picture(23000 + int(number)))
	canvas.queue_redraw()


## The game copies a building with the transfer mode that leaves white out, so the white of its picture is clear.
func _white_left_out(texture: Texture2D) -> Texture2D:
	if texture == null: return null
	var image := texture.get_image()
	image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.996 and pixel.g > 0.996 and pixel.b > 0.996: image.set_pixel(x, y, Color(1, 1, 1, 0))
	return ImageTexture.create_from_image(image)


## Chooses the brush from the game's pictures or icons.
func _object_brush_from(kind: String) -> void:
	var current := int(toolbar.tile_id.value)
	var start := -current if kind == "icon" and current < 0 else (23000 + current if kind == "picture" and current > 0 else 0)
	shell.resource_picker.show_for(kind, start, "Object layer", func(id): _object_chosen(kind, id, func(value): toolbar.tile_id.value = value))


## The object value a chosen icon or picture stands for, or a note why a picture cannot be a building.
func _object_chosen(kind: String, id: int, use: Callable) -> void:
	if kind == "icon": use.call(-id)
	elif id > 23000 and id <= 32767: use.call(id - 23000)
	else: shell.status("A building is a picture numbered 23001 or more", "warn")


## Asks before the last map is removed, and says what still names it when something does.
func _remove_map() -> void:
	if shell.summary.is_empty(): return
	var last := int(shell.summary.get("maps", 0)) - 1
	if last < 1:
		shell.status("A scenario holds at least one map", "warn")
		return
	var response: Dictionary = await shell.request_backend({"op": "map_references", "map": last})
	if not response.get("ok", false): return
	var named: Array = response.result.named
	remove_map_dialog.clear_buttons()
	if named.is_empty():
		remove_map_dialog.heading = "Remove Map %d?" % last
		remove_map_dialog.message = "Only the last map can be removed, because the maps after another would change their numbers. Nothing names Map %d, so its floor, objects, walking triggers and regions go with it." % last
		remove_map_dialog.set_details([["Map", "Map %d" % last]])
		remove_map_dialog.set_note("Removing is one undo step.")
		remove_map_dialog.add_button("Remove", "danger", "remove")
		remove_map_dialog.add_button("Cancel", "primary", "cancel")
	else:
		remove_map_dialog.heading = "Map %d is still named" % last
		remove_map_dialog.message = "Change what names it first. The map stays as it is."
		remove_map_dialog.set_details(named.slice(0, 8).map(func(line): return ["", str(line)]))
		remove_map_dialog.set_note("" if named.size() <= 8 else "%d more are not listed." % (named.size() - 8))
		remove_map_dialog.add_button("Close", "primary", "cancel")
	remove_map_dialog.popup_centered()


func _remove_map_now() -> void:
	var last := int(shell.summary.get("maps", 0)) - 1
	var response: Dictionary = await shell.request_backend({"op": "apply", "expected_revision": shell.bridge.revision, "edits": [{"kind": "remove_map", "map": last}]})
	if not response.get("ok", false): return
	await shell._set_summary(response.result)
	shell.status("Map %d removed · one undo step" % last)
	await select_map(mini(map_id, last - 1))


## Opens Add a map, which offers a copy of the map in view and the floor most of it is made of.
func _add_map() -> void:
	if shell.summary.is_empty(): return
	var counts_of: Dictionary = {}
	for value in canvas.floor_values: counts_of[int(value)] = int(counts_of.get(int(value), 0)) + 1
	var common := 0
	var best := 0
	for value in counts_of:
		if int(value) >= 1 and int(value) <= 300 and int(counts_of[value]) > best:
			best = int(counts_of[value])
			common = int(value)
	await add_map_dialog.show_for(map_id, common)


## Sets the object of the selected cell as one undo step.
func object_edit(value: int) -> void:
	var cell := canvas.selected_cell
	if cell.x < 0: return
	await paint_stroke([cell], value, "object")
	await show_map()


## Sets the secret state of the selected floor cell: "normal", "hidden" (3000 added to its number) or "revealed" (2000 added,
## which is what a search leaves).
func secret_edit(state: String) -> void:
	var cell := canvas.selected_cell
	if cell.x < 0: return
	var value := int(canvas.floor_values[cell.x * 90 + cell.y])
	var sign := -1 if value < 0 else 1
	var number := absi(value) % 1000 if absi(value) > 1999 else absi(value)
	number += {"normal": 0, "hidden": 3000, "revealed": 2000}[state]
	if sign * number == value: return
	await paint_stroke([cell], sign * number, "floor")
	await show_map()


## The thumbnail of a tile, from the atlas.
func thumb(tile: int) -> Texture2D:
	if canvas.atlas == null or tile < 1 or tile > 300: return canvas.icons.get(tile)
	var texture := AtlasTexture.new()
	texture.atlas = canvas.atlas
	texture.region = Rect2(Vector2(((tile - 1) % 20) * 32, ((tile - 1) / 20) * 32), Vector2(32, 32))
	return texture


# ── layers, view and what is under the cursor ──

## Shows or hides a layer on the canvas, in the sidebar and in the Overlays menu.
func set_layer(layer: String, on: bool, update_toggle := true) -> void:
	_layers[layer] = on
	match layer:
		"floor": canvas.show_floor = on
		"objects": canvas.show_objects = on
		"triggers": canvas.show_triggers = on
		"regions": canvas.show_regions = on
		"starts": canvas.show_starts = on
		"secrets": canvas.show_secrets = on
	if update_toggle: sidebar.set_layer(layer, on)
	var popup := _overlays.get_popup()
	for index in range(OVERLAYS.size()): popup.set_item_checked(index, _layers[OVERLAYS[index][0]])
	_overlays.text = "Overlays %d/%d" % [_layers.values().count(true), OVERLAYS.size()]
	canvas.queue_redraw()


func _grid_changed() -> void:
	canvas.show_grid = bool(shell.settings.get_value("grid"))
	shell.header.show_grid(canvas.show_grid)
	_grid_toggle.set_pressed_no_signal(canvas.show_grid)
	canvas.queue_redraw()


func _view_changed() -> void:
	# In a narrow canvas the reading under the cursor would cover the map; the status bar still has it.
	if _hud_info != null: _hud_info.visible = canvas.size.x >= 640.0
	minimap.view = canvas.visible_cells()
	minimap.queue_redraw()
	for level in _zoom_buttons: _zoom_buttons[level].set_pressed_no_signal(is_equal_approx(canvas.zoom, ZOOMS[level]))


func _hovered(cell: Vector2i) -> void:
	var at := cell if cell.x >= 0 else canvas.selected_cell
	if at.x < 0:
		_hud_cell.text = "Map %d" % map_id
		_hud_detail.text = "move over a cell to read it"
		shell.status_bar.show_context("Map %d · 90 × 90%s" % [map_id, (" · terrain %d" % int(terrains[map_id])) if terrains.has(map_id) else ""])
		return
	var tile := int(canvas.floor_values[at.x * 90 + at.y]) if canvas.floor_values.size() == 8100 else 0
	_hud_cell.text = "Cell %d, %d" % [at.x, at.y]
	var parts: Array[String] = ["floor %d" % tile]
	if terrains.has(map_id): parts.append("terrain %d" % int(terrains[map_id]))
	for trigger in canvas.triggers:
		if int(trigger.x) == at.x and int(trigger.y) == at.y: parts.append("W%d · %d%%" % [int(trigger.slot), int(trigger.chance)])
	_hud_detail.text = " · ".join(parts)
	shell.status_bar.show_context("Cell %d, %d · Map %d · 90 × 90%s" % [at.x, at.y, map_id, (" · terrain %d" % int(terrains[map_id])) if terrains.has(map_id) else ""])


## The pending note of the inspector and the stage starts follow the drafts.
func chrome_changed() -> void:
	if not _ready_to_draw: return
	inspector.show_pending(shell.drafts.size())
	if not canvas.floor_values.is_empty(): refresh_starts()


func refresh_starts() -> void:
	var starts: Array = []
	for row in shell.summary.get("stages", []):
		if not row.active: continue
		var start: Dictionary = shell.drafts.get("stage_start:%d" % int(row.id), row)
		if int(start.get("map", row.map)) == map_id: starts.append({"id": int(row.id), "name": row.name, "x": int(start.get("x", row.x)), "y": int(start.get("y", row.y))})
	canvas.stage_starts = starts
	toolbar.start_text.text = _start_text()
	canvas.queue_redraw()


func _start_text() -> String:
	for start in canvas.stage_starts:
		if int(start.id) == toolbar.chosen_stage(): return "%d, %d" % [int(start.x), int(start.y)]
	return "not on this map"


func _stage_picked() -> void:
	canvas.active_stage = toolbar.chosen_stage()
	shell.stages.stage_id = canvas.active_stage
	refresh_starts()
	show_stages()


func stage_chosen(id: int) -> void:
	canvas.active_stage = id
	toolbar.show_stages(shell.summary.get("stages", []), id)
	refresh_starts()
	show_stages()


func show_stages() -> void:
	inspector.show_stages(shell.summary.get("stages", []), canvas.active_stage, map_id)


func _show_map_tab() -> void:
	var tiles := {}
	for value in canvas.floor_values: tiles[int(value)] = true
	var past := 0
	for region in canvas.regions:
		if int(region.last_x) >= 90 or int(region.last_y) >= 90: past += 1
	var starts := canvas.stage_starts.map(func(start): return "Stage %d at %d, %d" % [int(start.id), int(start.x), int(start.y)])
	var look := _look()
	inspector.show_map({"map": map_id, "terrain": int(look.get("terrain", terrains.get(map_id, -1))), "limits_sight": bool(look.get("limits_sight", false)), "light": int(look.get("light", 0)), "picture": picture, "tiles": tiles.size(), "placed": canvas.triggers.size(), "objects": canvas.objects.filter(func(value): return int(value) != 0).size(),
		"regions": canvas.regions.size(), "past_edge": past, "starts_text": ", ".join(starts) if not starts.is_empty() else "none on this map"})


# ── tools ──

func _tool_changed(name: String) -> void:
	canvas.tool = name
	canvas.cancel_stroke()
	if name == "start": inspector.show_tab("stage")
	elif name == "region": inspector.show_tab("regions")
	elif name in ["trigger", "select", "erase"] and inspector.tab in ["stage", "regions"]: inspector.show_tab("cell")
	canvas.queue_redraw()


func _tool_clicked(name: String, cell: Vector2i) -> void:
	match name:
		"trigger": shell.guard(shell.placement_ui.place.bind(cell, false, false))
		"erase":
			var found := _trigger_at(cell)
			if found.is_empty(): shell.status("No walking trigger at %d, %d" % [cell.x, cell.y], "warn")
			else: ask_remove(int(found.id))
		"start":
			var stage := toolbar.chosen_stage()
			shell.stages.draft_start(stage, map_id, cell.x, cell.y)
			shell.status("Stage %d start drafted at %d, %d · Apply edits" % [stage, cell.x, cell.y])
		"region":
			var slot := -1
			for region in canvas.regions:
				if cell.x >= int(region.first_x) and cell.x <= int(region.last_x) and cell.y >= int(region.first_y) and cell.y <= int(region.last_y): slot = int(region.slot); break
			select_region(slot)


func _trigger_at(cell: Vector2i) -> Dictionary:
	for trigger in canvas.triggers:
		if int(trigger.x) == cell.x and int(trigger.y) == cell.y: return trigger
	return {}


## The regions as saved, with the unapplied edits of this map put over them.
func _with_region_drafts(saved: Array) -> Array:
	var shown: Array = saved.duplicate(true)
	for draft in shell.drafts.values():
		if draft.get("kind") != "region" or int(draft.map) != map_id: continue
		shown = shown.filter(func(region): return int(region.slot) != int(draft.slot))
		if not _is_empty(draft): shown.append(_region_of(draft))
	shown.sort_custom(func(a, b): return int(a.slot) < int(b.slot))
	return shown


static func _is_empty(draft: Dictionary) -> bool:
	return int(draft.first_y) == 0 and int(draft.first_x) == 0 and int(draft.last_y) == 0 and int(draft.last_x) == 0


static func _region_of(draft: Dictionary) -> Dictionary:
	return {"slot": int(draft.slot), "first_y": int(draft.first_y), "first_x": int(draft.first_x), "last_y": int(draft.last_y), "last_x": int(draft.last_x), "encounter_chance": int(draft.encounter_chance), "battle_min": int(draft.battle_min), "battle_max": int(draft.battle_max), "scripts": draft.scripts.map(func(v): return int(v)), "script_chances": draft.script_chances.map(func(v): return int(v)), "exclusive": bool(draft.exclusive), "avoid_chance": int(draft.avoid_chance), "avoid_sound": int(draft.avoid_sound), "avoid_dialogue": int(draft.avoid_dialogue)}


func _free_slot() -> int:
	for slot in range(20):
		if not canvas.regions.any(func(region): return int(region.slot) == slot): return slot
	return -1


## The map's tile set and sight limit: the draft over what is saved.
func _look() -> Dictionary:
	var draft: Dictionary = shell.drafts.get("map_look:%d" % map_id, {})
	if not draft.is_empty(): return {"terrain": int(draft.terrain), "limits_sight": bool(draft.limits_sight), "light": int(draft.light)}
	return _saved_land


## Changes the map's tile set or sight limit; it becomes a draft, or none when it is as saved.
func land_edit(changes: Dictionary) -> void:
	if shell.summary.is_empty() or _saved_land.is_empty(): return
	var look := _look().duplicate()
	for key in changes: look[key] = changes[key]
	var key := "map_look:%d" % map_id
	if int(look.terrain) == int(_saved_land.terrain) and bool(look.limits_sight) == bool(_saved_land.limits_sight) and int(look.light) == int(_saved_land.light): shell.drafts.erase(key)
	else: shell.drafts[key] = {"kind": "map_look", "map": map_id, "terrain": int(look.terrain), "limits_sight": bool(look.limits_sight), "light": int(look.light)}
	shell._invalidate_receipt()
	shell._update_buttons()
	_after_map()


## Changes one region: `changes` holds the fields that moved, "remove" clears it.
## The region becomes a draft of the whole region, or none when it is as saved.
func region_edit(slot: int, changes: Dictionary) -> void:
	if shell.summary.is_empty() or slot < 0 or slot > 19: return
	var region := {"slot": slot, "first_y": 0, "first_x": 0, "last_y": 3, "last_x": 3, "encounter_chance": 0, "battle_min": 0, "battle_max": 0, "scripts": [0, 0, 0], "script_chances": [0, 0, 0], "exclusive": false, "avoid_chance": 0, "avoid_sound": 0, "avoid_dialogue": 0}
	for existing in canvas.regions:
		if int(existing.slot) == slot: region = existing.duplicate(true)
	for key in changes:
		match str(key):
			"script0", "script1", "script2": region.scripts[int(str(key).substr(6))] = int(changes[key])
			"chance0", "chance1", "chance2": region.script_chances[int(str(key).substr(6))] = int(changes[key])
			"remove": pass
			_: region[key] = changes[key]
	if changes.has("remove"):
		for key in ["first_y", "first_x", "last_y", "last_x", "encounter_chance", "battle_min", "battle_max", "avoid_chance", "avoid_sound", "avoid_dialogue"]: region[key] = 0
		region.scripts = [0, 0, 0]
		region.script_chances = [0, 0, 0]
		region.exclusive = false
	var draft := {"kind": "region", "map": map_id, "slot": slot, "first_y": int(region.first_y), "first_x": int(region.first_x), "last_y": int(region.last_y), "last_x": int(region.last_x), "encounter_chance": int(region.encounter_chance), "battle_min": int(region.battle_min), "battle_max": int(region.battle_max), "scripts": region.scripts.map(func(v): return int(v)), "script_chances": region.script_chances.map(func(v): return int(v)), "exclusive": bool(region.exclusive), "avoid_chance": int(region.avoid_chance), "avoid_sound": int(region.avoid_sound), "avoid_dialogue": int(region.avoid_dialogue)}
	var key := "region:%d:%d" % [map_id, slot]
	var saved: Dictionary = {}
	for original in _saved_regions:
		if int(original.slot) == slot: saved = original
	var as_saved: bool = (saved.is_empty() and _is_empty(draft)) or (not saved.is_empty() and JSON.stringify(_region_of(draft)) == JSON.stringify(_region_of({"slot": slot, "first_y": saved.first_y, "first_x": saved.first_x, "last_y": saved.last_y, "last_x": saved.last_x, "encounter_chance": saved.encounter_chance, "battle_min": saved.battle_min, "battle_max": saved.battle_max, "scripts": saved.scripts, "script_chances": saved.script_chances, "exclusive": saved.get("exclusive", false), "avoid_chance": saved.get("avoid_chance", 0), "avoid_sound": saved.get("avoid_sound", 0), "avoid_dialogue": saved.get("avoid_dialogue", 0)})))
	if as_saved: shell.drafts.erase(key)
	else: shell.drafts[key] = draft
	canvas.regions = _with_region_drafts(_saved_regions)
	shell._invalidate_receipt()
	shell._update_buttons()
	if changes.has("remove"):
		canvas.selected_region = -1
		inspector.show_regions(canvas.regions, -1)
	elif changes.has("first_x") or changes.has("first_y") or changes.has("last_x") or changes.has("last_y") or changes.has("exclusive"):
		inspector.show_region_values(region)
	canvas.queue_redraw()
	sidebar.show_counts(canvas.triggers.size(), canvas.regions.size(), canvas.stage_starts.size())


## The first free slot gets a small region at the top left, for the fields to place.
func new_region() -> void:
	var slot := _free_slot()
	if slot < 0:
		shell.status("This map's twenty region slots are all in use", "warn")
		return
	region_edit(slot, {"first_x": 0, "first_y": 0, "last_x": 3, "last_y": 3})
	select_region(slot)


func _region_dragged(slot: int, rectangle: Rect2i) -> void:
	var target := slot
	if slot == -1:
		_drawing = _free_slot()
		if _drawing < 0:
			shell.status("This map's twenty region slots are all in use", "warn")
			return
		target = _drawing
	elif slot == -2: target = _drawing
	if target < 0: return
	region_edit(target, {"first_x": rectangle.position.x, "first_y": rectangle.position.y, "last_x": rectangle.end.x - 1, "last_y": rectangle.end.y - 1})
	if slot < 0 and canvas.selected_region != target:
		canvas.selected_region = target
		inspector.show_regions(canvas.regions, target)
		inspector.show_tab("regions")


func select_region(slot: int) -> void:
	canvas.selected_region = slot
	inspector.show_regions(canvas.regions, slot)
	if slot >= 0: inspector.show_tab("regions")
	canvas.queue_redraw()


func open_program(family: String, id: int) -> void:
	await shell.programs.open_cell_link({"family": family, "id": id})


func _open_slot_steps() -> void:
	var id: int = map_id * 100 + int(toolbar.slot.value)
	for trigger in canvas.triggers:
		if int(trigger.id) == id:
			shell.guard(shell._open_map_program.bind(id))
			return
	shell.status("This slot is unplaced; use Remove or choose a placed slot", "warn")


## One stroke is one apply, so one undo step. `tile` is the brush unless given; `layer` is the paint target unless given.
func paint_stroke(cells: Array, tile := -1000000, layer := "") -> void:
	if shell.bridge.busy or shell.summary.is_empty(): return
	var chosen := int(toolbar.tile_id.value) if tile == -1000000 else tile
	var onto := paint_target if layer.is_empty() else layer
	var edits: Array = []
	for cell in cells:
		if onto == "object": edits.append({"kind": "map_object", "map": map_id, "x": cell.x, "y": cell.y, "value": chosen})
		else: edits.append({"kind": "floor", "map": map_id, "x": cell.x, "y": cell.y, "tile": chosen})
	var response: Dictionary = await shell.request_backend({"op": "apply", "expected_revision": shell.bridge.revision, "edits": edits})
	if response.get("ok", false): await shell._set_summary(response.result); shell.status("%s stroke applied · one undo step" % ("Object" if onto == "object" else "Floor"))
	elif shell.bridge.requires_reopen:
		for edit in edits: shell.drafts["%s:%d:%d:%d" % [str(edit.kind), edit.map, edit.x, edit.y]] = edit
		shell._update_buttons()


# ── cells ──

func cell_selected(cell: Vector2i, tile: int) -> void:
	shell.placement_ui.selected = cell
	toolbar.cell_text.text = "Cell %d, %d" % [cell.x, cell.y]
	if _proposing: _proposing = false
	_show_cell()
	_hovered(Vector2i(-1, -1))


## Reads the program of every walking trigger at the selected cell and shows the cell.
func _show_cell() -> void:
	var cell := canvas.selected_cell
	if cell.x < 0 or canvas.floor_values.size() != 8100:
		inspector.show_cell(Vector2i(-1, -1), {})
		return
	var tile := int(canvas.floor_values[cell.x * 90 + cell.y])
	var object_value := int(canvas.objects[cell.x * 90 + cell.y]) if canvas.objects.size() == 8100 else 0
	var object_thumb: Texture2D = null
	var object_name := ""
	if object_value != 0:
		object_thumb = canvas.object_art.get(object_value)
		object_name = "Building %d" % object_value if object_value > 0 else "Icon %d" % -object_value
	var triggers: Array = canvas.triggers.filter(func(trigger): return int(trigger.x) == cell.x and int(trigger.y) == cell.y)
	_programs.clear()
	for trigger in triggers:
		if shell.bridge.busy: break
		var response: Dictionary = await shell.request_backend({"op": "program", "family": "walking", "id": int(trigger.id), "branch": 0})
		if response.get("ok", false): _programs[int(trigger.id)] = response.result
	var regions: Array = canvas.regions.filter(func(region): return cell.x >= int(region.first_x) and cell.x <= int(region.last_x) and cell.y >= int(region.first_y) and cell.y <= int(region.last_y))
	var starts: Array = canvas.stage_starts.filter(func(start): return int(start.x) == cell.x and int(start.y) == cell.y)
	inspector.show_cell(cell, {"map": map_id, "tile": tile, "tile_info": "terrain %d · %s" % [int(terrains.get(map_id, -1)), "floor" if tile >= 1 else "special"] if terrains.has(map_id) else "no artwork", "thumb": thumb(tile),
		"triggers": triggers, "programs": _programs, "regions": regions, "starts": starts, "proposal": _proposing,
		"object": object_value, "object_thumb": object_thumb, "object_name": object_name})


func _propose(on: bool) -> void:
	if on and canvas.selected_cell.x < 0:
		shell.status("Select a map cell first", "warn")
		return
	_proposing = on
	inspector.show_tab("cell")
	_show_cell()


func _choose(for_cell: bool) -> void:
	if for_cell and canvas.selected_cell.x < 0: return
	_choose_for_cell = for_cell
	var cell := canvas.selected_cell if for_cell else Vector2i(-1, -1)
	var current := int(canvas.floor_values[cell.x * 90 + cell.y]) if for_cell else int(toolbar.tile_id.value)
	choose_dialog.show_for(map_id, cell, current, canvas.atlas, canvas.icons, int(terrains.get(map_id, -1)), picture)


func _tile_picked(tile: int) -> void:
	if _choose_for_cell and canvas.selected_cell.x >= 0:
		shell.guard(paint_stroke.bind([{"x": canvas.selected_cell.x, "y": canvas.selected_cell.y}], tile))
	else:
		toolbar.tile_id.value = tile


# ── removing a trigger ──

## Asks before a walking trigger is unplaced; Disable keeps its steps.
func ask_remove(trigger_id: int) -> void:
	var found := {}
	for trigger in canvas.triggers:
		if int(trigger.id) == trigger_id: found = trigger
	if found.is_empty(): return
	_removing = trigger_id
	var here := canvas.triggers.filter(func(trigger): return int(trigger.x) == int(found.x) and int(trigger.y) == int(found.y) and int(trigger.id) != trigger_id)
	var program: Dictionary = _programs.get(trigger_id, {})
	var steps: Array = program.get("steps", [])
	var used := steps.filter(func(step): return int(step.opcode) != 0).size()
	var cell := "%d, %d" % [int(found.x), int(found.y)]
	remove_dialog.heading = "Remove W%d from Map %d (%s)?" % [int(found.slot), map_id, cell.replace(", ", ", ")]
	remove_dialog.set_details([["Trigger", "W%d · chance %d%s" % [int(found.slot), int(found.chance), (" · %d of %d steps" % [used, steps.size()]) if not steps.is_empty() else ""]],
		["Cell", cell + (" · shared with " + ", ".join(here.map(func(trigger): return "W%d" % int(trigger.slot))) if not here.is_empty() else "")],
		["Gate", "cleared at " + cell, Tokens.WARN]])
	remove_dialog.popup_centered()


func _remove_answered(action: String) -> void:
	var id := _removing
	_removing = -1
	var cell := Vector2i.ZERO
	for trigger in canvas.triggers:
		if int(trigger.id) == id: cell = Vector2i(int(trigger.x), int(trigger.y))
	match action:
		"remove": shell.guard(shell.placement_ui.place.bind(cell, true, false, id))
		"disable": shell.guard(shell.placement_ui.place.bind(cell, false, true, id))
