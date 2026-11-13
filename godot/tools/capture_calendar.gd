extends SceneTree
## Drives the Calendar page on the real renderer: the entries of the scenario, editing one, adding an entry,
## switching it off, picking a cell on a map, applying and undoing. Needs CENTURIONS_PROJECT to be an imported
## level, CENTURIONS_INSTALLATION and CENTURIONS_CAPTURE_OUT.
var shell: Control
var calendar: Control
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
	create_timer(120).timeout.connect(func(): push_error("Calendar capture timed out"); quit(99))
	root.gui_embed_subwindows = true
	out = OS.get_environment("CENTURIONS_CAPTURE_OUT")
	if out.is_empty(): push_error("CENTURIONS_CAPTURE_OUT required"); quit(1); return
	shell = load("res://src/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await shell.startup_completed
	calendar = shell.calendar_page
	root.size = Vector2i(1600, 900)
	await session("1600x900")
	root.size = Vector2i(1200, 720)
	await shell._show_route(shell.ROUTES.find("Calendar"))
	await snapshot("1200x720-calendar")
	shell.bridge.stop()
	if failures.is_empty(): print("CENTURIONS_CALENDAR_CAPTURES_PASSED")
	else: push_error("Calendar capture failures: " + str(failures))
	quit(0 if failures.is_empty() else 1)


func session(tag: String) -> void:
	await shell._show_route(shell.ROUTES.find("Calendar"))
	var count: int = calendar.entry_count()
	expect(count >= 12, "The scenario's calendar entries are listed")
	await calendar.show_entry(0)
	expect(int(calendar._entry.story) == 169 or int(calendar._entry.day) != 0, "An entry shows what the scenario holds")
	await snapshot(tag + "-calendar")
	# Setting a day on an unused entry is one draft; putting it back leaves none.
	await calendar.show_entry(3)
	var was: int = int(calendar.day.value)
	calendar.day.value = 40
	expect(shell.drafts.has("calendar_entry:3"), "A changed entry must be a draft")
	calendar.day.value = was
	expect(not shell.drafts.has("calendar_entry:3"), "An entry put back leaves no draft")
	# Make a real entry: day 40, every 10 days, chance 100, at a place with a flag and an item.
	calendar.day.value = 40
	calendar.interval.value = 10
	calendar.chance.value = 100
	calendar.story.value = 0
	calendar.flag_check.button_pressed = true
	calendar.flag.value = 5
	calendar.item_check.button_pressed = true
	calendar.item.value = 800
	calendar.place.select(1)
	calendar._read_fields()
	await settle()
	calendar.cell_check.button_pressed = true
	calendar.column.value = 7
	calendar.row.value = 4
	calendar._read_fields()
	var draft: Dictionary = shell.drafts.get("calendar_entry:3", {})
	expect(int(draft.get("day", 0)) == 40 and int(draft.get("x", -1)) == 7 and int(draft.get("y", -1)) == 4 and int(draft.get("place", 0)) == 1, "The entry's fields are in the draft: " + str(draft))
	var lines: PackedStringArray = calendar._lines()
	expect(lines.size() >= 5, "The eligibility lists each test the game makes: " + str(lines))
	await snapshot(tag + "-calendar-edited")
	# The cell picker opens on the entry's map.
	await calendar._cell_dialog.show_for(0, Vector2i(7, 4))
	await settle()
	await snapshot(tag + "-calendar-cell")
	calendar._cell_dialog.close()
	# A new entry after the last begins switched off.
	await calendar.add_entry()
	expect(calendar.entry_count() == count and shell.drafts.has("calendar_entry:%d" % count), "A new entry is added after the last")
	var applied: bool = await shell.apply_draft()
	expect(applied, "The calendar edits must apply: " + str(shell.ui("Status").text))
	await calendar.refresh()
	expect(calendar.entry_count() == count + 1, "The applied entry is added")
	await calendar.show_entry(3)
	expect(int(calendar.day.value) == 40 and int(calendar.column.value) == 7 and int(calendar.item.value) == 800, "An applied entry is saved")
	await snapshot(tag + "-calendar-applied")
	await shell._history("undo")
	await calendar.refresh()
	expect(calendar.entry_count() == count, "Undo takes the new entry back")
