extends VBoxContainer
## Preservation notices, one row each: a dot and the sentence. The notice that
## says runtime evidence is separate is drawn as a warning.
const Glyph = preload("res://src/widgets/glyph.gd")
const Tokens = preload("res://theme/editor_tokens.gd")


func _init() -> void:
	add_theme_constant_override("separation", 6)


func show_notices(notices: Array) -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	for notice in notices:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var dot := Glyph.new()
		dot.glyph = "dot"
		dot.extent = 10.0
		dot.color = Tokens.WARN if str(notice).begins_with("Runtime evidence") else Tokens.INFO
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		dot.custom_minimum_size.y = 18
		row.add_child(dot)
		var label := Label.new()
		label.text = str(notice)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		add_child(row)
