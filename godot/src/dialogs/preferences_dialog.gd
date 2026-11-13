extends "res://src/widgets/modal_overlay.gd"
## Preferences: the folder the editor runs from (found, not chosen), where
## checkpoints and exports go, the seed Play from here pins, and the workspace.
signal output_browse_requested
signal value_changed(key: String, value: Variant)
const Card = preload("res://src/widgets/card.gd")
const CheckRow = preload("res://src/widgets/check_row.gd")
const FolderCheck = preload("res://src/services/folder_check.gd")
const PathField = preload("res://src/widgets/path_field.gd")

var output_parent := PathField.new()
var seed_field := LineEdit.new()
var grid_toggle := CheckButton.new()
var compact_toggle := CheckButton.new()
var _folder := LineEdit.new()
var _checks := VBoxContainer.new()
var _play_note := Label.new()
var _loading := false


func _init() -> void:
	super()
	title = "Preferences"
	panel_size = Vector2(740, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	body.add_child(column)
	var folder_card := Card.new()
	folder_card.title = "This folder"
	column.add_child(folder_card)
	var about := Label.new()
	about.theme_type_variation = &"Muted"
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.text = "The editor runs from the New Centurions folder. Artwork is read locally and cached separately from the project."
	folder_card.add_row(about)
	_folder.editable = false
	_folder.theme_type_variation = &"LineEditMono"
	folder_card.add_row(_folder)
	_checks.add_theme_constant_override("separation", 8)
	folder_card.add_row(_checks)
	_play_note.theme_type_variation = &"Muted"
	_play_note.add_theme_font_size_override("font_size", 12)
	_play_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	folder_card.add_row(_play_note)
	var outputs := Card.new()
	outputs.title = "Checkpoints and exports"
	column.add_child(outputs)
	var output_row := HBoxContainer.new()
	output_row.add_theme_constant_override("separation", 12)
	var output_label := Label.new()
	output_label.theme_type_variation = &"Dim"
	output_label.text = "Output parent"
	output_row.add_child(output_label)
	output_parent.kind = "existing"
	output_parent.browse_text = "Browse parent…"
	output_parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_parent.browse_requested.connect(func(): output_browse_requested.emit())
	output_parent.text_changed.connect(func(text): if not _loading: value_changed.emit("output_parent", text.strip_edges()))
	output_row.add_child(output_parent)
	outputs.add_row(output_row)
	var rule := Label.new()
	rule.theme_type_variation = &"Muted"
	rule.add_theme_font_size_override("font_size", 12)
	rule.text = "Choose a new directory whose parent exists. Existing projects and exports are never replaced."
	outputs.add_row(rule)
	var play := Card.new()
	play.title = "Play from here"
	column.add_child(play)
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 12)
	var seed_words := VBoxContainer.new()
	seed_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var seed_title := Label.new()
	seed_title.theme_type_variation = &"Strong"
	seed_title.text = "Seed"
	seed_words.add_child(seed_title)
	var seed_note := Label.new()
	seed_note.theme_type_variation = &"Muted"
	seed_note.add_theme_font_size_override("font_size", 12)
	seed_note.text = "A pinned seed gives the same rolls on every run."
	seed_words.add_child(seed_note)
	seed_row.add_child(seed_words)
	seed_field.custom_minimum_size.x = 90
	seed_field.theme_type_variation = &"LineEditMono"
	seed_field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seed_field.text_changed.connect(_seed_edited)
	seed_row.add_child(seed_field)
	var pinned := CheckRow.new()
	pinned.text = "Pinned"
	pinned.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pinned.custom_minimum_size.x = 96
	seed_row.add_child(pinned)
	play.add_row(seed_row)
	var workspace := Card.new()
	workspace.title = "Workspace"
	column.add_child(workspace)
	workspace.add_row(_toggle_row(grid_toggle, "Map grid", "", "grid"))
	workspace.add_row(_toggle_row(compact_toggle, "Compact layout", "The side docks fold into the rail when the window is narrower than 1600 pixels.", "compact"))
	add_button("Done", "primary").pressed.connect(close)


func _toggle_row(toggle: CheckButton, name: String, note: String, key: String) -> Control:
	var row := HBoxContainer.new()
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.theme_type_variation = &"Strong"
	label.text = name
	words.add_child(label)
	if not note.is_empty():
		var hint := Label.new()
		hint.theme_type_variation = &"Muted"
		hint.add_theme_font_size_override("font_size", 12)
		hint.text = note
		words.add_child(hint)
	row.add_child(words)
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.toggled.connect(func(on): if not _loading: value_changed.emit(key, on))
	row.add_child(toggle)
	return row


func _seed_edited(text: String) -> void:
	if _loading: return
	var cleaned := text.strip_edges()
	if cleaned.is_valid_int(): value_changed.emit("seed", int(cleaned))


## Shows the stored choices and what the folder check found.
func show_values(values: Dictionary, folder: String, report: Array, default_output: String) -> void:
	_loading = true
	output_parent.show_path(str(values.get("output_parent", "")) if not str(values.get("output_parent", "")).is_empty() else default_output)
	seed_field.text = str(int(values.get("seed", 12)))
	grid_toggle.button_pressed = bool(values.get("grid", true))
	compact_toggle.button_pressed = bool(values.get("compact", true))
	_loading = false
	_folder.text = PathField.shown(folder) if not folder.is_empty() else "No New Centurions folder found beside the editor"
	for child in _checks.get_children(): _checks.remove_child(child); child.queue_free()
	for row in report:
		var check := CheckRow.new()
		check.text = row.label
		check.state = row.state
		check.note = row.note
		_checks.add_child(check)
	_play_note.text = FolderCheck.play_note(report)
	_play_note.visible = not _play_note.text.is_empty()
