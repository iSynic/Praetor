extends SceneTree
## Captures the shell's dock and menus and a gallery of the shared widgets on
## the real renderer; no host input or window automation.
const Card = preload("res://src/widgets/card.gd")
const KeyValueRow = preload("res://src/widgets/key_value_row.gd")
const ModalOverlay = preload("res://src/widgets/modal_overlay.gd")
const RecordList = preload("res://src/widgets/record_list.gd")
const ActionCard = preload("res://src/widgets/action_card.gd")
const CheckRow = preload("res://src/widgets/check_row.gd")
const ConfirmDialog = preload("res://src/widgets/confirm_dialog.gd")
const FolderCheck = preload("res://src/services/folder_check.gd")
const KbdButton = preload("res://src/widgets/kbd_button.gd")
const PathField = preload("res://src/widgets/path_field.gd")
const Capability = preload("res://src/scripts/capability.gd")
const StatTile = preload("res://src/widgets/stat_tile.gd")
const Stepper = preload("res://src/widgets/stepper.gd")
const StatusLevel = preload("res://src/services/status_level.gd")
const WorkspaceSettings = preload("res://src/services/workspace_settings.gd")
var shell: Control
var failures: Array = []


func _initialize() -> void:
	call_deferred("run")


func snapshot(path: String) -> void:
	while shell.bridge.busy: await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.save_png(path) != OK: failures.append(path)


func expect(passed: bool, message: String) -> void:
	if not passed: failures.append(message)


