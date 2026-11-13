extends "res://src/widgets/modal_overlay.gd"
## Choose floor: the terrain's tiles large, the one under the cursor and the one
## in use beside them. Arrow keys move, Enter uses it.
signal tile_chosen(tile: int)
const KbdButton = preload("res://src/widgets/kbd_button.gd")
const TilePalette = preload("res://src/tile_palette.gd")

var palette := TilePalette.new()
var _atlas: Texture2D
var _picked := 0
var _current := 0
var _terrain := Label.new()
var _preview := TextureRect.new()
var _name := Label.new()
var _info := Label.new()
var _now_preview := TextureRect.new()
var _now_name := Label.new()
var _note := Label.new()
var _use: KbdButton


func _init() -> void:
	super()
	title = "Choose floor"
	panel_size = Vector2(900, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	body.add_child(column)
	var head := HBoxContainer.new()
	_terrain.theme_type_variation = &"Badge"
	head.add_child(_terrain)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var keys := Label.new()
	keys.theme_type_variation = &"Dim"
	keys.text = "Arrow keys move · Enter uses"
	head.add_child(keys)
	column.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	palette.custom_minimum_size.x = 520
	palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette.chosen.connect(func(tile, _alt): _pick(tile))
	row.add_child(palette)
	var side := PanelContainer.new()
	side.theme_type_variation = &"Detail"
	side.custom_minimum_size.x = 250
	row.add_child(side)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	side.add_child(stack)
	_preview.custom_minimum_size = Vector2(110, 110)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stack.add_child(_preview)
	_name.theme_type_variation = &"Heading"
	stack.add_child(_name)
	_info.theme_type_variation = &"MonoDim"
	stack.add_child(_info)
	stack.add_child(HSeparator.new())
	var now := HBoxContainer.new()
	now.add_theme_constant_override("separation", 10)
	_now_preview.custom_minimum_size = Vector2(36, 36)
	_now_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_now_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	now.add_child(_now_preview)
	var now_words := VBoxContainer.new()
	now_words.add_theme_constant_override("separation", 0)
	var now_caption := Label.new()
	now_caption.theme_type_variation = &"Dim"
	now_caption.text = "Current"
	now_words.add_child(now_caption)
	now_words.add_child(_now_name)
	now.add_child(now_words)
	stack.add_child(now)
	_note.theme_type_variation = &"Muted"
	_note.add_theme_font_size_override("font_size", 12)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_note)
	add_button("Cancel").pressed.connect(close)
	_use = KbdButton.new()
	_use.theme_type_variation = &"PrimaryButton"
	_use.hint = "Enter"
	_use.pressed.connect(_commit)
	add_footer_button(_use)


func _thumb(tile: int) -> Texture2D:
	if _atlas == null or tile < 1 or tile > 300: return null
	var texture := AtlasTexture.new()
	texture.atlas = _atlas
	texture.region = Rect2(Vector2(((tile - 1) % 20) * 32, ((tile - 1) / 20) * 32), Vector2(32, 32))
	return texture


func _pick(tile: int) -> void:
	_picked = tile
	palette.current = tile
	_preview.texture = _thumb(tile)
	_name.text = "Tile %d" % tile
	_use.text = "Use tile %d" % tile


## Opens for one cell. `terrain` is the map's terrain number, or -1.
func show_for(map_id: int, cell: Vector2i, current: int, atlas: Texture2D, icons: Dictionary, terrain: int, picture: int) -> void:
	_atlas = atlas
	subtitle = "Map %d · cell %d, %d" % [map_id, cell.x, cell.y]
	palette.atlas = atlas
	palette.icons = icons
	_current = current
	_terrain.text = "Terrain %d  %d" % [terrain, 300] if terrain >= 0 else "Floors"
	_info.text = "terrain %s · floor" % (str(terrain) if terrain >= 0 else "?")
	_now_preview.texture = _thumb(current)
	_now_name.text = "Tile %d" % current
	_note.text = "Changes cell %d, %d's floor as one undo step. Alt-click on the map picks a tile." % [cell.x, cell.y]
	_pick(current)
	open()
	palette.grab_focus()


func _commit() -> void:
	close()
	tile_chosen.emit(_picked)


func _unhandled_key_input(event: InputEvent) -> void:
	super(event)
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_commit()
		get_viewport().set_input_as_handled()
