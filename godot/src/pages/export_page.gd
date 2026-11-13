extends HBoxContainer
## Export level folder: what the export holds, and the new folder to write it
## to. The folder is written once, never over another, and compared with the
## import afterwards.
const Card = preload("res://src/widgets/card.gd")
const CheckRow = preload("res://src/widgets/check_row.gd")
const Glyph = preload("res://src/widgets/glyph.gd")
const KbdButton = preload("res://src/widgets/kbd_button.gd")
const KeyValueRow = preload("res://src/widgets/key_value_row.gd")
const PathField = preload("res://src/widgets/path_field.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

# What each kind of edit is called in the list of changes.
const EDIT_NAMES := {"message": "Message text", "stage_name": "Stage names", "stage_start": "Stage start locations", "stage_opening": "Stage opening",
	"floor": "Floor tiles", "walking_location": "Walking trigger placements", "walking_chance": "Walking trigger chances", "walking_target": "Walking return destinations",
	"script_step": "Script steps", "encounter_condition": "Encounter conditions", "event_activation": "Movement activations", "scroll_text": "Scrolling texts", "scroll_text_remove": "Removed scrolling texts", "resource_change": "Pictures, icons and sounds"}

var shell: Control
var _title := Label.new()
var _subtitle := Label.new()
var _steps := VBoxContainer.new()
var _source := VBoxContainer.new()
var _changes := VBoxContainer.new()
var _changes_note := Label.new()
var parent_field := PathField.new()
var name_field := LineEdit.new()
var _state := Label.new()
var _writes := VBoxContainer.new()
var _compare := CheckBox.new()
var _play := CheckBox.new()
var _back: Button
var _export: KbdButton
var _loading := false


func _init() -> void:
	_build_left()
	_build_centre()
	_build_right()


func setup(owner_shell: Control) -> void:
	shell = owner_shell
	parent_field.text_changed.connect(func(_text): _compose())
	name_field.text_changed.connect(func(_text): _compose())
	parent_field.browse_requested.connect(shell._pick_folder.bind("destination_parent"))
	_back.pressed.connect(func(): shell.guard(shell._show_route.bind(shell.last_route)))
	_export.pressed.connect(export_now)


func _column(parent: Control, width: float, pad: Vector2) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if width > 0.0: scroll.custom_minimum_size.x = width
	else: scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", int(pad.x))
	margin.add_theme_constant_override("margin_right", int(pad.x))
	margin.add_theme_constant_override("margin_top", int(pad.y))
	margin.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	return column


func _build_left() -> void:
	var column := _column(self, 360, Vector2(20, 16))
	_title.theme_type_variation = &"PageTitle"
	_title.add_theme_font_size_override("font_size", 20)
	_title.text = "Export level folder"
	column.add_child(_title)
	_subtitle.theme_type_variation = &"Muted"
	_subtitle.add_theme_font_size_override("font_size", 12)
	column.add_child(_subtitle)
	_steps.add_theme_constant_override("separation", 6)
	column.add_child(_steps)
	var source := Card.new()
	source.title = "Source"
	source.add_row(_source)
	_source.add_theme_constant_override("separation", 6)
	column.add_child(source)
	var note := HBoxContainer.new()
	note.add_theme_constant_override("separation", 8)
	var dot := Glyph.new()
	dot.glyph = "dot"
	dot.extent = 10.0
	dot.color = Tokens.INFO
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	dot.custom_minimum_size.y = 18
	note.add_child(dot)
	var words := Label.new()
	words.theme_type_variation = &"Muted"
	words.add_theme_font_size_override("font_size", 12)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.text = "Export writes a new level folder. The checkpoint and the imported level stay as they were."
	note.add_child(words)
	column.add_child(note)


func _build_centre() -> void:
	add_child(VSeparator.new())
	var column := _column(self, 0, Vector2(24, 16))
	var head := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"Heading"
	title.text = "Changes since import"
	head.add_child(title)
	column.add_child(head)
	_changes_note.theme_type_variation = &"Muted"
	_changes_note.add_theme_font_size_override("font_size", 12)
	_changes_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_changes_note.text = "Only the bytes each edit owns change; every other byte is copied."
	column.add_child(_changes_note)
	var card := Card.new()
	card.title = "Edits"
	card.add_row(_changes)
	_changes.add_theme_constant_override("separation", 8)
	column.add_child(card)


func _build_right() -> void:
	add_child(VSeparator.new())
	var column := _column(self, 470, Vector2(20, 16))
	var destination := Card.new()
	destination.title = "Destination"
	column.add_child(destination)
	var parent_title := Label.new()
	parent_title.theme_type_variation = &"Caption"
	parent_title.text = "PARENT FOLDER"
	destination.add_row(parent_title)
	parent_field.kind = "existing"
	parent_field.browse_text = "Browse…"
	destination.add_row(parent_field)
	var name_title := Label.new()
	name_title.theme_type_variation = &"Caption"
	name_title.text = "FOLDER NAME"
	destination.add_row(name_title)
	name_field.theme_type_variation = &"LineEditMono"
	destination.add_row(name_field)
	_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state.add_theme_font_size_override("font_size", 12)
	destination.add_row(_state)
	var writes := Card.new()
	writes.title = "Writes"
	_writes.add_theme_constant_override("separation", 6)
	writes.add_row(_writes)
	column.add_child(writes)
	var after := Card.new()
	after.title = "After writing"
	column.add_child(after)
	_compare.text = "Compare every byte with the import"
	_compare.button_pressed = true
	after.add_row(_compare)
	_play.text = "Play from the opening with a pinned seed"
	_play.disabled = true
	after.add_row(_play)
	var runtime := Label.new()
	runtime.theme_type_variation = &"Muted"
	runtime.add_theme_font_size_override("font_size", 12)
	runtime.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	runtime.text = "Runtime evidence is separate from format validation; match a receipt to the exact export."
	column.add_child(runtime)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	_back = Button.new()
	_back.text = "Back"
	buttons.add_child(_back)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(gap)
	_export = KbdButton.new()
	_export.name = "ExportNow"
	_export.theme_type_variation = &"PrimaryButton"
	_export.hint = "↵"
	buttons.add_child(_export)


func _line(parent: Control, key: String, value: String) -> void:
	var row := KeyValueRow.new()
	row.key = key
	row.value = value
	row.key_width = 86
	parent.add_child(row)


func _clear(box: Control) -> void:
	for child in box.get_children(): box.remove_child(child); child.queue_free()


## Fills the page from the open project and the destination the shell holds.
func refresh() -> void:
	if shell == null: return
	var summary: Dictionary = shell.summary
	_clear(_steps)
	_clear(_source)
	_clear(_changes)
	_clear(_writes)
	if summary.is_empty():
		_subtitle.text = "No project open"
		_state.text = ""
		_export.text = "Export"
		_export.disabled = true
		return
	var native: Variant = summary.get("native")
	var name: String = str(native.get("name", "")) if native is Dictionary else str(summary.get("origin", {}).get("label", ""))
	var folder := str(summary.path).replace("\\\\?\\", "").replace("\\", "/").get_file()
	_subtitle.text = "%s · %s" % [name, folder]
	var errors := 0
	var warnings := 0
	for issue in summary.get("diagnostics", []):
		if str(issue.severity) == "error": errors += 1
		else: warnings += 1
	var edits := int(summary.get("edits", 0))
	var files := int(summary.get("source_files", 0))
	for step in [["Check", "%d errors · %d warnings" % [errors, warnings], "good" if errors == 0 else "err"],
			["Review changes", "%d edit%s since import" % [edits, "" if edits == 1 else "s"], "good"],
			["Destination", "A new folder; nothing is overwritten", "good"],
			["Write and compare", "Write the folder, then compare it with the import byte by byte", "idle"]]:
		var row := CheckRow.new()
		row.text = step[0]
		row.state = step[2]
		_steps.add_child(row)
		var detail := Label.new()
		detail.theme_type_variation = &"Dim"
		detail.text = step[1]
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var inset := MarginContainer.new()
		inset.add_theme_constant_override("margin_left", 28)
		inset.add_child(detail)
		_steps.add_child(inset)
	_line(_source, "Checkpoint", folder)
	_line(_source, "Format", "Project version %d" % int(summary.get("version", 0)))
	_line(_source, "Origin", str(summary.get("origin", {}).get("label", "")))
	var opening: Variant = summary.get("opening")
	if opening is Dictionary: _line(_source, "Opening", "Map %s · %s, %s" % [str(opening.get("map")), str(opening.get("x")), str(opening.get("y"))])
	_line(_source, "Startup header", name)
	var kinds: Dictionary = summary.get("edit_kinds", {})
	if kinds.is_empty():
		var none := Label.new()
		none.theme_type_variation = &"Muted"
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.text = "No edits since import: the export is the import, byte for byte."
		_changes.add_child(none)
	for kind in kinds:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str(EDIT_NAMES.get(kind, str(kind).capitalize().replace("_", " ")))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var count := Label.new()
		count.theme_type_variation = &"Mono"
		count.text = "%d" % int(kinds[kind])
		row.add_child(count)
		_changes.add_child(row)
	_line(_writes, "Changed", "%d edit%s" % [edits, "" if edits == 1 else "s"])
	_line(_writes, "Copied", "%d project files, including sidecars" % files)
	_line(_writes, "Named header", name)
	_line(_writes, "Installation", "not touched")
	_export.text = "Export %d files" % files
	_loading = true
	var whole: String = str(shell.ui("DestinationPath").text)
	parent_field.show_path(whole.get_base_dir())
	name_field.text = whole.get_file()
	_loading = false
	_compose(false)


## Joins the parent folder and the name into the destination the shell uses.
func _compose(tell_shell := true) -> void:
	if _loading or shell == null: return
	var whole := parent_field.text.strip_edges().path_join(name_field.text.strip_edges())
	if tell_shell: shell.set_destination(whole, self)
	var exists := not name_field.text.strip_edges().is_empty() and (DirAccess.dir_exists_absolute(whole) or FileAccess.file_exists(whole))
	var parent_ok := DirAccess.dir_exists_absolute(parent_field.text.strip_edges())
	if name_field.text.strip_edges().is_empty():
		_state.text = "Name the folder to create."
		_state.add_theme_color_override("font_color", Tokens.WARN)
	elif not parent_ok:
		_state.text = "The parent folder does not exist."
		_state.add_theme_color_override("font_color", Tokens.WARN)
	elif exists:
		_state.text = "%s already exists here. Existing folders are never overwritten." % name_field.text.strip_edges()
		_state.add_theme_color_override("font_color", Tokens.WARN)
	else:
		_state.text = "New folder · it will be created"
		_state.add_theme_color_override("font_color", Tokens.GOOD)
	_export.disabled = shell.summary.is_empty() or exists or not parent_ok or name_field.text.strip_edges().is_empty()


## The shell's buttons changed: the export button follows them.
func state_changed() -> void:
	if shell != null and is_node_ready(): _compose(false)


## Shows the destination the shell holds without telling it back.
func show_destination(whole: String) -> void:
	_loading = true
	parent_field.show_path(whole.get_base_dir())
	name_field.text = whole.get_file()
	_loading = false
	_compose(false)


func export_now() -> void:
	if shell.bridge.busy or _export.disabled: return
	shell.start_export(_compare.button_pressed)
