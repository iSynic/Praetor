extends SceneTree
## Drives the Maps workspace on the real renderer with real mouse events and
## captures it: the tools and what one stroke costs, triggers, stage starts,
## regions, the inspector's tabs and its quick edits, the Remove question and
## the Choose floor dialog. Needs CENTURIONS_PROJECT to be an imported level
## with walking triggers, CENTURIONS_INSTALLATION and CENTURIONS_CAPTURE_OUT.
var shell: Control
var canvas: Control
var out := ""
var failures: Array = []


func _initialize() -> void:
	call_deferred("run")


func settle() -> void:
	while shell.bridge.busy: await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func snapshot(name: String) -> void:
	await settle()
	var image := root.get_texture().get_image()
	if image == null or image.save_png(out.path_join(name + ".png")) != OK: failures.append(name)


func expect(passed: bool, message: String) -> void:
	if not passed: failures.append(message)


func floor_at(x: int, y: int) -> int:
	return int(canvas.floor_values[x * 90 + y])


## A mouse event at the middle of `cell`, given to the canvas as the window would.
func pointer(cell: Vector2i, pressed: Variant = null) -> void:
	var at: Vector2 = canvas.pan + (Vector2(cell) + Vector2(0.5, 0.5)) * canvas.cell_pixels()
	if pressed == null:
		var motion := InputEventMouseMotion.new()
		motion.position = at
		canvas._gui_input(motion)
	else:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.position = at
		canvas._gui_input(button)


func drag(from: Vector2i, to: Vector2i, hold := false) -> void:
	pointer(from, true)
	pointer(to)
	if not hold:
		pointer(to, false)
		await settle()


func all(node: Node, kind: String, found: Array) -> Array:
	if node.is_class(kind): found.append(node)
	for child in node.get_children(true): all(child, kind, found)
	return found


