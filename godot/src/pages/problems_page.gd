extends HBoxContainer
## Problems: what the checks found, with where to go, and the capability map:
## each operation the reconstruction records, how it is evidenced, whether the
## editor has a form for it and how many steps of this project use it.
const Capability = preload("res://src/scripts/capability.gd")
const Card = preload("res://src/widgets/card.gd")
const KeyValueRow = preload("res://src/widgets/key_value_row.gd")
const PageHeader = preload("res://src/widgets/page_header.gd")
const StatTile = preload("res://src/widgets/stat_tile.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

const SHOWN_OPERATIONS := 22

var shell: Control
var filter := "all"
var selected_opcode := 9
var header := PageHeader.new()
var _tiles: Dictionary = {}
var _filters: Dictionary = {}
var _group := ButtonGroup.new()
var _meter := ProgressBar.new()
var _editable := Label.new()
var _preserved := Label.new()
var _findings := VBoxContainer.new()
var _verdict := Label.new()
var _capability := VBoxContainer.new()
var _detail := VBoxContainer.new()
var _check: Button


func _init() -> void:
	add_theme_constant_override("separation", 12)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 250
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 8)
	for entry in [["errors", "Errors"], ["warnings", "Warnings"], ["readonly", "Read-only"]]:
		var tile := StatTile.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.caption = entry[1]
		tile.value = "0"
		tiles.add_child(tile)
		_tiles[entry[0]] = tile
	left.add_child(tiles)
	var findings_head := _caption("Findings")
	left.add_child(findings_head)
	for entry in [["all", "All findings"], ["error", "Errors"], ["warning", "Warnings"], ["readonly", "Read-only"]]:
		var button := Button.new()
		button.theme_type_variation = &"RowButton"
		button.toggle_mode = true
		button.button_group = _group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.set_pressed_no_signal(entry[0] == filter)
		var key: String = entry[0]
		button.pressed.connect(func(): filter = key; _show_findings())
		left.add_child(button)
		_filters[key] = button
	left.add_child(_caption("Capability"))
	var operations := Button.new()
	operations.theme_type_variation = &"RowButton"
	operations.alignment = HORIZONTAL_ALIGNMENT_LEFT
	operations.text = "Operations  %d" % Capability.known_count()
	left.add_child(operations)
	for name in ["Fields", "Spell effects"]:
		var later := Button.new()
		later.theme_type_variation = &"RowButton"
		later.alignment = HORIZONTAL_ALIGNMENT_LEFT
		later.text = name
		later.disabled = true
		later.tooltip_text = "The capability data holds operations only"
		left.add_child(later)
	left.add_child(_caption("Steps in this project"))
	_meter.show_percentage = false
	_meter.custom_minimum_size.y = 8
	left.add_child(_meter)
	_editable.theme_type_variation = &"Mono"
	left.add_child(_editable)
	_preserved.theme_type_variation = &"MonoDim"
	left.add_child(_preserved)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 10)
	scroll.add_child(centre)
	header.mark(Tokens.WARN)
	header.title.text = "Findings"
	_check = header.add_button("Check project")
	_check.pressed.connect(func(): shell.check_project())
	centre.add_child(header)
	var findings := Card.new()
	findings.title = "Finding"
	findings.right.add_child(_verdict)
	_verdict.theme_type_variation = &"Dim"
	_findings.add_theme_constant_override("separation", 6)
	findings.add_row(_findings)
	centre.add_child(findings)
	var map := Card.new()
	map.title = "Capability map"
	_capability.add_theme_constant_override("separation", 2)
	map.add_row(_capability)
	centre.add_child(map)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 270
	side.add_theme_constant_override("separation", 10)
	_detail.add_theme_constant_override("separation", 10)
	side.add_child(_detail)
	add_child(side)


func setup(owner_shell: Control) -> void:
	shell = owner_shell


