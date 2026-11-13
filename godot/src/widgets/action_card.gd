extends Button
## A whole card that is one choice: a glyph tile, a title with what it does,
## and the key that runs it.
const Glyph = preload("res://src/widgets/glyph.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

@export var title := "":
	set(value): title = value; _title.text = value
@export var body := "":
	set(value): body = value; _body.text = value
@export var key_hint := "":
	set(value): key_hint = value; _key.text = value; _key.visible = not value.is_empty()
@export var glyph := "":
	set(value): glyph = value; _glyph.glyph = value
## The card the author most likely wants is drawn with a filled tile.
@export var lead := false:
	set(value): lead = value; _tile.theme_type_variation = &"ActionTileOn" if value else &"ActionTile"; _glyph.color = Tokens.ACCENT_INK if value else Tokens.ACCENT

var _tile := PanelContainer.new()
var _glyph := Glyph.new()
var _title := Label.new()
var _body := Label.new()
var _key := Label.new()


func _init() -> void:
	theme_type_variation = &"ActionCard"
	custom_minimum_size = Vector2(0, 92)
	clip_contents = true
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	_tile.theme_type_variation = &"ActionTile"
	_tile.custom_minimum_size = Vector2(40, 40)
	_tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_tile)
	_glyph.extent = 20.0
	_glyph.color = Tokens.ACCENT
	_glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tile.add_child(_glyph)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)
	_title.theme_type_variation = &"Strong"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_title)
	_key.theme_type_variation = &"Kbd"
	_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key.visible = false
	head.add_child(_key)
	_body.theme_type_variation = &"Muted"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 12)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_body)
	# A button ignores what is inside it, so the card grows to its wrapped text.
	_body.minimum_size_changed.connect(_grow.call_deferred)
	resized.connect(_grow.call_deferred)


func _grow() -> void:
	# The key is dropped when the card is too narrow to hold it beside the title.
	_key.visible = not key_hint.is_empty() and size.x >= 270.0
	custom_minimum_size.y = maxf(92.0, 32.0 + _title.get_combined_minimum_size().y + _body.get_combined_minimum_size().y)


## A card whose action cannot run is drawn dim.
func set_available(available: bool) -> void:
	disabled = not available
	modulate.a = 1.0 if available else 0.5
