extends PanelContainer
## The dock below the pages: the project's findings, one row each with where to
## go, and Find uses, the steps and records that name one record.
signal toggled(opened: bool)
signal changed
const Capability = preload("res://src/scripts/capability.gd")
const Glyph = preload("res://src/widgets/glyph.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

const NOUNS := {"message": "Message", "battle_extra": "Battle extra", "reward": "Reward", "choice": "Choice", "typed": "Typed encounter", "story": "Story", "stage": "Stage", "sound": "Sound", "battle": "Battle", "monster": "Monster", "walking": "Walking trigger", "item": "Item", "shop": "Shop", "extra": "Extra Codes row"}
const COLUMNS := ["Table", "Record", "Step", "Before", "This step", "After"]

var shell: Control
var count := 0
var result: Dictionary = {}
var tab := "problems"
var uses: Dictionary = {}
var find_panel := VBoxContainer.new()
var find_tree := Tree.new()
var target_label := LineEdit.new()
var replace_value := SpinBox.new()
var replace_button := Button.new()
var choose_button := Button.new()
var find_summary := Label.new()
var play_panel := VBoxContainer.new()
var play_tree := Tree.new()
var play_summary := Label.new()
var copy_button := Button.new()
var save_button := Button.new()
var _open := false
var _compact := false
var _rows: Array = []


func _ready() -> void:
	%ProblemsToggle.pressed.connect(func(): _choose("problems"))
	get_node("ProblemsContent/Head/Row/Find").pressed.connect(func(): _choose("find"))
	get_node("ProblemsContent/Head/Row/Find").disabled = false
	get_node("ProblemsContent/Head/Row/Find").toggle_mode = true
	get_node("ProblemsContent/Head/Row/PlayLog").pressed.connect(func(): _choose("play"))
	get_node("ProblemsContent/Head/Row/PlayLog").disabled = false
	get_node("ProblemsContent/Head/Row/PlayLog").toggle_mode = true
	_build_play()
	%Collapse.pressed.connect(func(): _open = not _open; _show())
	_build_find()
	_show()


func setup(owner_shell: Control) -> void:
	shell = owner_shell


func _choose(name: String) -> void:
	if _open and tab == name: _open = false
	else: tab = name; _open = true
	_show()


func is_open() -> bool:
	return _open


## In the compact layout the dock shows only while it is open; the status bar opens it.
func set_compact(on: bool) -> void:
	_compact = on
	_show()


## Opens the dock on the Play log.
func show_log() -> void:
	tab = "play"
	_open = true
	_show()


## Opens or closes the dock on its Problems tab.
func open(opened: bool) -> void:
	_open = opened
	if opened: tab = "problems"
	_show()


func _show() -> void:
	visible = _open or not _compact
	%Problems.visible = _open and tab == "problems"
	find_panel.visible = _open and tab == "find"
	play_panel.visible = _open and tab == "play"
	get_node("ProblemsContent/Head/Row/PlayLog").set_pressed_no_signal(_open and tab == "play")
	%Collapse.glyph = "chevron_down" if _open else "chevron_up"
	%ProblemsToggle.set_pressed_no_signal(_open and tab == "problems")
	get_node("ProblemsContent/Head/Row/Find").set_pressed_no_signal(_open and tab == "find")
	toggled.emit(_open)


func _build_find() -> void:
	find_panel.visible = false
	find_panel.custom_minimum_size.y = 230
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 10)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	margin.add_child(inner)
	find_panel.add_child(margin)
	get_node("ProblemsContent").add_child(find_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	inner.add_child(row)
	target_label.editable = false
	target_label.custom_minimum_size.x = 280
	row.add_child(target_label)
	find_summary.theme_type_variation = &"Dim"
	find_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	find_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(find_summary)
	var replace_label := Label.new()
	replace_label.theme_type_variation = &"Dim"
	replace_label.text = "Replace with"
	row.add_child(replace_label)
	replace_value.min_value = 0
	replace_value.max_value = 32767
	replace_value.custom_minimum_size.x = 100
	replace_value.value_changed.connect(func(_value): _fill_find())
	row.add_child(replace_value)
	choose_button.text = "Choose…"
	choose_button.pressed.connect(_choose_replacement)
	row.add_child(choose_button)
	replace_button.text = "Replace"
	replace_button.pressed.connect(replace)
	row.add_child(replace_button)
	find_tree.columns = COLUMNS.size()
	find_tree.column_titles_visible = true
	find_tree.hide_root = true
	find_tree.select_mode = Tree.SELECT_ROW
	find_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for index in range(COLUMNS.size()):
		find_tree.set_column_title(index, COLUMNS[index].to_upper())
		find_tree.set_column_expand(index, index in [1, 3, 4, 5])
		find_tree.set_column_custom_minimum_width(index, 120 if index != 2 else 56)
	find_tree.item_activated.connect(_open_row)
	inner.add_child(find_tree)


## The findings of the project, fetched again from the adapter.
func refresh() -> void:
	if shell == null or shell.summary.is_empty():
		clear()
		return
	var response: Dictionary = await shell.request_backend({"op": "problems", "installation": shell.ui("Installation").text})
	result = response.result if response.get("ok", false) else {}
	_fill()
	changed.emit()


func clear() -> void:
	result = {}
	_fill()
	changed.emit()


func _fill() -> void:
	for row in %ProblemRows.get_children(): %ProblemRows.remove_child(row); row.queue_free()
	var findings: Array = result.get("findings", [])
	count = findings.size()
	for finding in findings:
		var tone := Tokens.ERR if finding.severity == "error" else Tokens.WARN if finding.severity == "warning" else Tokens.DIM
		var count_text := ""
		if finding.get("count") != null: count_text = "%s %s" % [str(int(finding.count)), str(finding.get("unit", ""))]
		_row(tone, str(finding.message), count_text, str(finding.where.get("label", "")), finding.where)
	var counts: Dictionary = result.get("counts", {})
	%ProblemsCount.text = str(count)
	%ProblemsCount.visible = count > 0
	%ProblemsSummary.text = "%d errors · %d warnings · %d read-only" % [int(counts.get("errors", 0)), int(counts.get("warnings", 0)), int(counts.get("readonly", 0))] if not result.is_empty() else "Preservation diagnostics · 0 notices"


func _row(tone: Color, message: String, amount: String, where: String, place: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var mark := Glyph.new()
	mark.glyph = "dot"
	mark.color = tone
	mark.extent = 14.0
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	var text := Label.new()
	text.text = message
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(text)
	var number := Label.new()
	number.theme_type_variation = &"MonoDim"
	number.text = amount
	number.custom_minimum_size.x = 90
	row.add_child(number)
	var place_label := Label.new()
	place_label.text = where
	place_label.theme_type_variation = &"Mono"
	place_label.add_theme_color_override("font_color", Tokens.INFO)
	place_label.custom_minimum_size.x = 180
	place_label.clip_text = true
	row.add_child(place_label)
	var go := Button.new()
	go.text = "Go"
	go.theme_type_variation = &"GhostButton"
	go.pressed.connect(func(): shell.guard(shell.navigator.go_where.bind(place)))
	row.add_child(go)
	%ProblemRows.add_child(row)


# ── Play log ──

func _build_play() -> void:
	play_panel.visible = false
	play_panel.custom_minimum_size.y = 230
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 10)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	margin.add_child(inner)
	play_panel.add_child(margin)
	get_node("ProblemsContent").add_child(play_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	inner.add_child(row)
	play_summary.theme_type_variation = &"Dim"
	play_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_summary.text = "No play session yet · Play from here starts one"
	row.add_child(play_summary)
	copy_button.text = "Copy commands"
	copy_button.pressed.connect(func(): shell.copy_play_commands())
	row.add_child(copy_button)
	save_button.text = "Save replay…"
	save_button.pressed.connect(func(): shell.save_play_replay())
	row.add_child(save_button)
	play_tree.columns = 3
	play_tree.column_titles_visible = true
	play_tree.hide_root = true
	play_tree.select_mode = Tree.SELECT_ROW
	play_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for index in range(3):
		play_tree.set_column_title(index, ["#", "COMMAND", "EVENTS"][index])
		play_tree.set_column_expand(index, index == 2)
		play_tree.set_column_custom_minimum_width(index, [40, 280, 100][index])
	inner.add_child(play_tree)


## The commands of the session and what each one did.
func show_play(session: RefCounted) -> void:
	play_tree.clear()
	var root := play_tree.create_item()
	for entry in session.log:
		var item := play_tree.create_item(root)
		item.set_text(0, str(entry.index))
		item.set_text(1, session.name_of_command(entry.command))
		var rejected: bool = not str(entry.error).is_empty()
		item.set_text(2, "rejected · %s" % entry.error if rejected else str(entry.text))
		if rejected: item.set_custom_color(2, Tokens.WARN)
	var accepted: int = session.commands().size()
	play_summary.text = "%d commands · %d accepted" % [session.log.size(), accepted] if not session.log.is_empty() else "No play session yet · Play from here starts one"
	copy_button.disabled = accepted == 0
	save_button.disabled = accepted == 0
	if session.log.size() > 0: play_tree.scroll_to_item(root.get_child(session.log.size() - 1))


# ── Find uses ──

## Lists every step and record that names `kind` `id` and opens the Find tab.
func find_uses(kind: String, id: int, label := "") -> void:
	if shell == null or shell.summary.is_empty(): return
	var response: Dictionary = await shell.request_backend({"op": "uses", "kind": kind, "id": id})
	if not response.get("ok", false): return
	uses = response.result
	target_label.text = label if not label.is_empty() else "%s %d" % [NOUNS.get(kind, kind), id]
	replace_value.set_value_no_signal(id)
	tab = "find"
	_open = true
	_show()
	_fill_find()


## A step row's operand after the replacement value is put in its place.
func replacement(row: Dictionary, value: int) -> int:
	var old := int(row.operand)
	match str(uses.kind):
		"message": return value if old >= 0 else -value
		"stage": return (value + 1) if old >= 0 else -(value + 1)
	return value


func _step_rows() -> Array:
	return uses.get("rows", []).filter(func(row): return row.has("opcode"))


func _fill_find() -> void:
	find_tree.clear()
	var root := find_tree.create_item()
	var last := ""
	_rows = uses.get("rows", [])
	for row in _rows:
		var item := find_tree.create_item(root)
		item.set_metadata(0, row)
		var table := str(row.table)
		item.set_text(0, table if table != last else "")
		last = table
		var record := "%s %d" % [NOUNS.get(str(row.kind), str(row.kind)), int(row.id)]
		if row.kind == "walking": record = "W%d · Map %d" % [int(row.id), int(row.get("map", 0))]
		elif row.kind == "cell": record = "Map %d · %d, %d" % [int(row.get("map", 0)), int(row.get("x", 0)), int(row.get("y", 0))]
		elif row.has("branch") and int(row.branch) > 0: record += " · branch %d" % int(row.branch)
		item.set_text(1, record)
		if row.has("opcode"):
			item.set_text(2, str(int(row.slot) + 1))
			item.set_text(3, str(row.get("before", "")) if row.get("before") != null else "—")
			item.set_text(4, str(row.name))
			if int(replace_value.value) != int(uses.id): item.set_text(5, Capability.subtitle(int(row.opcode), replacement(row, int(replace_value.value)), true))
		else:
			item.set_text(4, str(row.name))
	var steps := _step_rows().size()
	find_summary.text = "%d uses in %d records · %d tables" % [int(uses.get("total", 0)), int(uses.get("records", 0)), int(uses.get("tables", 0))] + (" · first 500 shown" if uses.get("truncated", false) else "")
	replace_button.text = "Replace %d" % steps
	replace_button.disabled = steps == 0 or int(replace_value.value) == int(uses.get("id", -1)) or str(uses.get("kind", "")) in ["monster", "battle", "walking"]
	choose_button.disabled = str(uses.get("kind", "")) not in ["reward"]


func _open_row() -> void:
	var item := find_tree.get_selected()
	if item == null: return
	var row: Dictionary = item.get_metadata(0)
	if row.kind == "cell":
		shell.guard(func():
			await shell.maps.select_map(int(row.get("map", 0)))
			await shell.navigator.go_to_cell(Vector2i(int(row.x), int(row.y))))
	else: shell.guard(shell.navigator.go.bind(str(row.kind), int(row.id), int(row.slot) if row.has("slot") else -1, int(row.branch) if row.has("branch") else 0))


func _choose_replacement() -> void:
	shell.picker_dialog.show_for(str(uses.kind), int(replace_value.value), "Find uses · replace %s %d" % [str(uses.kind), int(uses.id)], func(chosen): replace_value.value = chosen)


## Drafts the replacement as one script-step edit for each step that names the record.
func replace() -> void:
	var value := int(replace_value.value)
	var made := 0
	for row in _step_rows():
		var family: String = shell.navigator.FAMILY_OF.get(str(row.kind), "")
		if family.is_empty(): continue
		shell.drafts["script_step:%s:%d:%d:%d" % [family, int(row.id), int(row.branch), int(row.slot)]] = {"kind": "script_step", "family": family, "id": int(row.id), "branch": int(row.branch), "slot": int(row.slot), "opcode": int(row.opcode), "operand": replacement(row, value)}
		made += 1
	shell._invalidate_receipt()
	shell._update_buttons()
	shell.status("Replacement drafted · %d steps · Apply edits" % made)
