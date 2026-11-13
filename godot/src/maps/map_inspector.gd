extends VBoxContainer
## The right of the Maps workspace: the selected cell (its floor, walking
## triggers, regions and what refers to it), the map, its regions and the
## stages. Quick edits become drafts that wait for Apply, as everywhere else.
signal tab_changed(tab: String)
signal choose_tile_requested
signal object_changed(value: int)
signal secret_changed(state: String)
signal object_pick_requested(kind: String)
signal reveal_requested(cell: Vector2i)
signal callers_requested(trigger: int)
signal remove_requested(trigger_id: int)
signal region_chosen(slot: int)
signal region_changed(slot: int, changes: Dictionary)
signal region_removed(slot: int)
signal region_new
signal land_changed(changes: Dictionary)
signal open_program(family: String, id: int)
signal open_stages
signal create_confirmed
signal create_cancelled
const Card = preload("res://src/widgets/card.gd")
const Glyph = preload("res://src/widgets/glyph.gd")
const KeyValueRow = preload("res://src/widgets/key_value_row.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

const TABS := [["cell", "Cell"], ["map", "Map"], ["regions", "Regions"], ["stage", "Stage"]]

var shell: Control
var tab := "cell"
var _tab_buttons: Dictionary = {}
var _group := ButtonGroup.new()
var _panels: Dictionary = {}
var _note := Label.new()
var _revert := Button.new()
var _apply := Button.new()
var _loading := false
var _region_fields: Dictionary = {}


func _init() -> void:
	add_theme_constant_override("separation", 10)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 2)
	add_child(strip)
	for entry in TABS:
		var button := Button.new()
		button.theme_type_variation = &"RecordTab"
		button.toggle_mode = true
		button.button_group = _group
		button.focus_mode = Control.FOCUS_NONE
		button.text = entry[1]
		button.set_pressed_no_signal(entry[0] == tab)
		button.pressed.connect(func(): show_tab(entry[0]))
		strip.add_child(button)
		_tab_buttons[entry[0]] = button
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)
	for entry in TABS:
		var panel := VBoxContainer.new()
		panel.add_theme_constant_override("separation", 10)
		panel.visible = entry[0] == tab
		stack.add_child(panel)
		_panels[entry[0]] = panel
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	_note.theme_type_variation = &"Dim"
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(_note)
	_revert.text = "Revert"
	_revert.theme_type_variation = &"GhostButton"
	_revert.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_revert)
	_apply.text = "Apply"
	_apply.theme_type_variation = &"PrimaryButton"
	_apply.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_apply)
	add_child(foot)


func setup(owner_shell: Control) -> void:
	shell = owner_shell
	_apply.pressed.connect(func(): shell.apply_draft())
	_revert.pressed.connect(func(): if not shell.bridge.busy: shell._discard_continue())


func show_tab(name: String) -> void:
	tab = name
	for key in _panels: _panels[key].visible = key == name
	_tab_buttons[name].set_pressed_no_signal(true)
	tab_changed.emit(name)


## Whether edits wait for Apply, shown in the foot.
func show_pending(count: int) -> void:
	_note.text = "Edits wait for Apply" if count > 0 else "Painting commits each stroke as one undo step. Forms wait for Apply."
	_revert.disabled = count == 0
	_apply.disabled = count == 0


func _clear(panel: Control) -> void:
	for child in panel.get_children(): panel.remove_child(child); child.queue_free()


func _title(panel: Control, text: String, badges: Array, sub: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.theme_type_variation = &"Heading"
	label.text = text
	row.add_child(label)
	for badge in badges:
		var chip := Label.new()
		chip.theme_type_variation = &"Badge"
		chip.text = str(badge)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)
	panel.add_child(row)
	if not sub.is_empty():
		var line := Label.new()
		line.theme_type_variation = &"Dim"
		line.text = sub
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(line)


func _kv(parent: Control, key: String, value: String, mono := false) -> void:
	var row := KeyValueRow.new()
	row.key = key
	row.value = value
	row.mono = mono
	row.key_width = 80
	parent.add_child(row)


