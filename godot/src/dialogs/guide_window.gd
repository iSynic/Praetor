extends Window
## The guide to the editor: a window of its own, which can stay open beside the editor, with the chapters at the left and the
## text and pictures at the right. It reads data/guide/guide.json, built from docs/guide/guide.md by tools/build_guide.py.
const Prose = preload("res://src/widgets/prose.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

const GUIDE := "res://data/guide/guide.json"
const PICTURES := "res://data/guide/%s.png"
## The colour names of the table of step colours, and the kind of step each one is.
const SWATCH := {"Blue": "message", "Violet": "encounter", "Orange": "combat", "Yellow": "test", "Teal": "jump", "Pink": "pick", "Red": "vitals", "Brown": "gear", "Periwinkle": "map", "Mint": "clock", "Lilac": "mission", "Amber": "shop", "Cyan": "media", "Green": "reward", "Lime": "ally", "Grey": "preserved"}
const READING_WIDTH := 980

var document: Dictionary = {}
var contents := Tree.new()
var _scroll := ScrollContainer.new()
var _column := VBoxContainer.new()
var _anchors: Dictionary = {}
var _pictures: Array = []


func _init() -> void:
	title = "Guide to the editor"
	visible = false
	min_size = Vector2i(760, 480)
	size = Vector2i(1280, 860)
	# A window of the operating system when the editor runs in one; an embedded one in the captures.
	force_native = OS.get_environment("CENTURIONS_CAPTURE_OUT").is_empty()
	exclusive = false
	transient = false
	close_requested.connect(hide)
	size_changed.connect(_fit)
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Tokens.PANEL
	background.add_theme_stylebox_override("panel", style)
	add_child(background)
	var split := HSplitContainer.new()
	split.split_offset = 230
	background.add_child(split)
	var side := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]: side.add_theme_constant_override("margin_" + edge, 12)
	side.custom_minimum_size.x = 200
	split.add_child(side)
	contents.hide_root = true
	contents.select_mode = Tree.SELECT_ROW
	contents.item_selected.connect(_chosen)
	side.add_child(contents)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_scroll)
	var wrap := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]: wrap.add_theme_constant_override("margin_" + edge, 24)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(wrap)
	_column.add_theme_constant_override("separation", 12)
	_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrap.add_child(_column)


## Opens the guide at `chapter` (a chapter's title, or "" for the beginning).
func show_guide(chapter := "") -> void:
	if document.is_empty(): _build()
	if not visible:
		popup_centered(Vector2i(1280, 860))
	else:
		grab_focus()
	_fit()
	if not chapter.is_empty(): await _go(chapter)


func _build() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GUIDE))
	if not parsed is Dictionary: return
	document = parsed
	_anchors.clear()
	_pictures.clear()
	for child in _column.get_children(): child.queue_free()
	var root := contents.create_item()
	var top := Label.new()
	top.theme_type_variation = &"Heading"
	top.add_theme_font_size_override("font_size", 28)
	top.text = str(document.title)
	_column.add_child(top)
	var subtitle := Label.new()
	subtitle.theme_type_variation = &"Dim"
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.text = str(document.subtitle)
	_column.add_child(subtitle)
	_blocks(document.get("intro", []))
	var first := contents.create_item(root)
	first.set_text(0, "Introduction")
	first.set_metadata(0, "Introduction")
	_anchors["Introduction"] = top
	for chapter in document.chapters:
		var item := contents.create_item(root)
		item.set_text(0, str(chapter.title))
		item.set_metadata(0, str(chapter.title))
		var heading := _heading(str(chapter.title), 24)
		_anchors[str(chapter.title)] = heading
		_blocks(chapter.lead)
		for part in chapter.sections:
			var child := contents.create_item(item)
			child.set_text(0, str(part.title))
			child.set_metadata(0, "%s/%s" % [chapter.title, part.title])
			child.set_custom_color(0, Tokens.DIM)
			_anchors["%s/%s" % [chapter.title, part.title]] = _heading(str(part.title), 18)
			_blocks(part.blocks)
		item.collapsed = true
	await get_tree().process_frame
	_fit()


