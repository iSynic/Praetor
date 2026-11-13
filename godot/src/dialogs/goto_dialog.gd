extends "res://src/widgets/modal_overlay.gd"
## Go to: one field that finds monsters, battles, messages, triggers, stories
## and a cell of the open map by id, name or text, and opens the one chosen.
signal chosen(entry: Dictionary)

# [family, title, badge, record kind, colour]
const GROUPS := [
	["monsters", "Monsters", "MON", "monster", "combat"],
	["battles", "Battles", "BAT", "battle", "combat"],
	["messages", "Messages", "MSG", "message", "message"],
	["texts", "Texts", "TEXT", "text", "media"],
	["cells", "Cells", "CELL", "cell", "flow"],
	["triggers", "Triggers", "W", "walking", "flow"],
	["stories", "Stories", "STORY", "story", "flow"],
]
const SHOWN := 6

var shell: Control
var field := LineEdit.new()
var entries: Array = []
var selected := 0
var family := ""
var totals: Dictionary = {}
var _count := Label.new()
var _chips := HFlowContainer.new()
var _results := VBoxContainer.new()
var _results_scroll := ScrollContainer.new()
var _timer := Timer.new()
var _serial := 0
var _chip_group := ButtonGroup.new()


func _init() -> void:
	super()
	title = "Go to"
	panel_size = Vector2(760, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	body.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	field.placeholder_text = "Go to map, trigger, story, message or cell…"
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.clear_button_enabled = true
	field.text_changed.connect(func(_text): _timer.start())
	field.gui_input.connect(_field_key)
	row.add_child(field)
	_count.theme_type_variation = &"Dim"
	row.add_child(_count)
	_chips.add_theme_constant_override("h_separation", 6)
	_chips.add_theme_constant_override("v_separation", 6)
	column.add_child(_chips)
	_results_scroll.custom_minimum_size = Vector2(0, 360)
	_results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_results_scroll)
	_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results.add_theme_constant_override("separation", 2)
	_results_scroll.add_child(_results)
	var hints := Label.new()
	hints.theme_type_variation = &"Dim"
	hints.add_theme_font_size_override("font_size", 12)
	hints.text = "Prefixes   W walking trigger   S story   M message   B battle   3, 3 cell on this map   ↑ ↓ move   Enter open"
	footer_left.add_child(hints)
	_timer.one_shot = true
	_timer.wait_time = 0.15
	_timer.timeout.connect(search)
	add_child(_timer)
	_build_chips()


func setup(owner_shell: Control) -> void:
	shell = owner_shell


func show_dialog() -> void:
	field.text = ""
	family = ""
	entries = []
	open()
	field.grab_focus()
	await search()


func _build_chips() -> void:
	for chip in _chips.get_children(): _chips.remove_child(chip); chip.queue_free()
	var all := _chip("All", "", int(totals.get("", 0)))
	all.set_pressed_no_signal(family == "")
	for group in GROUPS:
		_chip(group[1], group[0], int(totals.get(group[0], 0))).set_pressed_no_signal(family == group[0])


func _chip(text: String, key: String, count: int) -> Button:
	var chip := Button.new()
	chip.theme_type_variation = &"Chip"
	chip.toggle_mode = true
	chip.button_group = _chip_group
	chip.text = text + ("  %d" % count if count > 0 else "")
	chip.pressed.connect(func(): family = key; selected = 0; search())
	_chips.add_child(chip)
	return chip


## The cell a query like "3, 3" names, or (-1, -1).
static func cell_of(query: String) -> Vector2i:
	var parts := query.strip_edges().replace(",", " ").split(" ", false)
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		if cell.x >= 0 and cell.y >= 0 and cell.x < 90 and cell.y < 90: return cell
	return Vector2i(-1, -1)


## The query the adapter is asked: a letter and a number run together.
static func query_of(text: String) -> String:
	var plain := text.strip_edges()
	var matched := RegEx.create_from_string("^([wsmbWSMB])\\s*(\\d+)$").search(plain)
	return matched.get_string(1).to_lower() + matched.get_string(2) if matched != null else plain