func _words(parent: Control, text: String, dim := true) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"Muted" if dim else &""
	label.add_theme_font_size_override("font_size", 12)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	if parent is Card: parent.add_row(label)
	else: parent.add_child(label)
	return label


func _link(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"GhostButton"
	button.text = text
	button.pressed.connect(callback)
	return button


## The cell tab. `info` holds {map, tile, tile_info, thumb, triggers, programs, regions, starts}.
func show_cell(cell: Vector2i, info: Dictionary) -> void:
	var panel: VBoxContainer = _panels.cell
	_clear(panel)
	if cell.x < 0:
		_title(panel, "Cell", [], "Select a cell to inspect it")
		return
	var triggers: Array = info.get("triggers", [])
	var names := triggers.map(func(trigger): return "W%d" % int(trigger.slot))
	var count := "no triggers" if triggers.is_empty() else ("1 trigger" if triggers.size() == 1 else "%d triggers" % triggers.size())
	_title(panel, "Cell %d, %d" % [cell.x, cell.y], names, "Map %d · floor %d · %s · %s" % [int(info.map), int(info.tile), "no object" if int(info.get("object", 0)) == 0 else "object %d" % int(info.get("object", 0)), count])
	var floor_card := Card.new()
	floor_card.title = "Floor"
	panel.add_child(floor_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var thumb := TextureRect.new()
	thumb.texture = info.get("thumb")
	thumb.custom_minimum_size = Vector2(48, 48)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(thumb)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tile := Label.new()
	tile.theme_type_variation = &"Strong"
	tile.text = "Tile %d" % int(info.tile)
	words.add_child(tile)
	var about := Label.new()
	about.theme_type_variation = &"MonoDim"
	about.text = str(info.get("tile_info", ""))
	words.add_child(about)
	row.add_child(words)
	var choose := Button.new()
	choose.text = "Choose…"
	choose.pressed.connect(func(): choose_tile_requested.emit())
	row.add_child(choose)
	floor_card.add_row(row)
	var secret := Card.new()
	secret.title = "Secret"
	panel.add_child(secret)
	var number := absi(int(info.tile))
	var states := ["normal", "hidden", "revealed"]
	var choice := OptionButton.new()
	for entry in ["Normal", "Hidden secret", "Revealed secret"]: choice.add_item(entry)
	choice.select(1 if number > 2999 else (2 if number > 1999 else 0))
	choice.item_selected.connect(func(index): secret_changed.emit(states[index]))
	secret.add_row(choice)
	_words(secret, "A hidden secret adds 3000 to the cell's number, which is what the game's search looks for: the squad's step searches the cells around it, finds a hidden cell by chance and takes 1000 off. A revealed secret is a cell a search has already found (2000 added)." )
	_words(secret, "The game draws a floor number above 300 as nothing, found or not, and walks it as the map's own tile. A trigger on a hidden cell fires whether or not the cell has been found: that is a secret entrance.")
	if info.get("proposal", false): _proposal(panel, cell, int(info.map))
	for trigger in triggers: _trigger_card(panel, trigger, info.programs.get(int(trigger.id), {}), cell)
	var regions: Array = info.get("regions", [])
	var here := Card.new()
	here.title = "Regions here"
	panel.add_child(here)
	if regions.is_empty(): _words(here, "No region covers this cell")
	for region in regions:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var dot := Glyph.new()
		dot.glyph = "dot"
		dot.extent = 10.0
		dot.color = Tokens.REGION
		line.add_child(dot)
		var label := Label.new()
		label.theme_type_variation = &"Mono"
		label.text = preload("res://src/map_canvas.gd")._region_text(region)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		line.add_child(_link("View", func(): region_chosen.emit(int(region.slot))))
		here.add_row(line)
	var object := Card.new()
	object.title = "Object"
	panel.add_child(object)
	var shown := int(info.get("object", 0))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var art := TextureRect.new()
	art.texture = info.get("object_thumb")
	art.custom_minimum_size = Vector2(48, 48)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	line.add_child(art)
	var said := VBoxContainer.new()
	said.add_theme_constant_override("separation", 0)
	said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	said.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var what := Label.new()
	what.theme_type_variation = &"Strong"
	what.text = "No object" if shown == 0 else str(info.get("object_name", "Object %d" % shown))
	said.add_child(what)
	var from := Label.new()
	from.theme_type_variation = &"MonoDim"
	from.text = "" if shown == 0 else ("picture %d" % (23000 + shown) if shown > 0 else "icon %d" % -shown)
	said.add_child(from)
	line.add_child(said)
	object.add_row(line)
	var value := SpinBox.new()
	value.min_value = -32768
	value.max_value = 32767
	value.rounded = true
	value.custom_minimum_size.x = 120
	value.set_value_no_signal(shown)
	value.value_changed.connect(func(number): object_changed.emit(int(number)))
	object.add_row(value)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	for entry in [["Building…", "picture"], ["Icon…", "icon"]]:
		buttons.add_child(_link(entry[0], func(): object_pick_requested.emit(entry[1])))
	if shown != 0: buttons.add_child(_link("Remove object", func(): object_changed.emit(0)))
	object.add_row(buttons)
	_words(object, "Drawn over the floor: a building is the picture numbered 23000 plus its value, set on the cell's lower right. It does not block the party or its sight.")
	_used_by(panel, cell, info)


## What New at selected cell would do, before it does it.
func _proposal(panel: Control, cell: Vector2i, map_id: int) -> void:
	var card := Card.new()
	card.title = "New walking trigger"
	card.dot_color = Tokens.ACCENT
	panel.add_child(card)
	_kv(card.body, "Slot", "the first unplaced empty program")
	_kv(card.body, "Gate", "0 → %d, this cell's location key" % (map_id * 10000 + cell.y * 100 + cell.x), true)
	_kv(card.body, "Steps", "0 of 8 · empty")
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): create_cancelled.emit())
	buttons.add_child(cancel)
	var create := Button.new()
	create.text = "Create · one undo step"
	create.theme_type_variation = &"PrimaryButton"
	create.pressed.connect(func(): create_confirmed.emit())
	buttons.add_child(create)
	card.add_row(buttons)