func run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Maps capture timed out"); quit(99))
	root.gui_embed_subwindows = true
	out = OS.get_environment("CENTURIONS_CAPTURE_OUT")
	if out.is_empty(): push_error("CENTURIONS_CAPTURE_OUT required"); quit(1); return
	var sizes := [Vector2i(1600, 900), Vector2i(1200, 720)]
	shell = load("res://src/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await shell.startup_completed
	canvas = shell.ui("MapCanvas")
	for dimensions in sizes:
		root.size = dimensions
		await shell._show_route(shell.ROUTES.find("Maps"))
		await shell._select_map(0)
		canvas.set_view(1.0, Vector2(16, 16))
		await map_session(dimensions)
		if dimensions.x < 1600: continue
	shell.bridge.stop()
	if failures.is_empty(): print("CENTURIONS_MAP_CAPTURES_PASSED")
	else: push_error("Map capture failures: " + str(failures))
	quit(0 if failures.is_empty() else 1)


func map_session(dimensions: Vector2i) -> void:
	var tag := "%dx%d" % [dimensions.x, dimensions.y]
	var maps: Control = shell.maps
	var live: Array = canvas.triggers.filter(func(trigger): return trigger.active)
	expect(not live.is_empty(), "The imported map must have an active walking trigger")
	var trigger: Dictionary = live[0]
	var cell := Vector2i(int(trigger.x), int(trigger.y))
	# Selecting a trigger's cell fills the inspector with its steps.
	maps.toolbar.select_tool("select")
	await drag(cell, cell)
	await settle()
	expect(maps.inspector.tab == "cell" and not maps._programs.is_empty(), "Selecting a trigger must load its program into the Cell tab")
	await snapshot(tag + "-map-cell-trigger")
	# A cell can be hidden until a search finds it (3000 added to its number), which is what a secret entrance stands on.
	var index := cell.x * 90 + cell.y
	var plain := int(canvas.floor_values[index])
	maps.inspector.secret_changed.emit("hidden")
	await settle()
	await settle()
	expect(int(canvas.floor_values[index]) == plain + 3000, "Hiding a cell adds 3000 to its number")
	# Two neighbours, one hidden and one revealed, show the overlay beside the trigger's cell.
	var neighbours := [cell + Vector2i(2, 0), cell + Vector2i(2, 1)]
	var saved: Array = neighbours.map(func(spot): return int(canvas.floor_values[spot.x * 90 + spot.y]))
	await maps.paint_stroke([neighbours[0]], saved[0] + 3000, "floor")
	await maps.paint_stroke([neighbours[1]], saved[1] + 2000, "floor")
	await settle()
	await snapshot(tag + "-map-secret")
	for number in range(2): await maps.paint_stroke([neighbours[number]], saved[number], "floor")
	maps.inspector.secret_changed.emit("normal")
	await settle()
	await settle()
	expect(int(canvas.floor_values[index]) == plain, "Showing the cell again takes the 3000 off")
	if dimensions.x < 1600:
		await snapshot(tag + "-map-compact")
		return
	# Keys and menu commands choose tools; a key means nothing in a field.
	shell._run_command("map:line")
	expect(maps.toolbar.tool == "line" and canvas.tool == "line", "The Line command must hold the Line tool")
	var key := InputEventKey.new()
	key.keycode = KEY_B
	key.pressed = true
	expect(shell.header.command_for_key(key) == "map:paint", "B must be the Paint tool's key")
	# One stroke is one apply: a line, a rectangle and a fill each cost one revision.
	shell.ui("TileID").value = 17
	var revision: int = shell.bridge.revision
	await drag(Vector2i(5, 10), Vector2i(9, 10), true)
	await snapshot(tag + "-map-line-preview")
	canvas._gui_input(release_at(Vector2i(9, 10)))
	await settle()
	expect(shell.bridge.revision == revision + 1, "A line must be one apply")
	expect(range(5, 10).all(func(x): return floor_at(x, 10) == 17), "A line must paint every cell between its ends")
	shell.maps.toolbar.select_tool("rectangle")
	shell.ui("TileID").value = 18
	revision = shell.bridge.revision
	await drag(Vector2i(2, 12), Vector2i(4, 14))
	expect(shell.bridge.revision == revision + 1 and floor_at(3, 13) == 18 and floor_at(2, 12) == 18 and floor_at(4, 14) == 18, "A rectangle must fill its corners and be one apply")
	shell.maps.toolbar.select_tool("fill")
	shell.ui("TileID").value = 19
	revision = shell.bridge.revision
	pointer(Vector2i(3, 13), true)
	pointer(Vector2i(3, 13), false)
	await settle()
	expect(shell.bridge.revision == revision + 1 and floor_at(2, 12) == 19 and floor_at(4, 14) == 19 and floor_at(5, 12) != 19, "Fill must cover the joined tiles of one tile and no others, in one apply")
	await shell._history("undo")
	expect(floor_at(3, 13) == 18, "Undo must take back the whole fill")
	shell.maps.toolbar.select_tool("sample")
	pointer(Vector2i(5, 10), true)
	pointer(Vector2i(5, 10), false)
	expect(int(shell.ui("TileID").value) == 17, "Sample must take the tile under the cursor")
	# Triggers: place by click, then remove through the question.
	shell.maps.toolbar.select_tool("trigger")
	shell.ui("PlacementSlot").value = 99
	shell.ui("PlacementChance").value = 75
	pointer(Vector2i(7, 11), true)
	pointer(Vector2i(7, 11), false)
	await settle()
	await settle()
	expect(canvas.triggers.any(func(item): return int(item.id) == 99 and int(item.x) == 7 and int(item.y) == 11), "The Trigger tool must place the slot where it is clicked")
	await snapshot(tag + "-map-trigger-tool")
	shell.maps.toolbar.select_tool("erase")
	pointer(Vector2i(7, 11), true)
	pointer(Vector2i(7, 11), false)
	expect(shell.ui("RemoveDialog").visible, "Erasing a trigger must ask first")
	await snapshot(tag + "-map-remove-question")
	shell.ui("RemoveDialog")._answer("remove")
	await settle()
	await settle()
	expect(not canvas.triggers.any(func(item): return int(item.id) == 99), "Remove must unplace the trigger")
	# Stage start: the click drafts the move; Apply makes it.
	shell.maps.toolbar.select_tool("start")
	pointer(Vector2i(6, 5))
	await snapshot(tag + "-map-start-tool")
	pointer(Vector2i(6, 5), true)
	pointer(Vector2i(6, 5), false)
	expect(shell.drafts.has("stage_start:0") and int(shell.drafts["stage_start:0"].x) == 6, "The Start tool must draft the stage start")
	expect(canvas.stage_starts.any(func(start): return int(start.x) == 6 and int(start.y) == 5), "The canvas must show the drafted start")
	await snapshot(tag + "-map-stage-tab")
	expect(await shell.apply_draft() and int(shell.summary.stages[0].x) == 6, "Apply must make the drafted start")
	# Regions are shown and selected, not edited.
	if not canvas.regions.is_empty():
		var region: Dictionary = canvas.regions[0]
		shell.maps.toolbar.select_tool("region")
		var inside := Vector2i(int(region.first_x), int(region.first_y))
		canvas.set_view(1.0, Vector2(16, 16))
		pointer(inside, true)
		pointer(inside, false)
		expect(maps.inspector.tab == "regions" and canvas.selected_region == int(region.slot), "The Region tool must select the region under the click")
		await snapshot(tag + "-map-region-tool")
	# The map tab.
	maps.inspector.show_tab("map")
	await snapshot(tag + "-map-map-tab")
	# The land card: a tile set and a sight limit are drafts, and putting them back removes the draft.
	var sets: Array = all(maps.inspector, "OptionButton", []).filter(func(choice): return choice.is_visible_in_tree())
	expect(not sets.is_empty(), "The Map tab must offer the tile set")
	if not sets.is_empty():
		var saved_set: int = sets[0].get_selected_id()
		var other: int = 3 if saved_set != 3 else 4
		sets[0].select(sets[0].get_item_index(other))
		sets[0].item_selected.emit(sets[0].get_item_index(other))
		await settle()
		var look: Dictionary = shell.drafts.get("map_look:%d" % maps.map_id, {})
		expect(int(look.get("terrain", -1)) == other, "A tile set change must be a draft")
		var again: Array = all(maps.inspector, "OptionButton", []).filter(func(choice): return choice.is_visible_in_tree())
		again[0].select(again[0].get_item_index(saved_set))
		again[0].item_selected.emit(again[0].get_item_index(saved_set))
		await settle()
		expect(not shell.drafts.has("map_look:%d" % maps.map_id), "The saved tile set must leave no draft")
	# Quick edits: a chance change is a draft; Apply writes it.
	shell.maps.toolbar.select_tool("select")
	maps.inspector.show_tab("cell")
	await drag(cell, cell)
	await settle()
	var spins: Array = all(maps.inspector, "SpinBox", [])
	expect(not spins.is_empty(), "The trigger card must hold a chance field")
	if not spins.is_empty():
		spins[0].value = 50
		expect(shell.drafts.has(JSON.stringify({"kind": "walking_chance", "id": int(trigger.id)})), "A chance change must be a draft")
		expect(await shell.apply_draft(), "Apply must accept the chance")
		await settle()
		var check: Dictionary = await shell.request_backend({"op": "program", "family": "walking", "id": int(trigger.id), "branch": 0})
		expect(int(check.result.chance) == 50, "The applied chance must be read back")
	# A tile chosen for one cell is one apply.
	canvas.set_view(1.0, Vector2(16, 16))
	await drag(Vector2i(12, 3), Vector2i(12, 3))
	maps._choose(true)
	await snapshot(tag + "-map-choose-floor")
	maps.choose_dialog.palette.chosen.emit(104, false)
	revision = shell.bridge.revision
	maps.choose_dialog._commit()
	await settle()
	await settle()
	expect(shell.bridge.revision == revision + 1 and floor_at(12, 3) == 104, "Choosing a tile for a cell must be one apply")
	# New at selected cell: the proposal, then the trigger.
	await drag(Vector2i(14, 3), Vector2i(14, 3))
	maps.toolbar.new_button.pressed.emit()
	await settle()
	await snapshot(tag + "-map-new-at-cell")
	var before: int = canvas.triggers.size()
	maps.inspector.create_confirmed.emit()
	await settle()
	await settle()
	expect(canvas.triggers.size() == before + 1 and canvas.triggers.any(func(item): return int(item.x) == 14 and int(item.y) == 3 and item.active), "Create must add an active trigger at the selected cell")
	canvas.set_view(1.0, Vector2(16, 16))
	await snapshot(tag + "-map-final")


func release_at(cell: Vector2i) -> InputEventMouseButton:
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = false
	button.position = canvas.pan + (Vector2(cell) + Vector2(0.5, 0.5)) * canvas.cell_pixels()
	return button
