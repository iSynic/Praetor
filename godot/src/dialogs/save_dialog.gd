extends "res://src/widgets/modal_overlay.gd"
## Save new checkpoint: a folder that does not exist yet. A save writes a new
## folder and never replaces one.
signal save_requested
signal browse_requested
const PathField = preload("res://src/widgets/path_field.gd")

var destination := PathField.new()
var _error := Label.new()
var _save: Button


func _init() -> void:
	super()
	title = "Save new checkpoint"
	panel_size = Vector2(620, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	body.add_child(column)
	destination.browse_requested.connect(func(): browse_requested.emit())
	column.add_child(destination)
	_error.theme_type_variation = &"TagErr"
	_error.visible = false
	column.add_child(_error)
	var note := Label.new()
	note.theme_type_variation = &"Muted"
	note.add_theme_font_size_override("font_size", 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Save writes a new checkpoint folder and never replaces one. A failed save leaves the project and its drafts as they were."
	column.add_child(note)
	add_button("Cancel").pressed.connect(close)
	_save = add_button("Save", "primary")
	_save.pressed.connect(func(): save_requested.emit())


## Opens the dialog for `action`: "save" or the reopened form after a failure.
func show_form(message := "") -> void:
	_error.text = message
	_error.visible = not message.is_empty()
	destination.refresh()
	if not message.is_empty(): destination.edit.add_theme_color_override("font_color", Color.WHITE)
	_save.call_deferred("grab_focus")
