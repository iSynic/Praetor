extends "res://src/widgets/modal_overlay.gd"
## Export native level, once the folder is written: what was written, how it
## differs from the import, and the runtime evidence, which is separate.
signal receipt_requested
signal show_folder_requested
signal done
const Card = preload("res://src/widgets/card.gd")
const CheckRow = preload("res://src/widgets/check_row.gd")
const Stepper = preload("res://src/widgets/stepper.gd")

var _stepper := Stepper.new()
var _progress := ProgressBar.new()
var _count := Label.new()
var _line := Label.new()
var _table_card := Card.new()
var _table := GridContainer.new()
var _others := Label.new()
var _checks_card := Card.new()
var _checks := VBoxContainer.new()
var _runtime_card := PanelContainer.new()
var _runtime_body := VBoxContainer.new()
var runtime_status := Label.new()
var _receipt: Button


func _init() -> void:
	super()
	title = "Export native level"
	panel_size = Vector2(1000, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	body.add_child(column)
	var head := HBoxContainer.new()
	_stepper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_stepper)
	_count.theme_type_variation = &"MonoDim"
	head.add_child(_count)
	column.add_child(head)
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 6
	column.add_child(_progress)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_line)
	_table_card.title = "Byte comparison with the import"
	column.add_child(_table_card)
	_table.columns = 3
	_table.add_theme_constant_override("h_separation", 40)
	_table.add_theme_constant_override("v_separation", 6)
	_table_card.add_row(_table)
	_others.theme_type_variation = &"Muted"
	_others.add_theme_font_size_override("font_size", 12)
	_table_card.add_row(_others)
	_checks_card.title = "Written folder"
	_checks_card.dot_color = Tokens.GOOD
	column.add_child(_checks_card)
	_checks.add_theme_constant_override("separation", 8)
	_checks_card.add_row(_checks)
	# The runtime evidence line is a plain child so the shell can find it by name.
	_runtime_card.theme_type_variation = &"Card"
	column.add_child(_runtime_card)
	_runtime_body.add_theme_constant_override("separation", 10)
	_runtime_card.add_child(_runtime_body)
	var runtime_title := Label.new()
	runtime_title.theme_type_variation = &"CaptionMuted"
	runtime_title.text = "RUNTIME"
	_runtime_body.add_child(runtime_title)
	runtime_status.theme_type_variation = &"Muted"
	runtime_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	runtime_status.text = "No receipt matched to this exact export. Loading, prologue, and gameplay are separate checks."
	_runtime_body.add_child(runtime_status)
	var runtime_row := HBoxContainer.new()
	_receipt = Button.new()
	_receipt.text = "Match a local validation receipt…"
	_receipt.pressed.connect(func(): receipt_requested.emit())
	runtime_row.add_child(_receipt)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	runtime_row.add_child(spacer)
	var untouched := Label.new()
	untouched.theme_type_variation = &"Dim"
	untouched.text = "The installation is not changed by export"
	runtime_row.add_child(untouched)
	_runtime_body.add_child(runtime_row)
	var folder := add_button("Show in folder")
	folder.pressed.connect(func(): show_folder_requested.emit())
	folder.reparent(footer_left)
	folder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_button("Done", "primary").pressed.connect(func(): close(); done.emit())


## `result` is the export's reply, `comparison` the byte comparison with the
## import (see ExportComparison) and `status` the line the status bar shows.
func show_result(result: Dictionary, comparison: Dictionary, status: String) -> void:
	subtitle = str(result.get("native_scenario_name", ""))
	var files := int(result.get("files", 0))
	_stepper.show_steps(["Write", "Publish", "Compare with the import"], 3)
	_progress.max_value = maxf(1.0, files)
	_progress.value = files
	_count.text = "%d of %d files written" % [files, files]
	_line.text = status
	for child in _table.get_children(): _table.remove_child(child); child.queue_free()
	var changed: Array = comparison.get("changed", [])
	_table_card.visible = true
	_table_card.right.get_children().map(func(node): node.queue_free())
	var total := Label.new()
	total.theme_type_variation = &"MonoDim"
	total.text = "%d files · %d bytes" % [changed.size(), int(comparison.get("bytes", 0))]
	_table_card.right.add_child(total)
	if changed.is_empty():
		var same := Label.new()
		same.theme_type_variation = &"Muted"
		same.text = "Every file is byte for byte the import."
		_table.add_child(same)
		_table.columns = 1
	else:
		_table.columns = 3
		for heading in ["FILE", "SIZE", "CHANGED"]:
			var caption := Label.new()
			caption.theme_type_variation = &"Caption"
			caption.text = heading
			_table.add_child(caption)
		for entry in changed:
			var name := Label.new()
			name.theme_type_variation = &"Strong"
			name.text = str(entry.name)
			_table.add_child(name)
			var size := Label.new()
			size.theme_type_variation = &"Mono"
			size.text = "%d bytes" % int(entry.size)
			_table.add_child(size)
			var bytes := Label.new()
			bytes.theme_type_variation = &"TagWarn"
			bytes.text = "%d bytes" % int(entry.bytes)
			_table.add_child(bytes)
	var copied := int(comparison.get("copied", 0))
	_others.text = "%d other file%s copied byte for byte, sidecars included" % [copied, "" if copied == 1 else "s"]
	for child in _checks.get_children(): _checks.remove_child(child); child.queue_free()
	var written := CheckRow.new()
	written.text = "The folder holds every file the project lists"
	written.state = "good" if int(comparison.get("files", 0)) == files else "err"
	written.note = "%d of %d" % [int(comparison.get("files", 0)), files]
	_checks.add_child(written)
	var exact := CheckRow.new()
	exact.text = "Only the bytes the edits own differ from the import" if not changed.is_empty() else "The export is the import, byte for byte"
	exact.state = "good" if comparison.get("unreadable", []).is_empty() else "warn"
	exact.note = "%d bytes" % int(comparison.get("bytes", 0)) if comparison.get("unreadable", []).is_empty() else "%d not compared" % comparison.unreadable.size()
	_checks.add_child(exact)
	var added: Array = comparison.get("added", [])
	if not added.is_empty():
		var fresh := CheckRow.new()
		fresh.text = "Files the edits added to the project"
		fresh.state = "good"
		fresh.note = ", ".join(added)
		_checks.add_child(fresh)