func _caption(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"CaptionMuted"
	label.uppercase = true
	label.text = text
	return label


## Draws the findings and the map from what the dock last fetched.
func refresh() -> void:
	var result: Dictionary = shell.problems.result
	var counts: Dictionary = result.get("counts", {})
	for key in _tiles: _tiles[key].value = str(int(counts.get(key, 0)))
	_filters.all.text = "All findings  %d" % int(shell.problems.count)
	_filters.error.text = "Errors  %d" % int(counts.get("errors", 0))
	_filters.warning.text = "Warnings  %d" % int(counts.get("warnings", 0))
	_filters.readonly.text = "Read-only  %d" % int(counts.get("readonly", 0))
	var steps: Dictionary = result.get("steps", {})
	_meter.max_value = maxf(1.0, float(steps.get("used", 1)))
	_meter.value = float(steps.get("editable", 0))
	_editable.text = "Editable  %d of %d" % [int(steps.get("editable", 0)), int(steps.get("used", 0))]
	_preserved.text = "Preserved  %d · %d operations" % [int(steps.get("preserved", 0)), int(steps.get("preserved_operations", 0))]
	header.sub.text = str(result.get("checked", ""))
	_show_findings()
	_show_operations()
	_show_detail()


func _show_findings() -> void:
	for child in _findings.get_children(): _findings.remove_child(child); child.queue_free()
	var result: Dictionary = shell.problems.result
	var counts: Dictionary = result.get("counts", {})
	_verdict.text = "No errors · export allowed" if int(counts.get("errors", 0)) == 0 else "%d errors" % int(counts.errors)
	for finding in result.get("findings", []):
		if filter != "all" and finding.severity != filter: continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var mark := Label.new()
		mark.text = "●"
		mark.add_theme_color_override("font_color", Tokens.ERR if finding.severity == "error" else Tokens.WARN if finding.severity == "warning" else Tokens.DIM)
		row.add_child(mark)
		var text := Label.new()
		text.text = str(finding.message)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var amount := Label.new()
		amount.theme_type_variation = &"MonoDim"
		amount.text = "%d %s" % [int(finding.count), str(finding.unit)] if finding.get("count") != null else ""
		amount.custom_minimum_size.x = 80
		row.add_child(amount)
		var place := Label.new()
		place.theme_type_variation = &"Mono"
		place.text = str(finding.where.get("label", ""))
		place.add_theme_color_override("font_color", Tokens.INFO)
		place.custom_minimum_size.x = 130
		place.clip_text = true
		row.add_child(place)
		var go := Button.new()
		go.text = "Go"
		go.theme_type_variation = &"GhostButton"
		var target: Dictionary = finding.where
		go.pressed.connect(func(): shell.guard(shell.navigator.go_where.bind(target)))
		row.add_child(go)
		_findings.add_child(row)


## The operations the reconstruction records that have a form or that a step of
## this project uses, the most used first.
func _show_operations() -> void:
	for child in _capability.get_children(): _capability.remove_child(child); child.queue_free()
	var used: Dictionary = {}
	var most := 1
	for entry in shell.problems.result.get("operations", []):
		used[int(entry.opcode)] = entry
		most = maxi(most, int(entry.steps))
	var codes: Array = []
	for code in used.keys(): codes.append(int(code))
	for form in Capability.forms():
		if int(form[0]) not in codes: codes.append(int(form[0]))
	codes.sort_custom(func(a, b): return int(used.get(a, {}).get("steps", 0)) > int(used.get(b, {}).get("steps", 0)) or (int(used.get(a, {}).get("steps", 0)) == int(used.get(b, {}).get("steps", 0)) and a < b))
	_capability.add_child(_operation_row(["OP", "OPERATION", "EVIDENCE", "EDITOR", "FORM", "STEPS", "RECORDS", "USE"], true, -1, 0))
	var shown := 0
	for code in codes:
		if shown >= SHOWN_OPERATIONS: break
		var entry: Dictionary = used.get(code, {})
		var row := Capability.row(code)
		var name := str(row.get("operation", scripts_label(code)))
		_capability.add_child(_operation_row([str(code), name, str(row.get("status", "")), str(row.get("editor", "")), "step form" if Capability.has_form(code) else "preserved", str(int(entry.get("steps", 0))), str(int(entry.get("records", 0))), float(entry.get("steps", 0)) / most], false, code, most))
		shown += 1
	var more := Label.new()
	more.theme_type_variation = &"Dim"
	more.text = "+ %d more operations" % maxi(0, Capability.known_count() - shown)
	_capability.add_child(more)


func scripts_label(code: int) -> String:
	return Capability.name_of(code, true) if Capability.has_form(code) else "Opcode %d" % code


func _operation_row(cells: Array, heading: bool, code: int, _most: int) -> Control:
	var widths := [44, 0, 120, 70, 90, 60, 70, 110]
	var button := Button.new()
	button.theme_type_variation = &"RowButton"
	button.toggle_mode = not heading
	button.disabled = heading
	button.custom_minimum_size.y = 30
	button.set_pressed_no_signal(code == selected_opcode)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in range(cells.size()):
		var control: Control
		if index == 7 and not heading:
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.max_value = 1.0
			bar.value = float(cells[index])
			bar.custom_minimum_size = Vector2(widths[index], 6)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			control = bar
		else:
			var label := Label.new()
			label.text = str(cells[index])
			label.clip_text = true
			label.theme_type_variation = &"CaptionMuted" if heading else (&"Mono" if index in [0, 5, 6] else &"")
			if not heading and index == 2: label.add_theme_color_override("font_color", Tokens.GOOD if str(cells[index]) == "native-verified" else Tokens.INFO)
			if not heading and index == 3: label.add_theme_color_override("font_color", Tokens.WARN if str(cells[index]) == "warn" else Tokens.GOOD)
			control = label
		if widths[index] == 0: control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else: control.custom_minimum_size.x = widths[index]
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(control)
	button.add_child(line)
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	if not heading: button.pressed.connect(func(): selected_opcode = code; _show_operations(); _show_detail())
	return button


func _show_detail() -> void:
	for child in _detail.get_children(): _detail.remove_child(child); child.queue_free()
	var code := selected_opcode
	var row := Capability.row(code)
	var name := Label.new()
	name.theme_type_variation = &"PageTitle"
	name.text = str(row.get("operation", scripts_label(code)))
	var title := Label.new()
	title.theme_type_variation = &"Dim"
	title.text = "Opcode %d" % code
	_detail.add_child(title)
	_detail.add_child(name)
	var rule := Card.new()
	rule.title = "Rule"
	_detail.add_child(rule)
	_fact(rule, "Operand", Capability.takes(code) if Capability.has_form(code) else "Copied as recorded")
	_fact(rule, "Engine", "%s · %d open diagnostics" % [str(row.get("editor", "")), int(row.get("open_diagnostics", 0))])
	_fact(rule, "Step form", "yes" if Capability.has_form(code) else "none; the step is preserved")
	var here := Card.new()
	here.title = "In this project"
	_detail.add_child(here)
	var entry: Dictionary = {}
	for candidate in shell.problems.result.get("operations", []):
		if int(candidate.opcode) == code: entry = candidate
	_fact(here, "Steps", str(int(entry.get("steps", 0))))
	_fact(here, "Records", str(int(entry.get("records", 0))))
	var evidence := Card.new()
	evidence.title = "Evidence"
	_detail.add_child(evidence)
	_fact(evidence, "Status", str(row.get("status", "not recorded")))
	var source := Label.new()
	source.theme_type_variation = &"Dim"
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	source.text = str(row.get("evidence", row.get("behavior", ""))) if row.get("evidence", null) != null or row.get("behavior", null) != null else "No evidence is recorded for this operation."
	evidence.add_row(source)


func _fact(card: Card, key: String, value: String) -> void:
	var row := KeyValueRow.new()
	row.key = key
	row.value = value
	row.key_width = 80
	card.add_row(row)
