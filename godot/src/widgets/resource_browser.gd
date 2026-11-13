extends VBoxContainer
## Browses the icons, pictures and sounds of the scenario and of the game: a grid of what exists, and the one in
## hand shown large with what is known of it. The Resources page puts its actions under the detail; the picker
## dialog puts a Use button there.
signal selected(kind: String, id: int)
signal activated(kind: String, id: int)
const Card = preload("res://src/widgets/card.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

const KINDS := [["icon", "Icons"], ["picture", "Pictures"], ["sound", "Sounds"]]
const NAMES := {"icon": "icons", "picture": "pictures", "sound": "sounds"}
## Tiles drawn at most; the number box narrows what matches.
const TILES := 400
## No resource chosen; every number a resource can have, negative ones too, is a choice.
const NONE := -100000

var shell: Control
var kind := "icon"
var scope := "scenario"
var selected_id := NONE
## The actions of whoever shows the browser go here, under the detail.
var actions := VBoxContainer.new()
var _lists: Dictionary = {}
var _revision := -1
var _kind_chips: Dictionary = {}
var _scope_chips: Dictionary = {}
var _search := LineEdit.new()
var _note := Label.new()
var _flow := HFlowContainer.new()
var _tiles: Dictionary = {}
var _detail := Card.new()
var _preview := TextureRect.new()
var _facts := VBoxContainer.new()
var _play := Button.new()
var _sound_note := Label.new()
var _build := 0


func _init() -> void:
	add_theme_constant_override("separation", 12)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 20)
	add_child(filters)
	var kinds := HBoxContainer.new()
	kinds.add_theme_constant_override("separation", 8)
	filters.add_child(kinds)
	var kind_group := ButtonGroup.new()
	for entry in KINDS:
		var chip := _chip(entry[1], kind_group, entry[0] == kind)
		chip.pressed.connect(func(): show_kind(entry[0]))
		kinds.add_child(chip)
		_kind_chips[entry[0]] = chip
	var scopes := HBoxContainer.new()
	scopes.add_theme_constant_override("separation", 8)
	filters.add_child(scopes)
	var scope_group := ButtonGroup.new()
	for entry in [["scenario", "This scenario"], ["game", "The game"], ["both", "Both"]]:
		var chip := _chip(entry[1], scope_group, entry[0] == scope)
		chip.pressed.connect(func(): scope = entry[0]; _fill())
		scopes.add_child(chip)
		_scope_chips[entry[0]] = chip
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(spacer)
	_search.placeholder_text = "Number"
	_search.custom_minimum_size.x = 160
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text): _fill())
	filters.add_child(_search)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var grid_card := PanelContainer.new()
	grid_card.theme_type_variation = &"Card"
	grid_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(grid_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	grid_card.add_child(column)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.add_theme_constant_override("h_separation", 8)
	_flow.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_flow)
	_note.theme_type_variation = &"Dim"
	column.add_child(_note)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 280
	side.add_theme_constant_override("separation", 12)
	body.add_child(side)
	_detail.title = "Nothing chosen"
	_preview.custom_minimum_size = Vector2(0, 170)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail.add_row(_preview)
	_play.text = "▶ Play"
	_play.visible = false
	_play.pressed.connect(func(): _sound_note.text = await shell.references.play_sound(selected_id))
	_detail.add_row(_play)
	_sound_note.theme_type_variation = &"Dim"
	_sound_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_row(_sound_note)
	_facts.add_theme_constant_override("separation", 4)
	_detail.add_row(_facts)
	side.add_child(_detail)
	actions.add_theme_constant_override("separation", 8)
	side.add_child(actions)


func _chip(text: String, group: ButtonGroup, on: bool) -> Button:
	var chip := Button.new()
	chip.theme_type_variation = &"Chip"
	chip.toggle_mode = true
	chip.button_group = group
	chip.text = text
	chip.set_pressed_no_signal(on)
	return chip


func setup(owner_shell: Control) -> void:
	shell = owner_shell


## Shows the kind and number given, reading what exists again when the records changed.
func open(show: String, id := NONE) -> void:
	kind = show
	_kind_chips[kind].set_pressed_no_signal(true)
	selected_id = id
	await load_lists()
	if id != NONE and not _visible_ids().has(id):
		scope = "both"
		_scope_chips["both"].set_pressed_no_signal(true)
	_fill()


func load_lists() -> void:
	if shell.summary.is_empty(): return
	if _revision == shell.bridge.revision and not _lists.is_empty(): return
	var response: Dictionary = await shell.request_backend({"op": "resources", "installation": shell.folder})
	if not response.get("ok", false): return
	_lists = {}
	for key in response.result:
		var entry: Dictionary = response.result[key]
		_lists[key] = {"scenario": _whole(entry.scenario), "game": _whole(entry.game)}
	_revision = shell.bridge.revision


## Whole numbers, since the adapter's numbers arrive as floats and a list of floats does not find an integer.
func _whole(ids: Array) -> Array:
	var out: Array = []
	for id in ids: out.append(int(id))
	return out


