extends SceneTree
## Drives the Resources page and the import dialog on the real renderer: browsing icons, pictures and sounds,
## importing a PNG as an icon, a picture and a WAV as a sound, applying them, removing one and choosing an icon.
## Needs CENTURIONS_PROJECT to be an imported level, CENTURIONS_INSTALLATION, CENTURIONS_CAPTURE_OUT and
## CENTURIONS_IMPORT_SOURCES, a folder holding gunner.png and tone.wav.
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
	create_timer(150).timeout.connect(func(): push_error("Resources capture timed out"); quit(99))
	root.gui_embed_subwindows = true
	out = OS.get_environment("CENTURIONS_CAPTURE_OUT")
	var sources := OS.get_environment("CENTURIONS_IMPORT_SOURCES")
	if out.is_empty() or sources.is_empty(): push_error("CENTURIONS_CAPTURE_OUT and CENTURIONS_IMPORT_SOURCES required"); quit(1); return
	shell = load("res://src/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await shell.startup_completed
	root.size = Vector2i(1600, 900)
	var page: Control = shell.resources_page
	await shell._show_route(shell.ROUTES.find("Resources"))
	await settle()
	var browser: Control = page.browser
	expect(browser._ids_of("scenario").size() > 200, "The scenario's icons are listed")
	await snapshot("1600x900-resources-icons")
	browser.scope = "game"
	browser._fill()
	await settle()
	expect(browser._ids_of("game").size() > 500, "The game's icons are listed")
	browser.scope = "scenario"
	browser.show_kind("sound")
	await settle()
	expect(browser.selected_id >= 0 and browser._play.visible, "A sound has a play button")
	await snapshot("1600x900-resources-sounds")
	browser.show_kind("picture")
	await settle()
	expect(browser._preview.texture != null, "A picture shows its preview")
	# Import a PNG as an icon, a picture and a sound.
	for step in [["icon", "gunner.png", 3300], ["picture", "gunner.png", 23360], ["sound", "tone.wav", 20160]]:
		var dialog: Control = shell.import_dialog
		dialog.show_for(step[0], step[2])
		dialog._file_chosen(sources.path_join(step[1]))
		await settle()
		await settle()
		expect(not dialog._prepared.is_empty(), "The %s is prepared: %s" % [step[0], str(dialog._notes.get_child_count())])
		expect(not dialog._import.disabled, "A prepared %s can be imported" % step[0])
		if step[0] == "icon": await snapshot("1600x900-import-icon")
		dialog._commit()
		expect(shell.drafts.has("resource_change:%s:%d" % [{"icon": "cicn", "picture": "PICT", "sound": "snd "}[step[0]], step[2]]), "The import of the %s is a draft" % step[0])
	var applied: bool = await shell.apply_draft()
	expect(applied, "The imports must apply: " + str(shell.ui("Status").text))
	await page.refresh()
	browser.show_kind("icon")
	await settle()
	expect(browser._ids_of("scenario").has(3300), "The imported icon is listed")
	browser.choose(3300)
	await settle()
	expect(browser._preview.texture != null, "The imported icon shows")
	await snapshot("1600x900-resources-imported")
	# Remove it again, then undo the imports.
	page.remove_selected()
	expect(shell.drafts.has("resource_change:cicn:3300"), "A removal is a draft")
	expect(await shell.apply_draft(), "The removal must apply")
	await page.refresh()
	expect(not browser._ids_of("scenario").has(3300), "The removed icon is gone")
	# The picker offers the icons for a field.
	shell.resource_picker.show_for("icon", 3017, "capture", Callable())
	await settle()
	await settle()
	await snapshot("1600x900-pick-icon")
	shell.resource_picker.close()
	root.size = Vector2i(1200, 720)
	await shell._show_route(shell.ROUTES.find("Resources"))
	await snapshot("1200x720-resources")
	shell.bridge.stop()
	if failures.is_empty(): print("CENTURIONS_RESOURCE_CAPTURES_PASSED")
	else: push_error("Resource capture failures: " + str(failures))
	quit(0 if failures.is_empty() else 1)
