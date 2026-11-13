extends VBoxContainer
## The tools of the map and the options of the one in hand. The controls the
## tools share (the brush tile, the trigger slot and chance, whether a return
## follows a placement) live here and are found by name through the shell.
signal tool_changed(tool: String)
signal new_at_cell_requested
signal open_steps_requested
signal choose_tile_requested
signal building_requested
signal icon_requested
const Glyph = preload("res://src/widgets/glyph.gd")
const ToolButton = preload("res://src/maps/tool_button.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

# [tool, name, key]. null is a rule between groups.
const TOOLS := [["select", "Select", "V"], ["sample", "Sample", "I"], null, ["paint", "Paint", "B"], ["line", "Line", "L"], ["rectangle", "Rectangle", "R"], ["fill", "Fill", "G"],
	null, ["trigger", "Trigger", "T"], ["region", "Region", "E"], ["start", "Start", "S"], null, ["erase", "Erase", "X"]]
const LAYERS := [["Floor", "paint"], ["Walking triggers", "trigger"], ["Regions", "region"], ["Stage starts", "start"]]
const NAMES := {"select": "Select", "sample": "Sample", "paint": "Paint", "line": "Line", "rectangle": "Rectangle", "fill": "Fill", "trigger": "Walking trigger",
	"region": "Region", "start": "Stage start", "erase": "Erase"}

var tool := "select"
## Whether the paint tools paint the object layer, which is chosen by a building picture or an icon as well as a tile.
var object_mode := false:
	set(value):
		object_mode = value
		_show_options()
var tile_id := SpinBox.new()
var slot := SpinBox.new()
var chance := SpinBox.new()
var follow := CheckButton.new()
var stage := OptionButton.new()
var layer := OptionButton.new()
var cell_text := Label.new()
var start_text := Label.new()
var new_button := Button.new()
var steps_button := Button.new()
var _buttons: Dictionary = {}
var _group := ButtonGroup.new()
var _bar := HBoxContainer.new()
var _hint := Label.new()
var _name := Label.new()
var _dot := Glyph.new()
var _boxes: Dictionary = {}
var _loading := false


func _init() -> void:
	add_theme_constant_override("separation", 6)
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 2)
	tools.add_theme_constant_override("v_separation", 4)
	add_child(tools)
	for entry in TOOLS:
		if entry == null:
			var rule := VSeparator.new()
			rule.custom_minimum_size = Vector2(9, 22)
			tools.add_child(rule)
			continue
		var button := ToolButton.new()
		button.text = entry[1]
		button.key = entry[2]
		button.button_group = _group
		button.set_pressed_no_signal(entry[0] == tool)
		button.pressed.connect(func(): select_tool(entry[0]))
		tools.add_child(button)
		_buttons[entry[0]] = button
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(gap)
	var layer_label := Label.new()
	layer_label.text = "Layer"
	layer_label.theme_type_variation = &"Dim"
	layer_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tools.add_child(layer_label)
	for entry in LAYERS: layer.add_item(entry[0])
	layer.item_selected.connect(func(index): if not _loading: select_tool(LAYERS[index][1]))
	tools.add_child(layer)
	var strip := PanelContainer.new()
	strip.theme_type_variation = &"OptionStrip"
	add_child(strip)
	_bar.add_theme_constant_override("separation", 10)
	strip.add_child(_bar)
	_dot.glyph = "dot"
	_dot.extent = 10.0
	_dot.color = Tokens.INFO
	_name.theme_type_variation = &"Strong"
	_hint.theme_type_variation = &"Dim"
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.clip_text = true
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cell_text.theme_type_variation = &"MonoDim"
	start_text.theme_type_variation = &"Mono"
	tile_id.name = "TileID"
	tile_id.min_value = -32768
	tile_id.max_value = 32767
	tile_id.value = 1
	tile_id.custom_minimum_size.x = 100
	slot.name = "PlacementSlot"
	slot.prefix = "W"
	slot.max_value = 99
	slot.custom_minimum_size.x = 84
	chance.name = "PlacementChance"
	chance.suffix = "%"
	chance.max_value = 100
	chance.value = 100
	chance.custom_minimum_size.x = 100
	follow.name = "PlacementFollow"
	follow.text = "Return follows placement"
	new_button.text = "New at selected cell"
	new_button.pressed.connect(func(): new_at_cell_requested.emit())
	steps_button.text = "Open steps ↗"
	steps_button.theme_type_variation = &"GhostButton"
	steps_button.pressed.connect(func(): open_steps_requested.emit())
	slot.value_changed.connect(func(_value): _show_options())
	for entry in [["tile", "Tile", tile_id], ["slot", "Slot", slot], ["chance", "Chance", chance], ["stage", "Stage", stage], ["start", "Start", start_text]]:
		_boxes[entry[0]] = _labelled(entry[1], entry[2])
	_show_options()


