extends Control
## The graph of a program's calls: each program a card of its steps, each call
## an arrow from the step that makes it to the card it reaches. Cards stand in
## columns by how many calls away from the first one they are.
signal step_selected(key: String, branch: int, slot: int)
const Capability = preload("res://src/scripts/capability.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

const CARD_WIDTH := 300.0
const GAP := Vector2(70, 26)

var graph: Dictionary = {}
var show_steps := true
var show_text := true
var content_size := Vector2.ZERO
var selected_key := ""
var cards: Dictionary = {}
var _rows: Dictionary = {}
var _edges: Array = []


func show_graph(value: Dictionary) -> void:
	graph = value
	rebuild()


func rebuild() -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	cards.clear()
	_rows.clear()
	if graph.is_empty(): return
	var depth := _depths()
	var columns: Dictionary = {}
	for node in graph.nodes:
		var column: int = depth.get(node.key, 0)
		if not columns.has(column): columns[column] = []
		columns[column].append(node)
	var extent := Vector2.ZERO
	for column in columns.keys():
		var y := 0.0
		for node in columns[column]:
			var card := _card(node)
			card.position = Vector2(column * (CARD_WIDTH + GAP.x), y)
			card.size = Vector2(CARD_WIDTH, card.get_combined_minimum_size().y)
			y += card.size.y + GAP.y
			extent = extent.max(card.position + card.size)
		extent.y = maxf(extent.y, y - GAP.y)
	content_size = extent + Vector2(12, 12)
	custom_minimum_size = content_size
	_edges = graph.edges
	_mark()
	queue_redraw.call_deferred()


func _depths() -> Dictionary:
	var depth := {graph.root: 0}
	var queue: Array = [graph.root]
	while not queue.is_empty():
		var key: String = queue.pop_front()
		for edge in graph.edges:
			if edge.from == key and not depth.has(edge.to):
				depth[edge.to] = int(depth[key]) + 1
				queue.append(edge.to)
	return depth


func _card(node: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	card.custom_minimum_size.x = CARD_WIDTH
	add_child(card)
	cards[node.key] = card
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = node.title
	title.theme_type_variation = &"Heading"
	head.add_child(title)
	var kind := Label.new()
	kind.theme_type_variation = &"Dim"
	kind.text = {"story": "story", "choice": "choice encounter", "typed": "typed encounter", "walking": "walking trigger"}.get(node.kind, node.kind)
	kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(kind)
	column.add_child(head)
	if node.kind in ["choice", "typed"]:
		var many := Label.new()
		many.theme_type_variation = &"Dim"
		many.text = "%d branches" % node.branches.size()
		column.add_child(many)
	if not show_steps: return card
	for branch in node.branches:
		var holder: VBoxContainer = column
		if node.kind in ["choice", "typed"]:
			var section := PanelContainer.new()
			section.theme_type_variation = &"Detail"
			var inner := VBoxContainer.new()
			inner.add_theme_constant_override("separation", 2)
			section.add_child(inner)
			var name := Label.new()
			name.text = "Branch %d" % int(branch.branch)
			name.theme_type_variation = &"Heading"
			inner.add_child(name)
			if not str(branch.label).is_empty():
				var words := Label.new()
				words.theme_type_variation = &"Dim"
				words.text = str(branch.label)
				words.clip_text = true
				inner.add_child(words)
			column.add_child(section)
			holder = inner
		for step in branch.steps: holder.add_child(_step_row(node, int(branch.branch), step))
	return card


func _step_row(node: Dictionary, branch: int, step: Dictionary) -> Control:
	var button := Button.new()
	button.theme_type_variation = &"RowButton"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	var text := "%d   %s" % [int(step.slot) + 1, str(step.name)]
	if show_text and step.get("text") != null: text += "  ·  " + str(step.text)
	button.text = text
	var colour := Capability.kind_colour(Capability.kind_of(int(step.opcode), bool(step.authorable)))
	button.add_theme_color_override("font_color", colour if step.authorable else Tokens.DIM)
	if not step.authorable: button.tooltip_text = "Preserved as recorded"
	button.pressed.connect(func(): select(node.key, branch, int(step.slot)))
	_rows["%s:%d:%d" % [node.key, branch, int(step.slot)]] = button
	return button


func select(key: String, branch: int, slot: int) -> void:
	selected_key = key
	_mark()
	step_selected.emit(key, branch, slot)


func _mark() -> void:
	for key in cards:
		var card: PanelContainer = cards[key]
		var style: StyleBox = card.get_theme_stylebox("panel").duplicate()
		if style is StyleBoxFlat and key == selected_key:
			style.border_color = Tokens.ACCENT
			style.set_border_width_all(2)
		card.add_theme_stylebox_override("panel", style)
	queue_redraw()


func _draw() -> void:
	for edge in _edges:
		var source: Control = _rows.get("%s:%d:%d" % [edge.from, int(edge.branch), int(edge.slot)])
		var card: Control = cards.get(edge.to)
		if card == null: continue
		var origin: Control = cards.get(edge.from)
		if origin == null: continue
		var from := origin.position + Vector2(origin.size.x, 20)
		if source != null: from.y = (get_global_transform().affine_inverse() * source.get_global_rect().get_center()).y
		var to := card.position + Vector2(0, 22)
		var reach := maxf(60.0, absf(to.x - from.x) * 0.5)
		var points := PackedVector2Array()
		for step in range(0, 25):
			var t := step / 24.0
			var a := from.lerp(from + Vector2(reach, 0), t)
			var b := (from + Vector2(reach, 0)).lerp(to - Vector2(reach, 0), t)
			var c := (to - Vector2(reach, 0)).lerp(to, t)
			points.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
		var colour := Tokens.tint(Tokens.FAMILY.encounter, 0.9)
		draw_polyline(points, colour, 1.5, true)
		draw_colored_polygon(PackedVector2Array([to, to + Vector2(-8, -4), to + Vector2(-8, 4)]), colour)
