extends RichTextLabel
## Running text with bold and code runs, as the manuals set it: it wraps to the width it is given and grows to fit.
const Tokens = preload("res://theme/editor_tokens.gd")


func _init() -> void:
	bbcode_enabled = true
	fit_content = true
	scroll_active = false
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_enabled = true
	add_theme_color_override("default_color", Tokens.TEXT)
	add_theme_font_size_override("normal_font_size", Tokens.TEXT_SIZE)
	add_theme_font_size_override("bold_font_size", Tokens.TEXT_SIZE)
	add_theme_font_size_override("mono_font_size", Tokens.TEXT_SIZE - 1)


func _ready() -> void:
	var strong := get_theme_font("font", "Strong")
	if strong != null: add_theme_font_override("bold_font", strong)
	var mono := get_theme_font("mono", "EditorTokens")
	if mono != null: add_theme_font_override("mono_font", mono)


## Shows `markup`, written with **bold** and `code` runs.
func show_markup(markup: String) -> void:
	text = markup_to_bbcode(markup)


static func markup_to_bbcode(markup: String) -> String:
	var plain := markup.replace("[", "[lb]")
	var bold := RegEx.create_from_string("[*][*](.+?)[*][*]")
	plain = bold.sub(plain, "[b]$1[/b]", true)
	var code := RegEx.create_from_string("`([^`]+)`")
	return code.sub(plain, "[code]$1[/code]", true)
