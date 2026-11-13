extends SceneTree
## Drives the Texts page on the real renderer: the list of scrolling texts, editing one with its styles, adding
## and removing texts, applying them and choosing one for a code 62 step. Needs CENTURIONS_PROJECT to be an
## imported level whose Scenario.rsrc holds texts, CENTURIONS_INSTALLATION and CENTURIONS_CAPTURE_OUT.
var shell: Control
var texts: Control
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
	create_timer(120).timeout.connect(func(): push_error("Texts capture timed out"); quit(99))
	root.gui_embed_subwindows = true
	out = OS.get_environment("CENTURIONS_CAPTURE_OUT")
	if out.is_empty(): push_error("CENTURIONS_CAPTURE_OUT required"); quit(1); return
	shell = load("res://src/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await shell.startup_completed
	texts = shell.texts_page
	root.size = Vector2i(1600, 900)
	await session("1600x900")
	root.size = Vector2i(1200, 720)
	await shell._show_route(shell.ROUTES.find("Texts"))
	await snapshot("1200x720-texts")
	shell.bridge.stop()
	if failures.is_empty(): print("CENTURIONS_TEXT_CAPTURES_PASSED")
	else: push_error("Text capture failures: " + str(failures))
	quit(0 if failures.is_empty() else 1)


func session(tag: String) -> void:
	await shell._show_route(shell.ROUTES.find("Texts"))
	expect(texts.list._tree.get_root().get_child_count() >= 6, "The list must hold the scenario's texts")
	# The filter looks in the whole text: the registration appeal names Denny's a long way past its first words.
	texts.list._filter.text = "denny"
	texts.list._filter.text_changed.emit("denny")
	var found: int = texts.list._tree.get_root().get_child_count()
	expect(found >= 1 and found < 6 and "Denny" in str(texts.list._tree.get_root().get_first_child().get_text(1)), "The filter must find words deep in a text and show where")
	texts.list._filter.text = ""
	texts.list._filter.text_changed.emit("")
	await texts.show_text(1001)
	var saved_text: String = texts.editor.text
	expect(saved_text.length() > 100 and texts._runs.size() >= 1, "A text shows its words and its style runs")
	await snapshot(tag + "-texts")
	# Editing the words is one draft; putting them back leaves none.
	texts.editor.text = saved_text + " More."
	texts._edited()
	expect(shell.drafts.has("scroll_text:1001"), "A changed text must be a draft")
	texts.editor.text = saved_text
	texts._edited()
	expect(not shell.drafts.has("scroll_text:1001"), "A text put back leaves no draft")
	# A run begins at the cursor and is a draft of its own.
	var before: int = texts._runs.size()
	texts.editor.set_caret_line(3)
	texts.editor.set_caret_column(0)
	texts._add_run()
	expect(texts._runs.size() == before + 1 and shell.drafts.has("scroll_text:1001"), "A style run is added at the cursor")
	var at: int = texts._cursor_character()
	for index in range(texts._runs.size()):
		if int(texts._runs[index].start) == at: texts._remove_run(index); break
	expect(not shell.drafts.has("scroll_text:1001"), "A removed run leaves the text as saved")
	# Apply a change, a new text and a removal.
	texts.editor.text = saved_text + " More."
	texts._edited()
	texts._number.value = 2000
	await texts.add_text()
	expect(shell.drafts.has("scroll_text:2000"), "A new text is a draft")
	texts.editor.text = "A new scrolling text."
	texts._edited()
	# Adding the number again must not empty the text already added under it.
	texts._number.value = 2000
	await texts.add_text()
	await texts.show_text(2000)
	expect(texts.editor.text == "A new scrolling text.", "Adding a number that is already new keeps its words")
	await texts.show_text(1005)
	await texts.remove_text()
	expect(shell.drafts.has("scroll_text:1005"), "A removal is a draft")
	await snapshot(tag + "-texts-drafts")
	var applied: bool = await shell.apply_draft()
	expect(applied, "The text edits must apply: " + str(shell.ui("Status").text))
	await texts.refresh()
	await texts.show_text(1001)
	expect(texts.editor.text.ends_with(" More."), "An applied edit is saved")
	await texts.show_text(2000)
	expect(texts.editor.text == "A new scrolling text.", "An applied new text is saved")
	var ids: Array = []
	for row in texts._rows: ids.append(int(row.id))
	expect(ids.has(2000) and not ids.has(1005), "The new text is listed and the removed one is gone")
	await snapshot(tag + "-texts-applied")
	# Undo takes all three back at once.
	await shell._history("undo")
	await texts.refresh()
	ids.clear()
	for row in texts._rows: ids.append(int(row.id))
	expect(ids.has(1005) and not ids.has(2000), "Undo restores the removed text and drops the new one")
	# The picker of a code 62 step lists the texts.
	shell.picker_dialog.show_for("text", 1001, "capture", Callable())
	await settle()
	await settle()
	expect(shell.picker_dialog.list._tree.get_root().get_child_count() >= 6, "The text picker lists the texts")
	await snapshot(tag + "-pick-text")
	shell.picker_dialog.close()
