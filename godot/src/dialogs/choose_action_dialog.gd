extends "res://src/widgets/modal_overlay.gd"
## Choose action: the operations a step has a form for, in their families,
## with the evidence for each and what choosing one would change.
signal action_chosen(opcode: int)
const Capability = preload("res://src/scripts/capability.gd")
const Card = preload("res://src/widgets/card.gd")
const KbdButton = preload("res://src/widgets/kbd_button.gd")
const KeyValueRow = preload("res://src/widgets/key_value_row.gd")

var _filter := LineEdit.new()
var _list := VBoxContainer.new()
var _detail := VBoxContainer.new()
var _note := Label.new()
var _use: KbdButton
var _group := ButtonGroup.new()
var _rows: Dictionary = {}
var _order: Array = []
var _picked := 0
var _current := 0
var _recent: Array = []
var _only_recent := false
var _forms_chip: Button
var _recent_chip: Button
var _context: Dictionary = {}


func _init() -> void:
	super()
	title = "Choose action"
	panel_size = Vector2(1000, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	body.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_filter.placeholder_text = "Filter by name or opcode…"
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter.clear_button_enabled = true
	_filter.text_changed.connect(func(_text): _fill())
	_filter.gui_input.connect(_filter_key)
	head.add_child(_filter)
	var chips := ButtonGroup.new()
	_forms_chip = Button.new()
	_forms_chip.theme_type_variation = &"Chip"
	_forms_chip.toggle_mode = true
	_forms_chip.button_group = chips
	_forms_chip.text = "Step forms  %d" % Capability.forms().size()
	_forms_chip.button_pressed = true
	_forms_chip.pressed.connect(func(): _only_recent = false; _fill())
	head.add_child(_forms_chip)
	_recent_chip = Button.new()
	_recent_chip.theme_type_variation = &"Chip"
	_recent_chip.toggle_mode = true
	_recent_chip.button_group = chips
	_recent_chip.text = "Recent"
	_recent_chip.pressed.connect(func(): _only_recent = true; _fill())
	head.add_child(_recent_chip)
	column.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 400)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var side := PanelContainer.new()
	side.theme_type_variation = &"Detail"
	side.custom_minimum_size.x = 330
	row.add_child(side)
	_detail.add_theme_constant_override("separation", 10)
	side.add_child(_detail)
	_note.theme_type_variation = &"Muted"
	_note.add_theme_font_size_override("font_size", 12)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_note)
	var keys := Label.new()
	keys.theme_type_variation = &"Dim"
	keys.text = "↑ ↓ move · Enter choose · Esc cancel"
	footer_left.add_child(keys)
	add_button("Cancel").pressed.connect(close)
	_use = KbdButton.new()
	_use.theme_type_variation = &"PrimaryButton"
	_use.hint = "Enter"
	_use.pressed.connect(_commit)
	add_footer_button(_use)


## Opens for a step. `context` holds {where, record, family, branch, slot, operand, operand_for}; `recent` lists the operations chosen lately.
func show_for(current: int, context: Dictionary, recent: Array) -> void:
	_current = current
	_picked = current
	_context = context
	_recent = recent
	_only_recent = false
	_forms_chip.button_pressed = true
	_filter.text = ""
	subtitle = "%s · %s" % [str(context.record), str(context.where)]
	var others := Capability.unlisted_count()
	_note.text = "Every operation of the game is offered. A number that names no code does nothing in the game." if others == 0 else "%d other operations are not offered. Steps that use them keep them as recorded." % others
	_fill()
	open()
	_filter.grab_focus()


func _fill() -> void:
	for child in _list.get_children(): _list.remove_child(child); child.queue_free()
	_rows.clear()
	_order.clear()
	var needle := _filter.text.strip_edges().to_lower()
	for family in Capability.KINDS:
		var members: Array = Capability.forms().filter(func(entry): return Capability.kind_of(int(entry[0])) == family[0] and (needle.is_empty() or needle in str(entry[1]).to_lower() or needle == str(entry[0]) or needle in str(entry[3]).to_lower()) and (not _only_recent or _recent.has(entry[0])))
		if members.is_empty(): continue
		var heading := HBoxContainer.new()
		heading.add_theme_constant_override("separation", 8)
		var dot := preload("res://src/widgets/glyph.gd").new()
		dot.glyph = "dot"
		dot.extent = 10.0
		dot.color = Capability.kind_colour(family[0])
		heading.add_child(dot)
		var name := Label.new()
		name.theme_type_variation = &"CaptionMuted"
		name.text = str(family[1]).to_upper()
		heading.add_child(name)
		_list.add_child(heading)
		for entry in members:
			_list.add_child(_row(entry))
			_order.append(int(entry[0]))
	if not _order.has(_picked) and not _order.is_empty(): _picked = _order[0]
	_show_picked()


