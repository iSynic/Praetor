extends Window
## View flow: the calls a program makes, across stories, choices and typed encounters, as cards joined by arrows.
## It is a window of its own, which can stay open beside the editor, be moved and resized; the graph zooms with the
## buttons, Ctrl and the wheel, or Ctrl with + and -, and drags with the middle button. Choosing a step names where
## it leads; Open takes the author to it.
const FlowCanvas = preload("res://src/widgets/flow_canvas.gd")
const KbdButton = preload("res://src/widgets/kbd_button.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

const ZOOM_LEAST := 0.25
const ZOOM_MOST := 2.0

var shell: Control
var graph: Dictionary = {}
var canvas := FlowCanvas.new()
var family := "story"
var program_id := 0
var zoom := 1.0
var _wrap := Control.new()
var _graph_scroll := ScrollContainer.new()
var _root_label := LineEdit.new()
var _zoom := Button.new()
var _steps := Button.new()
var _text := Button.new()
var _note := Label.new()
var _callers: Button
var _open: KbdButton
var _selected := {}
var _dragging := false


func _init() -> void:
	title = "View flow"
	visible = false
	min_size = Vector2i(640, 420)
	# A window of the operating system when the editor runs in one; an embedded one in the captures.
	force_native = OS.get_environment("CENTURIONS_CAPTURE_OUT").is_empty()
	exclusive = false
	transient = false
	close_requested.connect(close)
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Tokens.PANEL
	background.add_theme_stylebox_override("panel", style)
	add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 14)
	background.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 8)
	bar.add_theme_constant_override("v_separation", 6)
	column.add_child(bar)
	_root_label.editable = false
	_root_label.custom_minimum_size.x = 170
	bar.add_child(_root_label)
	for entry in [[_steps, "Steps"], [_text, "Message text"]]:
		var chip: Button = entry[0]
		chip.theme_type_variation = &"Chip"
		chip.toggle_mode = true
		chip.button_pressed = true
		chip.text = entry[1]
		chip.toggled.connect(func(_on): _rebuild())
		bar.add_child(chip)
	var callers_chip := Button.new()
	callers_chip.theme_type_variation = &"Chip"
	callers_chip.text = "Callers"
	callers_chip.disabled = true
	callers_chip.tooltip_text = "The graph follows calls forward; Callers lists what calls the chosen record"
	bar.add_child(callers_chip)
	for entry in [["message", "Message"], ["encounter", "Encounter"], ["combat", "Combat"], ["media", "Sound"], ["reward", "Reward"], ["test", "Test"], ["jump", "Jump"]]:
		var key := Label.new()
		key.theme_type_variation = &"Dim"
		key.text = "▌" + entry[1]
		key.add_theme_color_override("font_color", Tokens.KIND.get(entry[0], Tokens.DIM))
		bar.add_child(key)
	for entry in [["−", "Zoom out (Ctrl and −)", func(): zoom_by(0.8)], ["+", "Zoom in (Ctrl and +)", func(): zoom_by(1.25)]]:
		var button := Button.new()
		button.text = entry[0]
		button.tooltip_text = entry[1]
		button.custom_minimum_size.x = 32
		button.pressed.connect(entry[2])
		bar.add_child(button)
	_zoom.text = "100%"
	_zoom.tooltip_text = "Show the graph at its own size (Ctrl and 0)"
	_zoom.custom_minimum_size.x = 56
	_zoom.pressed.connect(func(): set_zoom(1.0))
	bar.add_child(_zoom)
	var fit := Button.new()
	fit.text = "Fit"
	fit.tooltip_text = "Scale the graph to the window, never larger than its own size"
	fit.pressed.connect(fit_to_view)
	bar.add_child(fit)
	var well := PanelContainer.new()
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var well_style := StyleBoxFlat.new()
	well_style.bg_color = Tokens.INK
	well.add_theme_stylebox_override("panel", well_style)
	column.add_child(well)
	_graph_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	well.add_child(_graph_scroll)
	_wrap.add_child(canvas)
	_graph_scroll.add_child(_wrap)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	column.add_child(footer)
	_note.theme_type_variation = &"Muted"
	_note.clip_text = true
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_note)
	_callers = Button.new()
	_callers.text = "Callers"
	_callers.pressed.connect(func(): if not _selected.is_empty(): shell.find_uses(str(_selected.kind), int(_selected.id)))
	footer.add_child(_callers)
	_open = KbdButton.new()
	_open.theme_type_variation = &"PrimaryButton"
	_open.text = "Open"
	_open.hint = "Enter"
	_open.pressed.connect(open_selected)
	footer.add_child(_open)
	canvas.step_selected.connect(_step_selected)


func setup(owner_shell: Control) -> void:
	shell = owner_shell


