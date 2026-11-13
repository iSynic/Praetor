extends SceneTree
## Drives the Notes page on the real renderer: the notes of the scenario with their labels, editing a note and a label, adding a note
## and a mark, applying and undoing. Needs CENTURIONS_PROJECT to be an imported level, CENTURIONS_INSTALLATION and CENTURIONS_CAPTURE_OUT.
var shell: Control
var notes: Control
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
	create_timer(100).timeout.connect(func(): push_error("Notes capture timed out"); quit(99))
	root.gui_embed_subwindows = true
	out = OS.get_environment("CENTURIONS_CAPTURE_OUT")
	if out.is_empty(): push_error("CENTURIONS_CAPTURE_OUT required"); quit(1); return
	shell = load("res://src/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await shell.startup_completed
	notes = shell.notes_page
	root.size = Vector2i(1600, 900)
	await shell._show_route(shell.ROUTES.find("Notes"))
	await notes.show_note(0)
	expect(notes.after.text == "Cave leading to other Symbionts", "The note's label is shown: " + notes.after.text)
	expect(int(notes._marks[0].icon.value) == 137 and int(notes.icon_size.value) == 16, "The note's marks and size are shown")
	await snapshot("1600x900-notes")
	# A mark's column is a draft; putting it back leaves none.
	var column: int = int(notes._marks[0].column.value)
	notes._marks[0].column.value = column + 1
	expect(shell.drafts.has("map_note:0"), "A changed note is a draft")
	notes._marks[0].column.value = column
	expect(not shell.drafts.has("map_note:0"), "A note put back leaves no draft")
	# A label is a draft of its own.
	notes.before.text = "A cave not yet found"
	notes._label_edited(false)
	expect(shell.drafts.has("note_label:1:0"), "A changed label is a draft")
	# A new note is a section; give it a mark, a cell size and words, then apply.
	var before_count: int = notes._all().size()
	await notes.add_note()
	expect(notes._all().size() == before_count + 1, "A note is added after the last")
	notes._marks[0].icon.value = 137
	notes._marks[0].column.value = 3
	notes._marks[0].row.value = 4
	notes.icon_size.value = 32
	notes.words.text = "A note the author wrote."
	notes._edited()
	await snapshot("1600x900-notes-new")
	var applied: bool = await shell.apply_draft()
	expect(applied, "The notes apply: " + str(shell.ui("Status").text))
	await notes.refresh()
	await notes.show_note(before_count)
	expect(notes.words.text == "A note the author wrote." and int(notes._marks[0].column.value) == 3 and int(notes.icon_size.value) == 32, "An applied note is saved")
	await notes.show_note(0)
	expect(notes.before.text == "A cave not yet found", "An applied label is saved")
	await shell._history("undo")
	await notes.refresh()
	expect(notes._all().size() == before_count, "Undo takes the new note back")
	shell.bridge.stop()
	if failures.is_empty(): print("CENTURIONS_NOTES_CAPTURES_PASSED")
	else: push_error("Notes capture failures: " + str(failures))
	quit(0 if failures.is_empty() else 1)
