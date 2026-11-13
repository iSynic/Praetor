extends SceneTree
## Drives the compact layout on the real renderer: the folded menu, the record
## list and inspector drawers on Maps, Triggers and Messages, the Problems dock
## folded into the status bar, and the Preferences choice that turns it off.
## Needs CENTURIONS_PROJECT to be an imported level, CENTURIONS_INSTALLATION and
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
	create_timer(150).timeout.connect(func(): push_error("Compact capture timed out"); quit(99))
	root.gui_embed_subwindows = true
	out = OS.get_environment("CENTURIONS_CAPTURE_OUT")
	if out.is_empty(): push_error("CENTURIONS_CAPTURE_OUT required"); quit(1); return
	shell = load("res://src/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await shell.startup_completed
	# Wide: nothing folds.
	root.size = Vector2i(1600, 900)
	await settle()
	var layout: RefCounted = shell.compact
	expect(not layout.active and shell.header.get_node("CommandBar/Menus").visible and shell.problems.visible, "A wide window keeps the menus and the dock")
	# Narrow: the menus fold, the dock folds, the drawers are closed.
	root.size = Vector2i(1280, 720)
	await settle()
	expect(layout.active and not shell.header.get_node("CommandBar/Menus").visible and shell.header._burger.visible, "A narrow window folds the menus into one button")
	expect(not shell.problems.visible, "A narrow window folds the dock into the status bar")
	await shell._show_route(shell.ROUTES.find("Maps"))
	var sidebar: Control = layout.parts_of("Maps").list
	var inspector: Control = layout.parts_of("Maps").side
	expect(not sidebar.visible and not inspector.visible, "The drawers start closed")
	await snapshot("1280-map-compact")
	shell.tabs.list_requested.emit()
	await settle()
	expect(sidebar.visible and not inspector.visible, "The Maps button opens the map list")
	await snapshot("1280-map-list-drawer")
	shell.tabs.list_requested.emit()
	shell.tabs.side_requested.emit()
	await settle()
	expect(not sidebar.visible and inspector.visible, "The inspector button opens the inspector")
	await snapshot("1280-map-inspector-drawer")
	await shell._show_route(shell.ROUTES.find("Messages"))
	expect(not layout.parts_of("Messages").list.visible and not layout.drawers.list, "A page's drawers start closed")
	# The folded menu holds every menu, entries as they stand.
	var popup: PopupMenu = shell.header._burger.get_popup()
	shell.header._fill_burger()
	expect(popup.item_count == shell.header.MENUS.size(), "The folded menu lists every menu")
	var folded: PopupMenu = popup.get_item_submenu_node(0)
	expect(folded.item_count == shell.header._menu_button("File").get_popup().item_count, "A folded menu holds its entries")
	popup.popup(Rect2i(10, 50, 200, 0))
	await settle()
	var file: PopupMenu = popup.get_item_submenu_node(0)
	file.popup(Rect2i(210, 50, 260, 0))
	await snapshot("1280-folded-menu")
	file.hide()
	popup.hide()
	# The status bar opens the dock.
	shell.status_bar._chip.pressed.emit()
	await settle()
	expect(shell.problems.visible and shell.problems.is_open(), "The problems chip opens the dock")
	await snapshot("1280-dock-open")
	shell.status_bar._chip.pressed.emit()
	await settle()
	expect(not shell.problems.visible, "The problems chip closes the dock")
	await shell._show_route(shell.ROUTES.find("Programs"))
	await snapshot("1280-triggers-compact")
	# The choice turns it off.
	shell.settings.set_value("compact", false)
	await settle()
	expect(not layout.active and shell.problems.visible and layout.parts_of("Maps").list.visible, "With the choice off a narrow window keeps the full layout")
	shell.settings.set_value("compact", true)
	shell.bridge.stop()
	if failures.is_empty(): print("CENTURIONS_COMPACT_CAPTURES_PASSED")
	else: push_error("Compact capture failures: " + str(failures))
	quit(0 if failures.is_empty() else 1)