func show_kind(next: String) -> void:
	kind = next
	selected_id = NONE
	_fill()


func _ids_of(which: String) -> Array:
	var entry: Dictionary = _lists.get(NAMES[kind], {})
	if which == "both":
		var union: Array = entry.get("scenario", []).duplicate()
		for id in entry.get("game", []):
			if not union.has(id): union.append(id)
		union.sort()
		return union
	return entry.get(which, [])


func _visible_ids() -> Array:
	var needle := _search.text.strip_edges()
	var ids: Array = []
	for id in _ids_of(scope):
		if needle.is_empty() or str(int(id)).contains(needle): ids.append(int(id))
	return ids


func _fill() -> void:
	_build += 1
	var build := _build
	for child in _flow.get_children(): _flow.remove_child(child); child.queue_free()
	_tiles.clear()
	for entry in KINDS: _kind_chips[entry[0]].text = "%s %d" % [entry[1], _ids_of("scenario").size() if entry[0] == kind else _count(entry[0])]
	var ids := _visible_ids()
	var scenario: Array = _lists.get(NAMES[kind], {}).get("scenario", [])
	var shown := ids.slice(0, TILES)
	for id in shown: _flow.add_child(_tile(int(id), scenario.has(id)))
	_note.text = "Showing %d of %d · narrow with the number box" % [shown.size(), ids.size()] if ids.size() > TILES else "%d %s" % [ids.size(), NAMES[kind]]
	if selected_id != NONE and not ids.has(selected_id): selected_id = NONE
	if selected_id == NONE and not ids.is_empty(): selected_id = int(ids[0])
	_show_detail()
	if kind == "icon":
		await shell.references.fetch(shown)
		if build != _build: return
		for id in shown:
			if _tiles.has(id) and is_instance_valid(_tiles[id].picture): _tiles[id].picture.texture = shell.references.icon(int(id))


func _count(of: String) -> int:
	var entry: Dictionary = _lists.get(NAMES[of], {})
	return entry.get("scenario", []).size()


func _tile(id: int, mine: bool) -> Control:
	var tile := Button.new()
	tile.toggle_mode = true
	tile.custom_minimum_size = Vector2(76, 82)
	tile.theme_type_variation = &"Chip"
	tile.set_pressed_no_signal(id == selected_id)
	tile.pressed.connect(func(): choose(id))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_top = 6
	box.offset_bottom = -4
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2(48, 44)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if kind != "icon":
		var glyph := Label.new()
		glyph.text = "PICT" if kind == "picture" else "♪"
		glyph.theme_type_variation = &"Dim"
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.custom_minimum_size = Vector2(48, 44)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(glyph)
	else:
		box.add_child(picture)
	var label := Label.new()
	label.text = str(id) + (" ·" if mine and scope == "both" else "")
	label.theme_type_variation = &"Mono"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	tile.add_child(box)
	tile.gui_input.connect(func(event): if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT: activated.emit(kind, id))
	_tiles[id] = {"button": tile, "picture": picture}
	return tile


func choose(id: int) -> void:
	selected_id = id
	for key in _tiles: _tiles[key].button.set_pressed_no_signal(int(key) == id)
	_show_detail()
	selected.emit(kind, id)


func _show_detail() -> void:
	for child in _facts.get_children(): _facts.remove_child(child); child.queue_free()
	_play.visible = false
	_sound_note.text = ""
	_preview.texture = null
	if selected_id == NONE:
		_detail.title = "Nothing chosen"
		return
	_detail.title = "%s %d" % [kind.capitalize(), selected_id]
	var entry: Dictionary = _lists.get(NAMES[kind], {})
	var mine: bool = entry.get("scenario", []).has(selected_id)
	var source := "This scenario" if mine else "The game"
	if mine and entry.get("game", []).has(selected_id): source = "This scenario (the game holds this number too)"
	_fact("From", source)
	var id := selected_id
	match kind:
		"icon":
			await shell.references.fetch([id])
			if id != selected_id: return
			var texture: Texture2D = shell.references.icon(id)
			_preview.texture = texture
			if texture != null: _fact("Size", "%d × %d" % [texture.get_width(), texture.get_height()])
		"picture":
			var texture: Texture2D = await shell.references.picture(id)
			if id != selected_id: return
			_preview.texture = texture
			if texture != null: _fact("Size", "%d × %d" % [texture.get_width(), texture.get_height()])
		"sound":
			var found: Dictionary = await shell.references.sound(id)
			if id != selected_id: return
			_play.visible = found.has("stream")
			if found.has("stream"): _fact("Length", "%.1f s" % float(found.seconds))
			else: _sound_note.text = str(found.note)


func _fact(key: String, value: String) -> void:
	var line := HBoxContainer.new()
	var name := Label.new()
	name.theme_type_variation = &"Dim"
	name.text = key
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name)
	var text := Label.new()
	text.text = value
	line.add_child(text)
	_facts.add_child(line)
