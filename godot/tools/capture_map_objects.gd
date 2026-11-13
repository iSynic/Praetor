extends SceneTree
## Drives the object layer and Add a map on the real renderer: painting objects, a building picture and an icon,
## the inspector's Object card, the dialog that adds a copy of a map, and undo. Needs CENTURIONS_PROJECT to be an
## imported level, CENTURIONS_INSTALLATION and CENTURIONS_CAPTURE_OUT.
var shell: Control
var maps: Control
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
	create_timer(150).timeout.connect(func(): push_error("Map object capture timed out"); quit(99))
	root.gui_embed_subwindows = true
	out = OS.get_environment("CENTURIONS_CAPTURE_OUT")
	if out.is_empty(): push_error("CENTURIONS_CAPTURE_OUT required"); quit(1); return
	shell = load("res://src/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await shell.startup_completed
	maps = shell.maps
	root.size = Vector2i(1600, 900)
	await session("1600x900")
	shell.bridge.stop()
	if failures.is_empty(): print("CENTURIONS_MAP_OBJECT_CAPTURES_PASSED")
	else: push_error("Map object capture failures: " + str(failures))
	quit(0 if failures.is_empty() else 1)


func session(tag: String) -> void:
	await shell._show_route(shell.ROUTES.find("Maps"))
	await maps.select_map(0)
	var canvas: Control = maps.canvas
	var before: int = int(shell.summary.maps)
	var had: int = int(canvas.objects[3 * 90 + 3])
	expect(canvas.objects.size() == 8100, "The map reports its object layer")
	# The Objects tab paints the object layer: a building, then another, then an icon.
	maps.sidebar.target_changed.emit("object")
	await settle()
	expect(maps.paint_target == "object" and maps.toolbar.object_mode, "The Objects tab makes the paint tools write objects")
	maps.toolbar.tile_id.value = 55
	await maps.paint_stroke([Vector2i(3, 3)])
	await maps.show_map()
	expect(int(canvas.objects[3 * 90 + 3]) == 55, "A building is painted")
	canvas.selected_cell = Vector2i(4, 3)
	await maps._show_cell()
	await maps.object_edit(10)
	expect(int(canvas.objects[4 * 90 + 3]) == 10 and canvas.object_art.get(10) != null, "A building is placed and its art is read: " + str(canvas.object_art.get(10)))
	canvas.selected_cell = Vector2i(5, 3)
	await maps._show_cell()
	await maps.object_edit(-3001)
	expect(int(canvas.objects[5 * 90 + 3]) == -3001, "An icon is placed")
	canvas.selected_cell = Vector2i(4, 3)
	await maps._show_cell()
	canvas.center_on(Vector2i(4, 3))
	canvas.zoom_to(1.0)
	await snapshot(tag + "-objects")
	canvas.selected_cell = Vector2i(3, 3)
	await maps.object_edit(0)
	expect(int(canvas.objects[3 * 90 + 3]) == 0, "An object is removed by painting nothing")
	# Add a map as a copy of this one.
	await maps.add_map_dialog.show_for(0, 5)
	await settle()
	expect(maps.add_map_dialog._review.get_child_count() >= 3, "The dialog reviews what the three files gain")
	await snapshot(tag + "-add-map")
	await maps.add_map_dialog._commit()
	await settle()
	expect(int(shell.summary.maps) == before + 1, "The map is added")
	await maps.select_map(before)
	expect(int(canvas.objects[4 * 90 + 3]) == 10, "The copy holds the objects of the map it copies")
	await snapshot(tag + "-added")
	# The Thunder scenario already names an eleventh map in a step, so the new map cannot be removed and the dialog says what names it.
	await maps._remove_map()
	await settle()
	expect(maps.remove_map_dialog.visible and maps.remove_map_dialog.heading.ends_with("still named"), "The last map is kept while a step names it: " + maps.remove_map_dialog.heading)
	await snapshot(tag + "-remove-map")
	maps.remove_map_dialog.hide()
	# Undo takes the map and the objects back.
	for step in range(5): await shell._history("undo")
	expect(int(shell.summary.maps) == before, "Undo takes the added map back")

	await maps.select_map(0)
	expect(int(canvas.objects[3 * 90 + 3]) == had and int(canvas.objects[4 * 90 + 3]) == 0, "Undo takes the objects back")