func run() -> void:
	create_timer(45).timeout.connect(func(): push_error("Widget capture timed out"); quit(99))
	root.gui_embed_subwindows = true
	root.size = Vector2i(1600, 900)
	var out := OS.get_environment("CENTURIONS_CAPTURE_OUT")
	if out.is_empty(): push_error("CENTURIONS_CAPTURE_OUT required"); quit(1); return
	shell = load("res://src/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await shell.startup_completed
	# The dock opens from the rail and lists one row per notice.
	shell.rail.problems_requested.emit()
	expect(shell.ui("Problems").visible, "Problems dock did not open")
	expect(shell.ui("ProblemRows").get_child_count() == shell.problems.count, "Problems rows do not match the count")
	shell.ui("MenuFile").show_popup()
	await snapshot(out.path_join("shell-problems-and-menu.png"))
	shell.ui("MenuFile").get_popup().hide()
	shell.ui("MenuView").show_popup()
	await snapshot(out.path_join("shell-view-menu.png"))
	shell.ui("MenuView").get_popup().hide()
	shell.rail.problems_requested.emit()
	expect(not shell.ui("Problems").visible, "Problems dock did not close")
	# A menu entry routes like its rail button.
	shell.header.command.emit("route:Maps")
	while shell.bridge.busy: await process_frame
	expect(shell.pages.current_tab == shell.ROUTES.find("Maps"), "View menu did not route to Maps")

	var modal := ModalOverlay.new()
	modal.title = "Author records"
	modal.subtitle = "Monsters"
	modal.panel_size = Vector2(1080, 560)
	shell.add_child(modal)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	modal.body.add_child(columns)
	var list := RecordList.new()
	list.title = "Monsters"
	list.filter_placeholder = "Filter by id or monster name…"
	list.can_add = true
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.set_columns([{"title": "ID", "width": 64, "mono": true}, {"title": "Name"}, {"title": "Level", "width": 70, "mono": true, "right": true}])
	list.set_scopes([{"id": "all", "label": "All", "count": 4}, {"id": "unnamed", "label": "Unnamed", "count": 1}])
	list.set_rows([
		{"id": 64, "cells": ["M64", "Scientist", 1]},
		{"id": 65, "cells": ["M65", "Biologist", 1], "dirty": true},
		{"id": 66, "cells": ["M66", "Bore Worm", 5]},
		{"id": 67, "cells": ["M67", "", 7]},
	])
	list.set_count(4)
	list.select(65)
	columns.add_child(list)
	var picked: Array = []
	list.row_selected.connect(func(id): picked.append(id))
	var card := Card.new()
	card.title = "Edit after cloning"
	card.dot_color = shell.get_theme_color("info", "EditorTokens")
	card.custom_minimum_size.x = 420
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	columns.add_child(card)
	for pair in [["Name", "29 Mac Roman bytes at most", false], ["Level", "1 – 127", true], ["Stamina", "0 – 30000", true]]:
		var row := KeyValueRow.new()
		row.key = pair[0]; row.value = pair[1]; row.mono = pair[2]
		card.add_row(row)
	var badges := HBoxContainer.new()
	for entry in [["imported level", "Badge"], ["warn", "BadgeWarn"], ["error", "BadgeErr"], ["allow", "BadgeGood"], ["new", "BadgeAccent"]]:
		var badge := Label.new(); badge.text = entry[0]; badge.theme_type_variation = entry[1]; badges.add_child(badge)
	card.add_row(badges)
	var chips := HBoxContainer.new()
	for entry in [["All  136", true], ["Unnamed  12", false]]:
		var chip := Button.new(); chip.text = entry[0]; chip.theme_type_variation = &"Chip"; chip.toggle_mode = true; chip.button_pressed = entry[1]; chips.add_child(chip)
	card.add_row(chips)
	var field := LineEdit.new(); field.text = "Pirate Captain"; card.add_row(field)
	var bar: Control = load("res://src/widgets/apply_bar.tscn").instantiate()
	card.add_row(bar)
	bar.show_pending(1, false)
	modal.add_button("Cancel").pressed.connect(modal.close)
	modal.add_button("Remove", "danger")
	modal.add_button("Clone as Monster 136", "primary")
	modal.open()
	await snapshot(out.path_join("widgets.png"))
	# The filter narrows the rows; Esc closes the overlay.
	list._filter.text = "worm"; list._filter.text_changed.emit("worm")
	expect(list._tree.get_root().get_child_count() == 1, "Record list filter kept the wrong rows")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE; escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame; await process_frame
	expect(not modal.visible, "Esc did not close the modal overlay")
	await project_flow_widgets(out)
	shell.bridge.stop()
	if failures.is_empty(): print("CENTURIONS_WIDGET_CAPTURES_PASSED")
	else: push_error("Widget capture failures: " + str(failures))
	quit(0 if failures.is_empty() else 1)


## The widgets and services of the project flows: a gallery, and the checks
## that carry the flows' rules (shortcut routing, the answer a question gives,
## what a destination field says, and the settings file shared with the adapter).
func project_flow_widgets(out: String) -> void:
	# Every operation the editor has a form for is one the capability data records and the program view reads.
	expect(Capability.known_count() > 100 and not Capability.provenance().get("sha256", "").is_empty(), "The capability data must load with its provenance")
	for entry in Capability.forms():
		expect(not Capability.row(int(entry[0])).is_empty(), "Opcode %d has a form and so must have a capability row" % int(entry[0]))
		expect(not Capability.takes(int(entry[0])).is_empty(), "Opcode %d must say what its operand takes" % int(entry[0]))
	# Shortcuts reach the same commands as the menus; an entry that is not built yet runs nothing.
	var press := func(keycode: int, ctrl := true, shift := false) -> String:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.ctrl_pressed = ctrl
		event.shift_pressed = shift
		event.pressed = true
		return shell.header.command_for_key(event)
	expect(press.call(KEY_I) == "import" and press.call(KEY_O) == "open" and press.call(KEY_N) == "new", "Ctrl I, O and N must import, open and start from a template")
	expect(press.call(KEY_COMMA) == "preferences" and press.call(KEY_1) == "route:Maps" and press.call(KEY_J) == "problems", "Ctrl comma, 1 and J must open Preferences, Maps and Problems")
	expect(press.call(KEY_K) == "goto" and press.call(KEY_F, true, true) == "find_uses" and press.call(KEY_F5, false) == "", "Ctrl K and Ctrl Shift F must open Go to and Find uses; Play from here runs nothing while the runtime is missing")
	# The dot before a status line says how it went.
	for pair in [["Starting local adapter…", "info"], ["Opened checkpoint", "good"], ["Select a map cell first", "warn"], ["Return destination drafted · Apply edits", "warn"],
			["No receipt matched to this exact export. Loading, prologue, and gameplay are separate checks.", "dim"], ["Receipt does not match this exact export. Startup remains unverified for the current edits.", "err"],
			["Adapter disconnected. Reopen the project; drafts are kept.", "err"], ["destination already exists; choose a new directory", "err"], ["Wait for the current operation.", "warn"]]:
		expect(StatusLevel.of(pair[0]) == pair[1], "Status line '%s' must be %s" % [pair[0], pair[1]])
	# A destination must be a new folder under an existing parent.
	var field := PathField.new()
	shell.add_child(field)
	field.text = out
	expect(field.state == "exists" and not field.problem().is_empty(), "An existing folder must be refused as a destination")
	field.text = out.path_join("not-yet")
	expect(field.state == "new" and field.problem().is_empty(), "A new folder under an existing parent must be accepted")
	field.text = out.path_join("no-parent/not-yet")
	expect(field.state == "parent", "A destination without a parent folder must be refused")
	field.queue_free()
	# A question answers once: Enter takes the safe choice, Esc cancels.
	var answers: Array = []
	var ask := ConfirmDialog.new()
	shell.add_child(ask)
	ask.heading = "Discard W0's unapplied edit?"
	ask.message = "The form returns to W0 as last applied."
	ask.add_button("Discard", "danger", "discard", true)
	ask.add_button("Keep editing", "primary")
	ask.confirmed.connect(func(): answers.append("confirmed"))
	ask.canceled.connect(func(): answers.append("canceled"))
	ask.custom_action.connect(func(action): answers.append(action))
	ask.popup_centered()
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	ask._unhandled_key_input(enter)
	ask.popup_centered()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	ask._unhandled_key_input(escape)
	expect(answers == ["confirmed", "canceled"], "Enter must give the primary answer and Esc must cancel, once each: %s" % str(answers))
	ask.queue_free()
	# The settings file is shared with the adapter: choices written here leave its keys alone.
	var file := out.path_join("settings-roundtrip.json")
	var written := FileAccess.open(file, FileAccess.WRITE)
	written.store_string(JSON.stringify({"installation": "D:/NC", "recent": [{"path": "a"}], "seed": 3}))
	written.close()
	var settings := WorkspaceSettings.new()
	settings.load_from(file)
	expect(settings.get_value("seed") == 3 and settings.get_value("grid") == true, "Stored choices must load over the defaults")
	expect(settings.set_value("seed", 9) and settings.set_value("grid", false), "A choice must be written")
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file))
	expect(stored.get("installation") == "D:/NC" and stored.get("recent", []).size() == 1 and int(stored.get("seed", 0)) == 9 and stored.get("grid") == false, "Writing a choice must keep the adapter's keys")
	# A folder without the original data is reported, not chosen.
	expect(FolderCheck.find("") != "" or OS.get_environment("CENTURIONS_INSTALLATION").is_empty(), "The development folder must be found")
	expect(FolderCheck.holds_original_data(out) == false and FolderCheck.report(out).any(func(row): return row.label == "Original data" and row.state == "err"), "A folder without Data Files must report the original data missing")
	# A gallery of what the screens are made of.
	var gallery := PanelContainer.new()
	gallery.theme_type_variation = &"Card"
	gallery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gallery.offset_left = 60; gallery.offset_top = 60; gallery.offset_right = -60; gallery.offset_bottom = -60
	shell.add_child(gallery)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	gallery.add_child(column)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	column.add_child(cards)
	for entry in [["Import level", "Read a New Centurions level folder into a new project.", "Ctrl I", "import", true, true], ["Open checkpoint", "Reopen a saved project folder.", "Ctrl O", "folder", false, true], ["New from template", "Start a minimal mission pack.", "Ctrl N", "plus", false, false]]:
		var card := ActionCard.new()
		card.title = entry[0]; card.body = entry[1]; card.key_hint = entry[2]; card.glyph = entry[3]; card.lead = entry[4]
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards.add_child(card)
		card.set_available(entry[5])
	var rows := VBoxContainer.new()
	for entry in [["good", "New Centurions 1.3.2", "New Centurions"], ["warn", "Replay tool", "centurions-tools.exe · not found"], ["err", "Original data", "Data Files · not found"], ["idle", "Artwork cache", "made when artwork first loads"]]:
		var row := CheckRow.new()
		row.state = entry[0]; row.text = entry[1]; row.note = entry[2]
		rows.add_child(row)
	column.add_child(rows)
	var tiles := HBoxContainer.new()
	for entry in [["10", "Maps"], ["20 · 6 in use", "Stages"], ["11 tables", "Walking triggers"]]:
		var tile := StatTile.new()
		tile.value = entry[0]; tile.caption = entry[1]
		tiles.add_child(tile)
	column.add_child(tiles)
	var steps := Stepper.new()
	steps.show_steps(["Source", "Destination", "Result"], 1)
	column.add_child(steps)
	var states := VBoxContainer.new()
	for path in [out.path_join("new-folder"), out]:
		var sample := PathField.new()
		sample.text = path
		states.add_child(sample)
	column.add_child(states)
	var switches := HBoxContainer.new()
	var on := CheckButton.new(); on.text = "Map grid"; on.button_pressed = true
	var off := CheckButton.new(); off.text = "Compact layout"
	var tick := CheckBox.new(); tick.text = "Compare every byte"; tick.button_pressed = true
	var save := KbdButton.new(); save.text = "Save"; save.hint = "Ctrl S"
	var play := KbdButton.new(); play.text = "Play from here"; play.hint = "F5"; play.theme_type_variation = &"PrimaryButton"
	for node in [on, off, tick, save, play]: switches.add_child(node)
	column.add_child(switches)
	await snapshot(out.path_join("widgets-project-flows.png"))
	gallery.queue_free()