func _trigger_card(panel: Control, trigger: Dictionary, program: Dictionary, cell: Vector2i) -> void:
	var id := int(trigger.id)
	var card := Card.new()
	card.title = "Walking trigger W%d" % int(trigger.slot)
	card.dot_color = Tokens.TRIGGER if trigger.active else Tokens.DIM
	panel.add_child(card)
	if program.is_empty():
		_words(card, "Steps are not loaded yet.")
		return
	var chance_key := JSON.stringify({"kind": "walking_chance", "id": id})
	var saved := int(program.get("chance", trigger.chance))
	var shown := int(shell.drafts.get(chance_key, {}).get("chance", saved))
	var editable: bool = program.get("conditions", {}).get("chance_authorable", false)
	var live := CheckButton.new()
	live.button_pressed = shown > 0
	live.disabled = not editable
	card.right.add_child(live)
	var chance := SpinBox.new()
	chance.max_value = 100
	chance.suffix = "%"
	chance.value = shown
	chance.editable = editable
	chance.custom_minimum_size.x = 96
	var chance_row := HBoxContainer.new()
	chance_row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.theme_type_variation = &"Dim"
	label.text = "Chance"
	label.custom_minimum_size.x = 80
	chance_row.add_child(label)
	chance_row.add_child(chance)
	card.add_row(chance_row)
	var change := func(value: int):
		if _loading: return
		if value == saved: shell.drafts.erase(chance_key)
		else: shell.drafts[chance_key] = {"kind": "walking_chance", "id": id, "chance": value}
		shell._invalidate_receipt()
		shell._update_buttons()
	chance.value_changed.connect(func(value):
		live.set_pressed_no_signal(int(value) > 0)
		change.call(int(value)))
	live.toggled.connect(func(on):
		chance.value = (saved if saved > 0 else 100) if on else 0)
	var destination: Dictionary = program.get("destination", {})
	if not destination.is_empty(): _kv(card.body, "After", "returns to Map %d (%d, %d)" % [int(destination.map), int(destination.x), int(destination.y)])
	var flag: Variant = trigger.get("cell_flag")
	_kv(card.body, "Activation", "location gate %s · stamp %d" % [("open" if flag != null and int(flag) > 0 else "shut"), int(destination.get("stamp", 0))])
	var steps: Array = program.get("steps", [])
	var used := steps.filter(func(step): return int(step.opcode) != 0).size()
	var head := HBoxContainer.new()
	var steps_title := Label.new()
	steps_title.theme_type_variation = &"CaptionMuted"
	steps_title.text = "STEPS  %d of %d used" % [used, steps.size()]
	steps_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(steps_title)
	head.add_child(_link("Open ↗", func(): open_program.emit("walking", id)))
	card.add_row(head)
	for step in steps: card.add_row(_step_row(id, step))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	var callers := Button.new()
	callers.text = "Callers"
	callers.pressed.connect(func(): callers_requested.emit(id))
	buttons.add_child(callers)
	var reveal := Button.new()
	reveal.text = "Reveal"
	reveal.pressed.connect(func(): reveal_requested.emit(cell))
	buttons.add_child(reveal)
	var remove := Button.new()
	remove.text = "Remove"
	remove.theme_type_variation = &"GhostButton"
	remove.pressed.connect(func(): remove_requested.emit(id))
	buttons.add_child(remove)
	card.add_row(buttons)