func search() -> void:
	if shell == null or shell.summary.is_empty(): return
	_serial += 1
	var mine := _serial
	var query := query_of(field.text)
	var response: Dictionary = {"ok": true, "result": {"groups": [], "total": 0}}
	if not query.is_empty():
		response = await shell.request_backend({"op": "search", "query": query, "families": [] if family.is_empty() else [family], "limit": 64 if not family.is_empty() else SHOWN})
	if mine != _serial or not response.get("ok", false): return
	var result: Dictionary = response.result
	entries = []
	var cell := cell_of(field.text)
	var groups: Array = []
	for group in result.groups:
		var meta: Array = GROUPS[GROUPS.find_custom(func(g): return g[0] == group.family)]
		groups.append({"meta": meta, "total": int(group.total), "rows": group.rows})
	if cell.x >= 0 and (family.is_empty() or family == "cells"):
		groups.append({"meta": GROUPS[3], "total": 1, "rows": [{"id": cell.x * 90 + cell.y, "title": "Cell %d, %d" % [cell.x, cell.y], "detail": "on Map %d" % shell.maps.map_id, "cell": cell}]})
	if family.is_empty():
		totals = {"": 0}
		for group in groups:
			totals[group.meta[0]] = group.total
			totals[""] += group.total
		_build_chips()
	for child in _results.get_children(): _results.remove_child(child); child.queue_free()
	for group in groups:
		if group.total == 0: continue
		var heading := HBoxContainer.new()
		var caption := Label.new()
		caption.theme_type_variation = &"CaptionMuted"
		caption.uppercase = true
		caption.text = "%s  %d" % [group.meta[1], group.total]
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(caption)
		if group.total > group.rows.size() and family.is_empty():
			var more := Button.new()
			more.theme_type_variation = &"GhostButton"
			more.text = "Show all %d" % group.total
			var key: String = group.meta[0]
			more.pressed.connect(func(): family = key; selected = 0; _build_chips(); search())
			heading.add_child(more)
		_results.add_child(heading)
		for item in group.rows: _row(group.meta, item)
	_count.text = "%d result%s" % [entries.size(), "" if entries.size() == 1 else "s"] if not query.is_empty() else ""
	selected = clampi(selected, 0, maxi(0, entries.size() - 1))
	_mark()


func _row(meta: Array, item: Dictionary) -> void:
	var entry := {"kind": meta[3], "id": int(item.id), "title": str(item.title), "cell": item.get("cell", Vector2i(-1, -1))}
	entries.append(entry)
	var index := entries.size() - 1
	var button := Button.new()
	button.theme_type_variation = &"RowButton"
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(func(): selected = index; commit())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := Label.new()
	badge.theme_type_variation = &"BadgeDim"
	badge.text = meta[2]
	badge.add_theme_color_override("font_color", Tokens.FAMILY.get(meta[4], Tokens.DIM))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(badge)
	var number := Label.new()
	number.theme_type_variation = &"Mono"
	number.text = str(int(item.id)) if meta[3] != "cell" else ""
	number.custom_minimum_size.x = 44
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(number)
	var name := Label.new()
	name.text = str(item.title)
	name.clip_text = true
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name)
	if item.has("detail"):
		var detail := Label.new()
		detail.theme_type_variation = &"Dim"
		detail.text = str(item.detail)
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(detail)
	button.custom_minimum_size.y = 34
	button.add_child(line)
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	entry["button"] = button
	_results.add_child(button)


func _mark() -> void:
	for index in range(entries.size()): entries[index].button.set_pressed_no_signal(index == selected)
	if selected < entries.size(): _results_scroll.ensure_control_visible(entries[selected].button)


func _field_key(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed: return
	match event.keycode:
		KEY_DOWN: selected = mini(selected + 1, entries.size() - 1); _mark(); field.accept_event()
		KEY_UP: selected = maxi(selected - 1, 0); _mark(); field.accept_event()
		KEY_ENTER, KEY_KP_ENTER: commit(); field.accept_event()


func commit() -> void:
	if selected >= entries.size(): return
	var entry: Dictionary = entries[selected]
	close()
	chosen.emit({"kind": entry.kind, "id": entry.id, "cell": entry.cell})


func _unhandled_key_input(event: InputEvent) -> void:
	super(event)