func _row(entry: Array) -> Button:
	var opcode := int(entry[0])
	var button := Button.new()
	button.theme_type_variation = &"RowButton"
	button.toggle_mode = true
	button.button_group = _group
	button.custom_minimum_size = Vector2(0, 46)
	button.set_pressed_no_signal(opcode == _picked)
	button.pressed.connect(func(): _picked = opcode; _show_picked())
	button.gui_input.connect(func(event): if event is InputEventMouseButton and event.double_click: _commit())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	button.add_child(margin)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(line)
	var code := Label.new()
	code.theme_type_variation = &"MonoDim"
	code.text = str(opcode)
	code.custom_minimum_size.x = 30
	code.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(code)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(words)
	var name := Label.new()
	name.theme_type_variation = &"Strong"
	name.text = str(entry[1])
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(name)
	var about := Label.new()
	about.theme_type_variation = &"Dim"
	about.text = str(entry[3])
	about.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(about)
	if opcode == _current:
		var now := Label.new()
		now.theme_type_variation = &"BadgeDim"
		now.text = "current"
		now.mouse_filter = Control.MOUSE_FILTER_IGNORE
		now.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(now)
	var row := Capability.row(opcode)
	if not row.is_empty():
		if row.editor == "warn":
			var warn := Label.new()
			warn.theme_type_variation = &"BadgeWarn"
			warn.text = "warn"
			warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			warn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(warn)
		var status := Label.new()
		status.theme_type_variation = &"BadgeGood" if row.status == "native-verified" else &"Badge"
		status.text = str(row.status)
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(status)
	_rows[opcode] = button
	return button


func _show_picked() -> void:
	for opcode in _rows: _rows[opcode].set_pressed_no_signal(opcode == _picked)
	for child in _detail.get_children(): _detail.remove_child(child); child.queue_free()
	var entry := Capability.form(_picked)
	if entry.is_empty():
		_use.disabled = true
		return
	_use.disabled = false
	_use.text = "Use %s" % str(entry[1])
	var top := HBoxContainer.new()
	var code := Label.new()
	code.theme_type_variation = &"Dim"
	code.text = "Opcode %d" % _picked
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(code)
	var family := Label.new()
	family.theme_type_variation = &"Dim"
	var kind := Capability.kind_of(int(entry[0]))
	family.text = str(Capability.KINDS[Capability.KINDS.map(func(item): return item[0]).find(kind)][1])
	family.add_theme_color_override("font_color", Capability.kind_colour(kind))
	top.add_child(family)
	_detail.add_child(top)
	var name := Label.new()
	name.theme_type_variation = &"Heading"
	name.add_theme_font_size_override("font_size", 20)
	name.text = str(entry[1])
	_detail.add_child(name)
	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 6)
	var row := Capability.row(_picked)
	if not row.is_empty():
		for badge in [[row.status, &"BadgeGood" if row.status == "native-verified" else &"Badge"], [row.editor, &"BadgeWarn" if row.editor == "warn" else &"BadgeGood"], ["step form", &"BadgeAccent"]]:
			var label := Label.new()
			label.theme_type_variation = badge[1]
			label.text = str(badge[0])
			badges.add_child(label)
	_detail.add_child(badges)
	var operand := Card.new()
	operand.title = "Operand"
	_detail.add_child(operand)
	_kv(operand.body, "Takes", Capability.takes(_picked))
	if not row.is_empty() and row.get("behavior") != null: _kv(operand.body, "Does", str(row.behavior))
	var change := Card.new()
	change.title = "This change"
	_detail.add_child(change)
	var after_operand: int = _context.operand_for.call(_picked) if _context.has("operand_for") else int(_context.operand)
	_kv(change.body, "Before", "%d  %s  %d" % [_current, Capability.name_of(_current), int(_context.operand)], true)
	_kv(change.body, "After", "%d  %s  %d" % [_picked, str(entry[1]), after_operand], true)
	var offsets := Capability.offsets(str(_context.family), int(_context.branch), int(_context.slot))
	var op_span := "%d" % int(offsets[0]) if int(offsets[1]) == 1 else "%d–%d" % [int(offsets[0]), int(offsets[0]) + 1]
	_kv(change.body, "Bytes", "%s, %d–%d of %s's row" % [op_span, int(offsets[2]), int(offsets[2]) + 1, str(_context.record)], true)


func _kv(parent: Control, key: String, value: String, mono := false) -> void:
	var row := KeyValueRow.new()
	row.key = key
	row.value = value
	row.mono = mono
	row.key_width = 64
	parent.add_child(row)


func _filter_key(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed: return
	var at := _order.find(_picked)
	if event.keycode == KEY_DOWN and at < _order.size() - 1: _picked = _order[at + 1]
	elif event.keycode == KEY_UP and at > 0: _picked = _order[at - 1]
	else: return
	_show_picked()
	_filter.accept_event()


func _commit() -> void:
	if not Capability.has_form(_picked): return
	close()
	action_chosen.emit(_picked)


func _unhandled_key_input(event: InputEvent) -> void:
	super(event)
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_commit()
		get_viewport().set_input_as_handled()
