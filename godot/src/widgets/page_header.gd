extends VBoxContainer
## The head of a record page: its title with badges, a line saying where the
## record lives, and the buttons that act on it. The buttons wrap under the
## title when the page is narrow.
const Tokens = preload("res://theme/editor_tokens.gd")

var title := Label.new()
var sub := Label.new()
var _badges := HBoxContainer.new()
var _buttons := HFlowContainer.new()
var _dot := preload("res://src/widgets/glyph.gd").new()


func _init() -> void:
	add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var lead := HFlowContainer.new()
	lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lead.add_theme_constant_override("h_separation", 10)
	lead.add_theme_constant_override("v_separation", 4)
	row.add_child(lead)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	lead.add_child(name_row)
	_dot.glyph = "dot"
	_dot.extent = 14.0
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dot.visible = false
	name_row.add_child(_dot)
	title.theme_type_variation = &"PageTitle"
	title.add_theme_font_size_override("font_size", 22)
	name_row.add_child(title)
	_badges.add_theme_constant_override("separation", 6)
	_badges.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lead.add_child(_badges)
	_buttons.alignment = FlowContainer.ALIGNMENT_END
	_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buttons.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_buttons.add_theme_constant_override("h_separation", 8)
	_buttons.add_theme_constant_override("v_separation", 6)
	row.add_child(_buttons)
	sub.theme_type_variation = &"Dim"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(sub)


## The dot before the title, in the colour of the record's family.
func mark(color: Color) -> void:
	_dot.color = color
	_dot.visible = true


## Replaces the badges: each is [text, variation].
func show_badges(badges: Array) -> void:
	for child in _badges.get_children(): _badges.remove_child(child); child.queue_free()
	for entry in badges:
		var badge := Label.new()
		badge.theme_type_variation = entry[1]
		badge.text = entry[0]
		_badges.add_child(badge)


## Adds a button; one that waits for a later phase is disabled with a reason.
func add_button(text: String, disabled_reason := "") -> Button:
	var button := Button.new()
	button.text = text
	if not disabled_reason.is_empty():
		button.disabled = true
		button.tooltip_text = disabled_reason
	_buttons.add_child(button)
	return button
