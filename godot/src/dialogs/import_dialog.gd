extends "res://src/widgets/modal_overlay.gd"
## Import level: the source folder that was read, where the new checkpoint
## goes, and what the import produced.
signal import_requested
signal another_requested
signal template_requested
signal open_requested
signal browse_requested
const Card = preload("res://src/widgets/card.gd")
const ContentsGrid = preload("res://src/widgets/contents_grid.gd")
const KeyValueRow = preload("res://src/widgets/key_value_row.gd")
const NoticeList = preload("res://src/widgets/notice_list.gd")
const PathField = preload("res://src/widgets/path_field.gd")
const Stepper = preload("res://src/widgets/stepper.gd")

var destination := PathField.new()
var _stepper := Stepper.new()
var _source_card := Card.new()
var _folder := LineEdit.new()
var _read := Label.new()
var _destination_card := Card.new()
var _project := Label.new()
var _error := Label.new()
var _result_card := Card.new()
var _name := Label.new()
var _origin := Label.new()
var _header := Label.new()
var _tiles := ContentsGrid.new()
var _notices_title := Label.new()
var _notices := NoticeList.new()
var _note := Label.new()
var _cancel: Button
var _import: Button
var _another: Button
var _template: Button
var _open: Button


func _init() -> void:
	super()
	title = "Import level"
	panel_size = Vector2(960, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	body.add_child(column)
	column.add_child(_stepper)
	_source_card.title = "Source"
	_source_card.dot_color = Tokens.GOOD
	column.add_child(_source_card)
	var folder_row := KeyValueRow.new()
	folder_row.key = "Folder"
	_folder.editable = false
	_folder.theme_type_variation = &"LineEditMono"
	folder_row.set_control(_folder)
	_source_card.add_row(folder_row)
	var read_row := KeyValueRow.new()
	read_row.key = "Read"
	read_row.set_control(_read)
	_read.theme_type_variation = &"Mono"
	_source_card.add_row(read_row)
	_destination_card.title = "Destination"
	_destination_card.dot_color = Tokens.GOOD
	column.add_child(_destination_card)
	var checkpoint_row := KeyValueRow.new()
	checkpoint_row.key = "Checkpoint"
	checkpoint_row.set_control(destination)
	destination.browse_text = "Browse…"
	destination.browse_requested.connect(func(): browse_requested.emit())
	_destination_card.add_row(checkpoint_row)
	var project_row := KeyValueRow.new()
	project_row.key = "Project"
	project_row.set_control(_project)
	_project.theme_type_variation = &"Mono"
	_destination_card.add_row(project_row)
	_error.theme_type_variation = &"TagErr"
	_error.visible = false
	_destination_card.add_row(_error)
	_result_card.title = "Result"
	_result_card.dot_color = Tokens.GOOD
	column.add_child(_result_card)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_name.theme_type_variation = &"Heading"
	head.add_child(_name)
	_origin.theme_type_variation = &"Badge"
	_origin.text = "imported"
	_origin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_origin)
	_header.theme_type_variation = &"MonoDim"
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_header)
	_result_card.add_row(head)
	_tiles.columns = 6
	_result_card.add_row(_tiles)
	_notices_title.theme_type_variation = &"CaptionMuted"
	_result_card.add_row(_notices_title)
	_result_card.add_row(_notices)
	_note.theme_type_variation = &"Muted"
	_note.add_theme_font_size_override("font_size", 12)
	_note.text = "The source folder is only read. Keep this checkpoint unchanged to use it as a template for new scenarios."
	column.add_child(_note)
	_another = add_button("Import another…")
	_another.pressed.connect(func(): another_requested.emit())
	_another.reparent(footer_left)
	_another.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cancel = add_button("Cancel")
	_cancel.pressed.connect(close)
	_import = add_button("Import", "primary")
	_import.pressed.connect(func(): import_requested.emit())
	_template = add_button("New from template…")
	_template.pressed.connect(func(): template_requested.emit())
	_open = add_button("Open project", "primary")
	_open.pressed.connect(func(): open_requested.emit())


## The dialog before the import: the folder to read and where to put it.
func show_source(source: String, folder_summary: String, version: int) -> void:
	subtitle = source.get_file()
	_stepper.show_steps(["Source", "Destination", "Result"], 1)
	_folder.text = PathField.shown(source)
	_read.text = folder_summary
	_project.text = "version %d · imported · 0 edits" % version if version > 0 else "imported · 0 edits"
	_error.visible = false
	destination.refresh()
	_set_stage("destination")


func show_failure(message: String) -> void:
	_error.text = message
	_error.visible = true
	_stepper.show_steps(["Source", "Destination", "Result"], 1, 1)
	_set_stage("destination")


func show_result(summary: Dictionary) -> void:
	var native: Variant = summary.get("native")
	var name_text: String = str(native.get("name", "")) if native is Dictionary else ""
	if name_text.is_empty(): name_text = str(summary.get("origin", {}).get("label", "Imported level"))
	subtitle = name_text
	_stepper.show_steps(["Source", "Destination", "Result"], 3)
	_name.text = name_text
	_header.text = "scenario header: " + name_text
	_tiles.show_contents(summary.get("contents", {}))
	var kept: Array = summary.get("warnings", []).filter(func(notice): return not str(notice).begins_with("Runtime evidence"))
	_notices_title.text = "PRESERVATION · %d NOTICE%s" % [kept.size(), "" if kept.size() == 1 else "S"]
	_notices.show_notices(kept)
	_project.text = "version %d · imported · %d edits" % [int(summary.get("version", 0)), int(summary.get("edits", 0))]
	_set_stage("result")


func _set_stage(stage: String) -> void:
	var done := stage == "result"
	if done: destination.lock("new folder")
	else: destination.unlock()
	_result_card.visible = done
	_note.visible = done
	_cancel.visible = not done
	_import.visible = not done
	_another.visible = done
	_template.visible = done
	_open.visible = done
	dismissible = true
	if done: _open.call_deferred("grab_focus")
	else: _import.call_deferred("grab_focus")