## One of the eight steps: its number, operation and operand. A step the editor
## does not author is locked; an operand that can change is a draft.
func _step_row(id: int, step: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var number := Label.new()
	number.theme_type_variation = &"MonoDim"
	number.text = str(int(step.slot) + 1)
	number.custom_minimum_size.x = 14
	row.add_child(number)
	var code := Label.new()
	code.theme_type_variation = &"MonoDim"
	code.text = str(int(step.opcode))
	code.custom_minimum_size.x = 30
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(code)
	var name := Label.new()
	name.text = str(step.name) if step.authorable or int(step.opcode) == 0 else "Preserved operation"
	name.theme_type_variation = &"" if step.authorable else &"Dim"
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	row.add_child(name)
	var opcode := int(step.opcode)
	if step.authorable and opcode not in [0, 24, 100]:
		var key := "script_step:walking:%d:0:%d" % [id, int(step.slot)]
		var operand := SpinBox.new()
		operand.min_value = -32768
		operand.max_value = 32767
		operand.value = int(shell.drafts.get(key, {}).get("operand", step.operand))
		operand.custom_minimum_size.x = 84
		operand.value_changed.connect(func(value):
			if _loading: return
			if int(value) == int(step.operand): shell.drafts.erase(key)
			else: shell.drafts[key] = {"kind": "script_step", "family": "walking", "id": id, "branch": 0, "slot": int(step.slot), "opcode": opcode, "operand": int(value)}
			shell._invalidate_receipt()
			shell._update_buttons())
		row.add_child(operand)
	else:
		var value := Label.new()
		value.theme_type_variation = &"MonoDim"
		value.text = str(int(step.operand)) if opcode != 0 else ""
		row.add_child(value)
		if not step.authorable and opcode != 0:
			var lock := Glyph.new()
			lock.glyph = "lock"
			lock.extent = 12.0
			lock.color = Tokens.DIM
			row.add_child(lock)
	return row


func _used_by(panel: Control, cell: Vector2i, info: Dictionary) -> void:
	var card := Card.new()
	card.title = "Used by"
	var any := false
	for start in info.get("starts", []):
		any = true
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var dot := Glyph.new()
		dot.glyph = "dot"
		dot.extent = 10.0
		dot.color = Tokens.START
		line.add_child(dot)
		var text := Label.new()
		text.text = "Stage %d starts here" % int(start.id)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		line.add_child(_link("Stages ↗", func(): show_tab("stage")))
		card.add_row(line)
	for trigger in info.get("triggers", []):
		var program: Dictionary = info.programs.get(int(trigger.id), {})
		for step in program.get("steps", []):
			if int(step.opcode) != 39: continue
			any = true
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 8)
			var dot := Glyph.new()
			dot.glyph = "dot"
			dot.extent = 10.0
			dot.color = Tokens.FAMILY.flow
			line.add_child(dot)
			var text := Label.new()
			text.text = "W%d step %d replaces the steps with Story %d" % [int(trigger.slot), int(step.slot) + 1, int(step.operand)]
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(text)
			line.add_child(_link("Story ↗", func(): open_program.emit("story", int(step.operand))))
			card.add_row(line)
	if not any: _words(card, "Nothing starts here or replaces a program from this cell")
	panel.add_child(card)