func _heading(text: String, size: int) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"Heading"
	label.add_theme_font_size_override("font_size", size)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var gap := Control.new()
	gap.custom_minimum_size.y = 10 if size > 20 else 4
	_column.add_child(gap)
	_column.add_child(label)
	return label


func _blocks(blocks: Array) -> void:
	for block in blocks:
		if block.has("p"):
			var prose := Prose.new()
			prose.show_markup(str(block.p))
			_column.add_child(prose)
		elif block.has("note"):
			_note(str(block.note))
		elif block.has("li"):
			for item in block.li:
				var numbered := str(item).length() > 2 and str(item)[1] == ")"
				var line := Prose.new()
				line.show_markup(str(item) if numbered else "•  " + str(item))
				var indent := MarginContainer.new()
				indent.add_theme_constant_override("margin_left", 14)
				indent.add_child(line)
				_column.add_child(indent)
		elif block.has("table"):
			_table(block.table)
		elif block.has("figure"):
			_figure(str(block.figure), str(block.caption))


func _note(text: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Card"
	var prose := Prose.new()
	prose.show_markup("**NOTE:** " + text)
	panel.add_child(prose)
	_column.add_child(panel)


func _table(rows: Array) -> void:
	if rows.is_empty(): return
	var grid := GridContainer.new()
	grid.columns = rows[0].size() + (1 if str(rows[0][0]) == "Colour" else 0)
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	var coloured := str(rows[0][0]) == "Colour"
	for index in range(rows.size()):
		if coloured:
			var swatch := ColorRect.new()
			swatch.custom_minimum_size = Vector2(14, 14)
			swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			swatch.color = Tokens.KIND.get(SWATCH.get(str(rows[index][0]), ""), Color.TRANSPARENT) if index > 0 else Color.TRANSPARENT
			grid.add_child(swatch)
		for cell in rows[index]:
			var label := Label.new()
			label.theme_type_variation = &"Strong" if index == 0 else &""
			label.text = str(cell)
			grid.add_child(label)
	_column.add_child(grid)


func _figure(name: String, caption: String) -> void:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 4)
	# The pictures show the game's own art, so a copy of the editor carries none; they are built from the player's
	# installation (tools/build_guide_pictures.py).
	if not ResourceLoader.exists(PICTURES % name):
		var missing := Label.new()
		missing.theme_type_variation = &"Dim"
		missing.text = "%s\n(The picture shows the game's own art and is not shipped. tools/build_guide_pictures.py makes it from your installation.)" % caption
		missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		holder.add_child(missing)
		_column.add_child(holder)
		return
	var texture: Texture2D = load(PICTURES % name)
	if texture == null: return
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	holder.add_child(picture)
	var words := Label.new()
	words.theme_type_variation = &"Dim"
	words.text = caption
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	holder.add_child(words)
	_column.add_child(holder)
	_pictures.append(picture)


## The reading column takes the width of the window up to a comfortable measure, and each picture its height.
func _fit() -> void:
	if _scroll == null or _column == null: return
	var width := clampf(_scroll.size.x - 48.0 - 14.0, 320.0, float(READING_WIDTH))
	_column.custom_minimum_size.x = width
	for picture in _pictures:
		var texture: Texture2D = picture.texture
		picture.custom_minimum_size = Vector2(width, floorf(width * texture.get_height() / texture.get_width()))


func _chosen() -> void:
	var item := contents.get_selected()
	if item != null: _go(str(item.get_metadata(0)))


func _go(key: String) -> void:
	var anchor: Control = _anchors.get(key)
	if anchor == null: return
	await get_tree().process_frame
	_scroll.scroll_vertical = int(anchor.global_position.y - _column.global_position.y) + 24