## Registers the controls the drivers and the placement controller find by name.
func register(shell: Control) -> void:
	for node in [tile_id, slot, chance, follow]: shell.name_node(node.name, node)


## Fills the stage choice from the summary's stages.
func show_stages(stages: Array, chosen: int) -> void:
	_loading = true
	stage.clear()
	for row in stages:
		if row.get("active", false): stage.add_item("%d · %s" % [int(row.id), str(row.name)], int(row.id))
	var index := stage.get_item_index(chosen)
	if index >= 0: stage.select(index)
	_loading = false


func chosen_stage() -> int:
	return stage.get_selected_id() if stage.item_count > 0 else 0


func select_tool(name: String) -> void:
	if not _buttons.has(name): return
	tool = name
	for key in _buttons: _buttons[key].set_pressed_no_signal(key == name)
	_loading = true
	var target := {"paint": 0, "line": 0, "rectangle": 0, "fill": 0, "sample": 0, "trigger": 1, "erase": 1, "region": 2, "start": 3}
	if target.has(name): layer.select(target[name])
	_loading = false
	_show_options()
	tool_changed.emit(name)


## The hint under the tool: what a click does.
func hint_for(name: String) -> String:
	return {"select": "Click a cell to inspect it · double-click a trigger to open its steps", "sample": "Click a cell to pick its floor tile",
		"paint": "Drag to paint · one stroke is one undo step · right-click or Alt-click picks", "line": "Drag from one cell to another · one stroke is one undo step",
		"rectangle": "Drag from corner to corner · fills the rectangle · one undo step", "fill": "Click a cell to fill the tiles joined to it with the brush · one undo step",
		"trigger": "Click a cell to place W%d · Delete removes" % int(slot.value), "region": "Drag a handle to resize · drag inside to move · drag on empty floor draws a new region",
		"start": "Click a cell to move the start · the squad enters the stage here", "erase": "Click a cell to remove its walking trigger"}.get(name, "")


func _show_options() -> void:
	for child in _bar.get_children(): _bar.remove_child(child)
	_dot.color = {"trigger": Tokens.TRIGGER, "region": Tokens.REGION, "start": Tokens.START}.get(tool, Tokens.TEXT)
	_name.text = "Paint objects" if object_mode and tool == "paint" else NAMES.get(tool, "")
	_bar.add_child(_dot)
	_bar.add_child(_name)
	match tool:
		"select":
			_bar.add_child(cell_text)
			_bar.add_child(new_button)
		"paint", "line", "rectangle", "fill":
			_bar.add_child(_boxes.tile)
			if object_mode:
				for entry in [["Building…", building_requested], ["Icon…", icon_requested]]:
					var pick := Button.new()
					pick.text = entry[0]
					pick.theme_type_variation = &"GhostButton"
					pick.pressed.connect(func(): entry[1].emit())
					_bar.add_child(pick)
				var clear := Button.new()
				clear.text = "Nothing"
				clear.tooltip_text = "Paints 0, which removes an object"
				clear.theme_type_variation = &"GhostButton"
				clear.pressed.connect(func(): tile_id.value = 0)
				_bar.add_child(clear)
			else:
				var choose := Button.new()
				choose.text = "Choose…"
				choose.theme_type_variation = &"GhostButton"
				choose.pressed.connect(func(): choose_tile_requested.emit())
				_bar.add_child(choose)
		"trigger":
			_bar.add_child(_boxes.slot)
			_bar.add_child(_boxes.chance)
			_bar.add_child(follow)
			_bar.add_child(steps_button)
		"start":
			_bar.add_child(_boxes.stage)
			_bar.add_child(_boxes.start)
	_hint.text = hint_for(tool)
	_bar.add_child(_hint)


## A control with its dim name before it; the pair is rebuilt each time the options change.
func _labelled(text: String, control: Control) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Dim"
	box.add_child(label)
	box.add_child(control)
	return box


## Controls the current tool does not show are kept out of the tree; they are freed with the toolbar.
func _exit_tree() -> void:
	var kept: Array = [_dot, _name, cell_text, new_button, follow, steps_button, _hint]
	kept.append_array(_boxes.values())
	for node in kept:
		if is_instance_valid(node) and node.get_parent() == null: node.free()