## The map tab: what the map holds.
func show_map(info: Dictionary) -> void:
	var panel: VBoxContainer = _panels.map
	_clear(panel)
	_title(panel, "Map %d" % int(info.map), [], "%d × %d" % [90, 90])
	var land := Card.new()
	land.title = "Land"
	panel.add_child(land)
	if info.terrain >= 0:
		var sets := OptionButton.new()
		for tile_set in range(1, 10) + range(15, 20):
			sets.add_item("Tile set %d" % tile_set, tile_set)
		var chosen := sets.get_item_index(int(info.terrain))
		if chosen < 0:
			sets.add_item("Tile set %d (not authorable)" % int(info.terrain), int(info.terrain))
			chosen = sets.item_count - 1
		sets.select(chosen)
		sets.item_selected.connect(func(index): land_changed.emit({"terrain": sets.get_item_id(index)}))
		var sets_row := HBoxContainer.new()
		sets_row.add_theme_constant_override("separation", 10)
		sets_row.add_child(_tag("Tile set"))
		sets_row.add_child(sets)
		land.add_row(sets_row)
		var sight := CheckBox.new()
		sight.text = "Shows only the squares the party has seen"
		sight.button_pressed = bool(info.get("limits_sight", false))
		sight.toggled.connect(func(on): land_changed.emit({"limits_sight": on}))
		land.add_row(sight)
		var light := SpinBox.new()
		light.min_value = 0
		light.max_value = 255
		light.value = int(info.get("light", 0))
		light.custom_minimum_size.x = 96
		light.value_changed.connect(func(value): land_changed.emit({"light": int(value)}))
		var light_row := HBoxContainer.new()
		light_row.add_theme_constant_override("separation", 10)
		light_row.add_child(_tag("Light level"))
		light_row.add_child(light)
		land.add_row(light_row)
		_words(land, "Only story steps read the light level; nothing is drawn from it.")
	else:
		_kv(land.body, "Terrain", "not loaded")
	if info.get("picture", 0) != 0: _kv(land.body, "Pictures", "PICT %d" % int(info.picture), true)
	var contents := Card.new()
	contents.title = "Contents"
	panel.add_child(contents)
	_kv(contents.body, "Floor", "%d tiles in use" % int(info.tiles))
	_kv(contents.body, "Walking", "%d programs placed · %d slots free" % [int(info.placed), 100 - int(info.placed)])
	_kv(contents.body, "Regions", "%d of 20%s" % [int(info.regions), (" · %d past the edge" % int(info.past_edge)) if int(info.past_edge) > 0 else ""])
	_kv(contents.body, "Objects", "%d placed" % int(info.get("objects", 0)))
	_kv(contents.body, "Stage starts", info.starts_text)


## The regions tab: each rectangle of the map, and the fields of the chosen one.
## Every field is a draft that waits for Apply.
func show_regions(regions: Array, chosen: int) -> void:
	var panel: VBoxContainer = _panels.regions
	_clear(panel)
	_region_fields.clear()
	_title(panel, "Regions", ["provisional"], "%d of 20 slots in use" % regions.size())
	var list := Card.new()
	list.title = "On this map"
	var add := _link("New region", func(): region_new.emit())
	list.right.add_child(add)
	panel.add_child(list)
	if regions.is_empty(): _words(list, "This map has no regions")
	for region in regions:
		var button := Button.new()
		button.theme_type_variation = &"RowButton"
		button.toggle_mode = true
		button.set_pressed_no_signal(int(region.slot) == chosen)
		button.custom_minimum_size.y = 28
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "  " + preload("res://src/map_canvas.gd")._region_text(region)
		button.pressed.connect(func(): region_chosen.emit(int(region.slot)))
		list.add_row(button)
	for region in regions:
		if int(region.slot) != chosen: continue
		_region_card(panel, region)