## Where the window is, for the checks that it stays on screen.
func panel_rect() -> Rect2:
	return Rect2(Vector2(position), Vector2(size))


func close() -> void:
	hide()


## Opens the flow of a program.
func show_for(program_family: String, id: int) -> void:
	if shell.summary.is_empty(): return
	var response: Dictionary = await shell.request_backend({"op": "flow", "family": program_family, "id": id})
	if not response.get("ok", false): return
	family = program_family
	program_id = id
	graph = response.result
	var root_node: Dictionary = graph.nodes[0]
	_root_label.text = root_node.title
	title = "View flow · " + str(root_node.title)
	_selected = {"kind": root_node.kind, "id": root_node.id, "slot": -1, "branch": 0}
	_note.text = "%s · %d records · %d branches end here%s" % [root_node.title, int(graph.records), int(graph.ends), " · the graph is cut at 40 records" if graph.get("truncated", false) else ""]
	if not visible:
		var room := Vector2i(get_tree().root.size) if not force_native else Vector2i(DisplayServer.screen_get_usable_rect().size)
		popup_centered(Vector2i(mini(1200, room.x - 80), mini(800, room.y - 80)))
	else:
		grab_focus()
	_rebuild()
	await get_tree().process_frame
	fit_to_view()


func _rebuild() -> void:
	canvas.show_steps = _steps.button_pressed
	canvas.show_text = _text.button_pressed
	if not graph.is_empty(): canvas.show_graph(graph)


## Scales the graph down to the room there is, never up.
func fit_to_view() -> void:
	await get_tree().process_frame
	var room := _graph_scroll.size - Vector2(18, 18)
	var content := canvas.content_size
	var factor := 1.0
	if content.x > 0 and content.y > 0 and room.x > 0 and room.y > 0: factor = minf(1.0, minf(room.x / content.x, room.y / content.y))
	set_zoom(factor)


func zoom_by(factor: float) -> void:
	set_zoom(zoom * factor)


## Shows the graph at `value` times its own size, keeping the point under `about` (the middle of the view by default) where it is.
func set_zoom(value: float, about := Vector2(-1, -1)) -> void:
	var next := clampf(value, ZOOM_LEAST, ZOOM_MOST)
	var anchor := about if about.x >= 0 else _graph_scroll.size / 2.0
	var at := (Vector2(_graph_scroll.scroll_horizontal, _graph_scroll.scroll_vertical) + anchor) / zoom
	zoom = next
	canvas.scale = Vector2(zoom, zoom)
	_wrap.custom_minimum_size = canvas.content_size * zoom
	_zoom.text = "%d%%" % roundi(zoom * 100.0)
	await get_tree().process_frame
	var target := at * zoom - anchor
	_graph_scroll.scroll_horizontal = maxi(0, roundi(target.x))
	_graph_scroll.scroll_vertical = maxi(0, roundi(target.y))
	canvas.queue_redraw()


func _step_selected(key: String, branch: int, slot: int) -> void:
	var node: Dictionary = {}
	for candidate in graph.nodes:
		if candidate.key == key: node = candidate
	if node.is_empty(): return
	_selected = {"kind": node.kind, "id": node.id, "slot": slot, "branch": branch}
	var found: Dictionary = {}
	var label := ""
	for entry in node.branches:
		if int(entry.branch) == branch:
			label = str(entry.label)
			for step in entry.steps:
				if int(step.slot) == slot: found = step
	var where: String = node.title + (" · branch %d" % branch if node.kind in ["choice", "typed"] else "")
	var text := str(found.get("name", ""))
	if not label.is_empty(): where += "  \"%s\"" % label
	_note.text = "%s · step %d · %s%s" % [where, slot + 1, text, "  · leads to " + str(found.target) if found.get("target") != null else ""]


func open_selected() -> void:
	if _selected.is_empty(): return
	var main: Window = get_tree().root
	hide()
	main.grab_focus()
	shell.guard(shell.navigator.go.bind(str(_selected.kind), int(_selected.id), int(_selected.slot), int(_selected.branch)))


func _input(event: InputEvent) -> void:
	if not visible: return
	var mouse := _graph_scroll.get_local_mouse_position()
	var over := Rect2(Vector2.ZERO, _graph_scroll.size).has_point(mouse)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed and over
		elif event.pressed and over and event.ctrl_pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			set_zoom(zoom * (1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1), mouse)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_graph_scroll.scroll_horizontal -= roundi(event.relative.x)
		_graph_scroll.scroll_vertical -= roundi(event.relative.y)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			open_selected()
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
			zoom_by(1.25)
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			zoom_by(0.8)
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode in [KEY_0, KEY_KP_0]:
			set_zoom(1.0)
			get_viewport().set_input_as_handled()
