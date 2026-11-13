extends SceneTree
## Drives region editing on the real renderer with real mouse events: drawing a
## region on empty floor, moving and resizing it by its border, the fields
## beside the map, removing it, and applying and undoing the edit. Needs
## CENTURIONS_PROJECT to be an imported level, CENTURIONS_INSTALLATION and
## CENTURIONS_CAPTURE_OUT.
var shell: Control
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


func run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Regions capture timed out"); quit(99))
	root.gui_embed_subwindows = true
	out = OS.get_environment("CENTURIONS_CAPTURE_OUT")
	if out.is_empty(): push_error("CENTURIONS_CAPTURE_OUT required"); quit(1); return
	shell = load("res://src/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await shell.startup_completed
	for size in [Vector2i(1600, 900), Vector2i(1200, 720)]:
		root.size = size
		await session("%dx%d" % [size.x, size.y])
	shell.bridge.stop()
	if failures.is_empty(): print("CENTURIONS_REGION_CAPTURES_PASSED")
	else: push_error("Region capture failures: " + str(failures))
	quit(0 if failures.is_empty() else 1)


## A left button event at the middle of a cell of the canvas.
func click(canvas: Control, cell: Vector2i, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = canvas.pan + (Vector2(cell) + Vector2(0.5, 0.5)) * canvas.cell_pixels()
	canvas._gui_input(event)


func move(canvas: Control, cell: Vector2i) -> void:
	var event := InputEventMouseMotion.new()
	event.position = canvas.pan + (Vector2(cell) + Vector2(0.5, 0.5)) * canvas.cell_pixels()
	canvas._gui_input(event)


func region_at(canvas: Control, slot: int) -> Dictionary:
	for region in canvas.regions:
		if int(region.slot) == slot: return region
	return {}


func session(tag: String) -> void:
	await shell._show_route(shell.ROUTES.find("Maps"))
	await shell._select_map(0)
	var maps: Control = shell.maps
	var canvas: Control = shell.ui("MapCanvas")
	canvas.set_view(0.5, Vector2(20, 20))
	maps.toolbar.select_tool("region")
	var before: int = canvas.regions.size()
	expect(before > 0, "The imported map must have regions")
	# Draw on empty floor: the first free slot takes it.
	var free: int = maps._free_slot()
	var origin := Vector2i(-1, -1)
	for y in range(0, 80):
		for x in range(0, 80):
			var block := Rect2i(x, y, 6, 6)
			if origin.x < 0 and not canvas.regions.any(func(region): return canvas.region_rectangle(region).intersects(block)): origin = Vector2i(x, y)
	expect(origin.x >= 0, "The map must have empty floor for a region")
	click(canvas, origin, true)
	move(canvas, origin + Vector2i(4, 3))
	click(canvas, origin + Vector2i(4, 3), false)
	var made := region_at(canvas, free)
	expect(not made.is_empty() and int(made.first_x) == origin.x and int(made.last_x) == origin.x + 4 and int(made.last_y) == origin.y + 3, "Dragging on empty floor must draw a region in the first free slot: " + str(made))
	expect(shell.drafts.has("region:0:%d" % free), "A drawn region is a draft")
	expect(canvas.selected_region == free, "The drawn region is the chosen one")
	# Resize by its bottom right corner, then move it by its inside.
	click(canvas, origin + Vector2i(4, 3), true)
	move(canvas, origin + Vector2i(4, 4))
	click(canvas, origin + Vector2i(4, 4), false)
	expect(int(region_at(canvas, free).last_y) == origin.y + 4 and int(region_at(canvas, free).first_y) == origin.y, "Dragging a corner resizes the region")
	click(canvas, origin + Vector2i(2, 2), true)
	move(canvas, origin + Vector2i(3, 3))
	click(canvas, origin + Vector2i(3, 3), false)
	var moved := region_at(canvas, free)
	expect(int(moved.first_x) == origin.x + 1 and int(moved.first_y) == origin.y + 1 and int(moved.last_x) == origin.x + 5, "Dragging inside moves the region: " + str(moved))
	# The fields beside the map change the draft too.
	maps.region_edit(free, {"battle_min": 2, "battle_max": 4, "encounter_chance": 95, "script0": 28, "chance0": 100})
	expect(int(region_at(canvas, free).battle_max) == 4 and int(region_at(canvas, free).scripts[0]) == 28, "The fields change the region")
	await snapshot(tag + "-region-drawn")
	# Applied, it is saved; undone, it is gone.
	var applied: bool = await shell.apply_draft()
	expect(applied, "A drawn region must apply: " + str(shell.status_bar.get_node("%Status").text))
	await shell._select_map(0)
	expect(not region_at(canvas, free).is_empty(), "An applied region is saved")
	await shell._history("undo")
	await shell._select_map(0)
	expect(region_at(canvas, free).is_empty(), "Undo takes the region away")
	# Putting every field back removes the draft; removing a region is a draft of an empty one.
	var original: Dictionary = canvas.regions[0].duplicate(true)
	maps.region_edit(int(original.slot), {"last_x": int(original.last_x) - 1})
	expect(shell.drafts.has("region:0:%d" % int(original.slot)), "Changing a region drafts it")
	maps.region_edit(int(original.slot), {"last_x": int(original.last_x)})
	expect(not shell.drafts.has("region:0:%d" % int(original.slot)), "Putting the region back leaves no draft")
	maps.region_edit(int(original.slot), {"remove": true})
	expect(region_at(canvas, int(original.slot)).is_empty() and shell.drafts.size() == 1, "Removing a region drafts an empty one")
	await shell._discard_continue()
	expect(not region_at(canvas, int(original.slot)).is_empty(), "Discarding brings the region back")
	maps.select_region(int(original.slot))
	await snapshot(tag + "-region-fields")
	maps.toolbar.select_tool("select")