func _region_card(panel: Control, region: Dictionary) -> void:
	var slot := int(region.slot)
	var card := Card.new()
	card.title = "Region R%d" % slot
	card.dot_color = Tokens.REGION
	panel.add_child(card)
	var covers := HBoxContainer.new()
	covers.add_theme_constant_override("separation", 6)
	covers.add_child(_tag("First x"))
	covers.add_child(_field(slot, "first_x", int(region.first_x), 0, 89))
	covers.add_child(_tag("y"))
	covers.add_child(_field(slot, "first_y", int(region.first_y), 0, 89))
	card.add_row(covers)
	var last := HBoxContainer.new()
	last.add_theme_constant_override("separation", 6)
	last.add_child(_tag("Last x"))
	last.add_child(_field(slot, "last_x", int(region.last_x), 0, 89))
	last.add_child(_tag("y"))
	last.add_child(_field(slot, "last_y", int(region.last_y), 0, 89))
	card.add_row(last)
	var battles := HBoxContainer.new()
	battles.add_theme_constant_override("separation", 6)
	battles.add_child(_tag("Battles"))
	battles.add_child(_field(slot, "battle_min", int(region.battle_min), 0, 32767))
	battles.add_child(_tag("–"))
	battles.add_child(_field(slot, "battle_max", int(region.battle_max), 0, 32767))
	card.add_row(battles)
	var chance := HBoxContainer.new()
	chance.add_theme_constant_override("separation", 6)
	chance.add_child(_tag("Chance"))
	chance.add_child(_field(slot, "encounter_chance", int(region.encounter_chance), 0, 32767))
	chance.add_child(_tag("in 10000"))
	card.add_row(chance)
	var events := Label.new()
	events.theme_type_variation = &"CaptionMuted"
	events.text = "EVENTS"
	card.add_row(events)
	for index in range(3):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		line.add_child(_tag("%d  Story" % (index + 1)))
		line.add_child(_field(slot, "script%d" % index, int(region.scripts[index]), 0, 32767))
		line.add_child(_tag("chance"))
		line.add_child(_field(slot, "chance%d" % index, int(region.script_chances[index]), -100, 100))
		line.add_child(_tag("%"))
		line.add_child(_link("↗", func(): open_program.emit("story", int(region.scripts[index]))))
		card.add_row(line)
	var avoid := HBoxContainer.new()
	avoid.add_theme_constant_override("separation", 6)
	avoid.add_child(_tag("Avoid"))
	avoid.add_child(_field(slot, "avoid_chance", int(region.get("avoid_chance", 0)), -128, 127))
	avoid.add_child(_tag("% sound"))
	avoid.add_child(_field(slot, "avoid_sound", int(region.get("avoid_sound", 0)), -32768, 32767))
	card.add_row(avoid)
	var dialogue := HBoxContainer.new()
	dialogue.add_theme_constant_override("separation", 6)
	dialogue.add_child(_tag("Dialogue"))
	dialogue.add_child(_field(slot, "avoid_dialogue", int(region.get("avoid_dialogue", 0)), -32768, 32767))
	card.add_row(dialogue)
	var exclusive := CheckBox.new()
	exclusive.text = "Exclusive: lower regions are not scanned"
	exclusive.set_pressed_no_signal(bool(region.get("exclusive", false)))
	exclusive.toggled.connect(func(on): region_changed.emit(slot, {"exclusive": on}))
	_region_fields["exclusive"] = exclusive
	card.add_row(exclusive)
	_words(card, "A positive event chance is cleared once the event runs; a negative one stays.")
	var remove := _link("Remove region", func(): region_removed.emit(slot))
	card.add_row(remove)


