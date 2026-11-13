extends SceneTree
## Capture real rendered Godot routes; no host input or window automation.
var shell: Control

func _initialize() -> void:
	call_deferred("run")

## A dialog's panel must lie inside the window.
func check_dialog(label: String, dialog: Control, dimensions: Vector2i) -> void:
	var rect: Rect2 = dialog.panel_rect()
	if not Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(rect):
		push_error("Dialog %s exceeds the %s window: %s" % [label,str(dimensions),str(rect)])
		failed = true


func settle() -> void:
	if shell != null:
		while shell.bridge.busy: await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func snapshot(path: String) -> void:
	await settle()
	var image := root.get_texture().get_image()
	assert(image != null and not image.is_empty())
	assert(image.save_png(path) == OK)

var failed := false


func run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Rendered capture timed out"); quit(99))
	root.gui_embed_subwindows = true
	var out := OS.get_environment("CENTURIONS_CAPTURE_OUT")
	assert(not out.is_empty())
	shell = load("res://src/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await shell.startup_completed
	var sizes := [Vector2i(1600,900),Vector2i(1200,720)]
	var layouts: Array = []
	for dimensions in sizes:
		root.size = dimensions
		await settle()
		for index in range(shell.ROUTES.size()):
			await shell._show_route(index)
			if index == 6: await shell.combat_ui.record(1)
			await snapshot(out.path_join("%dx%d-%s.png" % [dimensions.x,dimensions.y,shell.ROUTES[index].to_lower()]))
			var bad: Array = []
			for name in ["Brand","Rail","Undo","Redo","Save","PlayFromHere","Export","Pages","Apply","ProblemsDock","Status"]:
				var control: Control = shell.ui(name)
				if control.is_visible_in_tree() and not Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(control.get_global_rect()): bad.append(name)
			layouts.append({"size":[dimensions.x,dimensions.y],"route":shell.ROUTES[index],"outside_window":bad})
			if not bad.is_empty(): push_error("Controls exceed window at %s on %s: %s" % [str(dimensions),shell.ROUTES[index],str(bad)]); failed = true
		await shell._show_route(3)
		await shell._select_map(0)
		var canvas: Control = shell.ui("MapCanvas")
		shell.maps.set_layer("regions",false)
		canvas.set_view(1.2,Vector2(450,320)-Vector2(67,85)*32*1.2)
		await snapshot(out.path_join("%dx%d-map0-negative-icons.png" % [dimensions.x,dimensions.y]))
		await shell._select_map(2)
		canvas.set_view(1.2,Vector2(200,320)-Vector2(1,41)*32*1.2)
		await snapshot(out.path_join("%dx%d-map2-negative-icons.png" % [dimensions.x,dimensions.y]))
		shell.maps.choose_dialog.show_for(2,Vector2i(1,41),1,canvas.atlas,canvas.icons,2,0)
		await snapshot(out.path_join("%dx%d-palette-icons.png" % [dimensions.x,dimensions.y]))
		check_dialog("choose-floor",shell.maps.choose_dialog,dimensions)
		shell.maps.choose_dialog.hide()
		await shell._select_map(0)
		canvas.set_view(0.35,Vector2(18,18))
		shell.maps.set_layer("regions",true)
		if not canvas.triggers.is_empty():
			var trigger: Dictionary = canvas.triggers[0]
			shell._map_cell_selected(Vector2i(int(trigger.x),int(trigger.y)),int(canvas.floor_values[int(trigger.x)*90+int(trigger.y)]))
		await snapshot(out.path_join("%dx%d-map-regions.png" % [dimensions.x,dimensions.y]))
		await shell._choose_program("typed",0,0)
		await shell._show_route(5)
		await shell.condition_ui.open()
		await snapshot(out.path_join("%dx%d-conditions.png" % [dimensions.x,dimensions.y]))
		shell.condition_ui.window.hide()
		await shell._show_route(3)
		shell.maps.toolbar.select_tool("trigger")
		await snapshot(out.path_join("%dx%d-placement.png" % [dimensions.x,dimensions.y]))
		shell.maps.toolbar.select_tool("select")
		await shell._show_route(6)
		shell.combat_ui.kind.select(1); await shell.combat_ui.catalogue(0); await shell.combat_ui.record(1)
		await snapshot(out.path_join("%dx%d-monsters.png" % [dimensions.x,dimensions.y]))
		shell.combat_ui.kind.select(0)
		shell._choose_destination("save")
		await snapshot(out.path_join("%dx%d-save-dialog.png" % [dimensions.x,dimensions.y]))
		shell.ui("DestinationDialog").hide()
		# Every dialog of the project flows stays inside the window, scrolling its body when it must.
		var dialogs := {}
		shell._source = OS.get_environment("CENTURIONS_INSTALLATION").path_join("Scenarios/The Thunder of Guns/0")
		shell._choose_destination("import")
		dialogs["import-source"] = shell.ui("ImportDialog")
		await snapshot(out.path_join("%dx%d-import-source.png" % [dimensions.x,dimensions.y]))
		check_dialog("import-source",dialogs["import-source"],dimensions)
		shell.ui("ImportDialog").show_result(shell.summary)
		await snapshot(out.path_join("%dx%d-import-result.png" % [dimensions.x,dimensions.y]))
		check_dialog("import-result",shell.ui("ImportDialog"),dimensions)
		shell.ui("ImportDialog").hide()
		shell._source = ""
		shell._choose_destination("new")
		await snapshot(out.path_join("%dx%d-new-from-template.png" % [dimensions.x,dimensions.y]))
		check_dialog("new-from-template",shell.ui("NewDialog"),dimensions)
		shell.ui("NewDialog").hide()
		shell.flows.open_preferences()
		await snapshot(out.path_join("%dx%d-preferences.png" % [dimensions.x,dimensions.y]))
		check_dialog("preferences",shell.ui("PreferencesDialog"),dimensions)
		shell.ui("PreferencesDialog").hide()
		shell.flows.show_export_result(out,{"files": 61,"native_scenario_name": "Capture","byte_exact_to_import": false},{"files": 61,"copied": 59,"changed": [{"name": "Data DD","size": 46200,"bytes": 7},{"name": "Data ED","size": 4284,"bytes": 3}],"bytes": 10,"added": [],"unreadable": []},"Exported 61 files · installation and runtime checks remain separate")
		await snapshot(out.path_join("%dx%d-export-results.png" % [dimensions.x,dimensions.y]))
		check_dialog("export-results",shell.ui("ExportResultDialog"),dimensions)
		shell.ui("ExportResultDialog").hide()
		await shell._show_route(2)
		await shell._load_message(0)
		shell.ui("TextCheckTimer").stop()
		shell.ui("MessageText").text = "Draft for review."
		shell._message_changed()
		shell.ui("TextCheckTimer").stop()
		shell.guard(shell._show_route.bind(1))
		await snapshot(out.path_join("%dx%d-draft-dialog.png" % [dimensions.x,dimensions.y]))
		await shell._discard_continue()
	var f := FileAccess.open(out.path_join("layout.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"layouts":layouts,"engine":Engine.get_version_info().string},"  ")); f.close()
	shell.bridge.stop()
	if failed: push_error("Capture checks failed"); quit(1); return
	print("CENTURIONS_EDITOR_CAPTURES_PASSED")
	quit()
