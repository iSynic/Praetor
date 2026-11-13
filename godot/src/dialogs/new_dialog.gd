extends "res://src/widgets/modal_overlay.gd"
## New scenario from template: a name, an unchanged imported checkpoint to
## start from, and a folder for the new checkpoint.
signal create_requested
signal template_browse_requested
signal destination_browse_requested
const Card = preload("res://src/widgets/card.gd")
const CheckRow = preload("res://src/widgets/check_row.gd")
const KeyValueRow = preload("res://src/widgets/key_value_row.gd")
const PathField = preload("res://src/widgets/path_field.gd")

const KEEPS := [
	"All maps and supporting catalogs are inherited and retained",
	"Global hooks, prologue, media and unresolved bootstrap bytes remain inherited",
	"The original Mission menu needs a matching scenario name and compatible slot; no installation is performed",
	"Floor passability and original-game scenario loading require separate verification",
]

var scenario_name := LineEdit.new()
var template := PathField.new()
var destination := PathField.new()
var _gate_badge := Label.new()
var _gate_rows := VBoxContainer.new()
var _error := Label.new()
var _create: Button


func _init() -> void:
	super()
	title = "New scenario from template"
	panel_size = Vector2(980, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	body.add_child(column)
	var intro := Label.new()
	intro.theme_type_variation = &"Muted"
	intro.text = "Uses an unchanged imported checkpoint; support data remains inherited."
	column.add_child(intro)
	var scenario := Card.new()
	scenario.title = "Scenario"
	column.add_child(scenario)
	var name_row := KeyValueRow.new()
	name_row.key = "Scenario name"
	name_row.key_width = 110
	scenario_name.placeholder_text = "Native scenario name"
	name_row.set_control(scenario_name)
	scenario.add_row(name_row)
	var template_row := KeyValueRow.new()
	template_row.key = "Template"
	template_row.key_width = 110
	template.kind = "existing"
	template.browse_text = "Choose…"
	template.placeholder = "Unchanged imported checkpoint"
	template.browse_requested.connect(func(): template_browse_requested.emit())
	template.text_changed.connect(func(_text): show_gate())
	template_row.set_control(template)
	scenario.add_row(template_row)
	var destination_row := KeyValueRow.new()
	destination_row.key = "Destination"
	destination_row.key_width = 110
	destination.browse_requested.connect(func(): destination_browse_requested.emit())
	destination_row.set_control(destination)
	scenario.add_row(destination_row)
	_error.theme_type_variation = &"TagErr"
	_error.visible = false
	scenario.add_row(_error)
	var gate := Card.new()
	gate.title = "Unchanged gate"
	gate.dot_color = Tokens.DIM
	column.add_child(gate)
	_gate_badge.theme_type_variation = &"BadgeDim"
	gate.right.add_child(_gate_badge)
	_gate_rows.add_theme_constant_override("separation", 8)
	gate.add_row(_gate_rows)
	var keeps := Card.new()
	keeps.title = "What the new scenario keeps"
	column.add_child(keeps)
	for line in KEEPS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var dot := preload("res://src/widgets/glyph.gd").new()
		dot.glyph = "dot"
		dot.extent = 10.0
		dot.color = Tokens.DIM
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		dot.custom_minimum_size.y = 18
		row.add_child(dot)
		var label := Label.new()
		label.text = line
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		keeps.add_row(row)
	add_button("Cancel").pressed.connect(close)
	_create = add_button("Create scenario", "primary")
	_create.pressed.connect(func(): create_requested.emit())
	show_gate()


## The checks the template answers before anything is written: its edits and
## new records, read from the checkpoint's manifest. The export, reimport and
## comparison run when the scenario is created.
func show_gate() -> void:
	for child in _gate_rows.get_children(): _gate_rows.remove_child(child); child.queue_free()
	var path := template.text.strip_edges()
	var manifest: Variant = null
	if not path.is_empty() and FileAccess.file_exists(path.path_join("project.json")):
		manifest = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("project.json")))
	var known: bool = manifest is Dictionary
	var edits: int = manifest.get("edits", []).size() if known else 0
	var rows: int = manifest.get("allocations", []).size() if known else 0
	var clean: bool = known and edits == 0 and rows == 0
	var first := CheckRow.new()
	first.text = "Template has no edits and no new records"
	first.state = "idle" if not known else ("good" if clean else "err")
	first.note = "%d · %d" % [edits, rows] if known else ""
	_gate_rows.add_child(first)
	for line in ["Exported to a scratch folder", "Reimported and reopened", "Every file and directory compares equal"]:
		var row := CheckRow.new()
		row.text = line
		row.state = "idle"
		row.note = "when the scenario is created"
		_gate_rows.add_child(row)
	_gate_badge.text = "template has edits" if known and not clean else ("ready" if clean else "choose a template")
	_gate_badge.theme_type_variation = &"BadgeErr" if known and not clean else (&"BadgeGood" if clean else &"BadgeDim")


func show_form(message := "") -> void:
	_error.text = message
	_error.visible = not message.is_empty()
	template.refresh()
	destination.refresh()
	show_gate()
	scenario_name.call_deferred("grab_focus")