func _tag(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"Dim"
	label.text = text
	return label


func _field(slot: int, key: String, value: int, low: int, high: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.custom_minimum_size.x = 76
	spin.set_value_no_signal(value)
	spin.value_changed.connect(func(number): region_changed.emit(slot, {key: int(number)}))
	_region_fields[key] = spin
	return spin


## Puts the values of a region that was just dragged in the fields beside the map.
func show_region_values(region: Dictionary) -> void:
	for key in ["first_x", "first_y", "last_x", "last_y"]:
		if _region_fields.has(key): _region_fields[key].set_value_no_signal(int(region[key]))


## The stage tab: the stages and the chosen stage's start.
func show_stages(stages: Array, chosen: int, map_id: int) -> void:
	var panel: VBoxContainer = _panels.stage
	_clear(panel)
	var active := stages.filter(func(row): return row.active)
	_title(panel, "Stages", [], "%d slots · %d in use" % [stages.size(), active.size()])
	var list := Card.new()
	list.title = "Stages"
	panel.add_child(list)
	for row in active:
		var button := Button.new()
		button.theme_type_variation = &"RowButton"
		button.toggle_mode = true
		button.set_pressed_no_signal(int(row.id) == chosen)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 28
		button.text = "  %d   %s · Map %d" % [int(row.id), str(row.name), int(row.map)]
		button.pressed.connect(func(): shell.stages.stage_id = int(row.id); shell.maps.stage_chosen(int(row.id)))
		list.add_row(button)
	if active.size() < stages.size(): _words(list, "%d – %d · empty" % [active.size(), stages.size() - 1])
	if chosen >= stages.size() or not stages[chosen].active: return
	var row: Dictionary = stages[chosen]
	var start: Dictionary = shell.drafts.get("stage_start:%d" % chosen, row)
	var card := Card.new()
	card.title = "Stage %d" % chosen
	card.dot_color = Tokens.START
	panel.add_child(card)
	var name := LineEdit.new()
	name.text = str(shell.drafts.get("stage_name:%d" % chosen, {}).get("name", row.name))
	name.text_changed.connect(func(text): shell.stages.draft_name(chosen, text))
	var name_row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.theme_type_variation = &"Dim"
	name_label.text = "Name"
	name_label.custom_minimum_size.x = 80
	name_row.add_child(name_label)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name)
	card.add_row(name_row)
	var start_row := HBoxContainer.new()
	start_row.add_theme_constant_override("separation", 6)
	var start_label := Label.new()
	start_label.theme_type_variation = &"Dim"
	start_label.text = "Start"
	start_label.custom_minimum_size.x = 74
	start_row.add_child(start_label)
	var fields: Dictionary = {}
	for entry in [["map", "Map", 19], ["x", "x", 89], ["y", "y", 89]]:
		var spin := SpinBox.new()
		spin.max_value = entry[2]
		spin.prefix = "" if entry[0] == "map" else ""
		spin.value = int(start.get(entry[0], 0))
		spin.custom_minimum_size.x = 64
		start_row.add_child(spin)
		fields[entry[0]] = spin
	for key in fields:
		fields[key].value_changed.connect(func(_value): shell.stages.draft_start(chosen, int(fields.map.value), int(fields.x.value), int(fields.y.value)))
	card.add_row(start_row)
	var here := active.filter(func(item): return int(item.map) == map_id).map(func(item): return "Stage %d" % int(item.id))
	_kv(card.body, "On this map", ", ".join(here) if not here.is_empty() else "none")
	var story := HBoxContainer.new()
	story.add_theme_constant_override("separation", 6)
	var story_label := Label.new()
	story_label.theme_type_variation = &"Dim"
	story_label.text = "Start story"
	story_label.custom_minimum_size.x = 80
	story.add_child(story_label)
	var story_text := Label.new()
	story_text.theme_type_variation = &"Mono"
	var story_id := int(shell.drafts.get("stage_script:%d" % chosen, {}).get("story", row.start_script))
	story_text.text = "%d · %s" % [story_id, "none" if story_id == 0 else "story"]
	story_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story.add_child(story_text)
	story.add_child(_link("Open ↗", func(): open_program.emit("story", story_id)))
	card.add_row(story)
	_words(card, "The start story is edited apart from the start cell. Stage transitions name stages by signed one-based number.")
