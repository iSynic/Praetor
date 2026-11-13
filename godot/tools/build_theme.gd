extends SceneTree
## Builds res://theme/editor_theme.tres from theme/editor_tokens.gd.
## Run: godot --headless --path godot --script res://tools/build_theme.gd
const T = preload("res://theme/editor_tokens.gd")

var theme := Theme.new()
var sans: Font
var medium: Font
var semibold: Font
var bold: Font
var mono: Font
var caption: Font


func _initialize() -> void:
	sans = system_font(T.SANS, 400)
	medium = system_font(T.SANS, 500)
	semibold = system_font(T.SANS, 600)
	bold = system_font(T.SANS, 700)
	mono = system_font(T.MONO, 400)
	caption = FontVariation.new()
	caption.base_font = semibold
	caption.spacing_glyph = 1
	theme.default_font = sans
	theme.default_font_size = T.TEXT_SIZE
	tokens()
	labels()
	buttons()
	inputs()
	lists()
	panels()
	menus_and_windows()
	progress()
	scrolling()
	var error := ResourceSaver.save(theme, "res://theme/editor_theme.tres")
	if error != OK: push_error("Theme was not saved: %d" % error)
	quit(0 if error == OK else 1)


func system_font(names: Array, weight: int) -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(names)
	font.font_weight = weight
	return font


## A flat box. `margin` is [horizontal, vertical]; `sides` limits the border to
## the named sides.
func box(fill: Color, border := Color.TRANSPARENT, radius := 0, margin := [0, 0], sides := ["left", "top", "right", "bottom"], width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.draw_center = fill.a > 0.0
	style.border_color = border
	if border.a > 0.0:
		for side in sides: style.set("border_width_" + side, width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin[0]
	style.content_margin_right = margin[0]
	style.content_margin_top = margin[1]
	style.content_margin_bottom = margin[1]
	style.anti_aliasing = radius > 0
	return style


func empty(margin := [0, 0]) -> StyleBoxEmpty:
	var style := StyleBoxEmpty.new()
	style.content_margin_left = margin[0]
	style.content_margin_right = margin[0]
	style.content_margin_top = margin[1]
	style.content_margin_bottom = margin[1]
	return style


func variation(name: String, base: String) -> void:
	theme.set_type_variation(name, base)


## The tokens themselves, for scripts that ask the theme rather than the token file.
func tokens() -> void:
	for entry in [["ink", T.INK], ["bar", T.BAR], ["panel", T.PANEL], ["panel2", T.PANEL2], ["raised", T.RAISED],
			["field", T.FIELD], ["line", T.LINE], ["line2", T.LINE2], ["text", T.TEXT], ["muted", T.MUTED], ["dim", T.DIM],
			["accent", T.ACCENT], ["accent_ink", T.ACCENT_INK], ["accent_soft", T.ACCENT_SOFT], ["warn", T.WARN],
			["err", T.ERR], ["info", T.INFO], ["good", T.GOOD], ["scrim", T.SCRIM], ["trigger", T.TRIGGER],
			["region", T.REGION], ["start", T.START], ["selected", T.SELECTED]]:
		theme.set_color(entry[0], "EditorTokens", entry[1])
	for family in T.FAMILY: theme.set_color("family_" + family, "EditorTokens", T.FAMILY[family])
	for entry in [["radius_key", T.RADIUS_KEY], ["radius_badge", T.RADIUS_BADGE], ["radius_input", T.RADIUS_INPUT],
			["radius_button", T.RADIUS_BUTTON], ["radius_card", T.RADIUS_CARD], ["radius_modal", T.RADIUS_MODAL],
			["radius_chip", T.RADIUS_CHIP], ["control_height", T.CONTROL_HEIGHT], ["chip_height", T.CHIP_HEIGHT],
			["header_height", T.HEADER_HEIGHT], ["rail_width", T.RAIL_WIDTH], ["status_height", T.STATUS_HEIGHT]]:
		theme.set_constant(entry[0], "EditorTokens", entry[1])
	for entry in [["sans", sans], ["medium", medium], ["semibold", semibold], ["bold", bold], ["mono", mono], ["caption", caption]]:
		theme.set_font(entry[0], "EditorTokens", entry[1])
	for entry in [["text", T.TEXT_SIZE], ["small", T.SMALL_SIZE], ["caption", T.CAPTION_SIZE], ["key", T.KEY_SIZE], ["heading", T.HEADING_SIZE]]:
		theme.set_font_size(entry[0], "EditorTokens", entry[1])


func label(name: String, color: Color, size: int, font: Font = null) -> void:
	variation(name, "Label")
	theme.set_color("font_color", name, color)
	theme.set_font_size("font_size", name, size)
	if font != null: theme.set_font("font", name, font)


func labels() -> void:
	theme.set_color("font_color", "Label", T.TEXT)
	theme.set_font_size("font_size", "Label", T.TEXT_SIZE)
	theme.set_constant("line_spacing", "Label", 4)
	label("Caption", T.DIM, T.CAPTION_SIZE, caption)
	label("CaptionMuted", T.MUTED, T.CAPTION_SIZE, caption)
	label("Muted", T.MUTED, T.TEXT_SIZE)
	label("Dim", T.DIM, T.SMALL_SIZE)
	label("Warn", T.WARN, T.SMALL_SIZE)
	label("Mono", T.TEXT, T.SMALL_SIZE, mono)
	label("MonoDim", T.DIM, T.CAPTION_SIZE, mono)
	label("Strong", T.TEXT, T.TEXT_SIZE, semibold)
	label("Heading", T.TEXT, T.HEADING_SIZE, bold)
	label("PageTitle", T.TEXT, 26, bold)
	label("Kbd", T.MUTED, T.KEY_SIZE, mono)
	theme.set_stylebox("normal", "Kbd", box(Color.TRANSPARENT, T.LINE2, T.RADIUS_KEY, [5, 1]))
	for entry in [["Badge", T.INFO], ["BadgeWarn", T.WARN], ["BadgeErr", T.ERR], ["BadgeGood", T.GOOD],
			["BadgeAccent", T.ACCENT], ["BadgeDim", T.DIM], ["BadgeEncounter", T.FAMILY.encounter]]:
		label(entry[0], entry[1], T.KEY_SIZE, bold)
		theme.set_stylebox("normal", entry[0], box(T.tint(entry[1], 0.13), T.tint(entry[1], 0.33), T.RADIUS_BADGE, [6, 1]))
	label("TagGood", T.GOOD, T.KEY_SIZE, mono)
	label("TagErr", T.ERR, T.SMALL_SIZE)
	label("TagWarn", T.WARN, T.KEY_SIZE, mono)
	label("MonoMuted", T.MUTED, T.SMALL_SIZE, mono)
	label("StepNumber", T.ACCENT, T.SMALL_SIZE, bold)
	theme.set_color("default_color", "RichTextLabel", T.TEXT)
	theme.set_font_size("normal_font_size", "RichTextLabel", T.TEXT_SIZE)
	theme.set_font_size("bold_font_size", "RichTextLabel", T.TEXT_SIZE)
	theme.set_font("bold_font", "RichTextLabel", semibold)
	theme.set_font("mono_font", "RichTextLabel", mono)
	theme.set_constant("line_separation", "RichTextLabel", 5)
	theme.set_color("font_color", "TooltipLabel", T.TEXT)
	theme.set_font_size("font_size", "TooltipLabel", T.SMALL_SIZE)
	theme.set_stylebox("panel", "TooltipPanel", box(T.RAISED, T.LINE2, T.RADIUS_INPUT, [8, 5]))


## One button kind: fill, border and text for the resting, hovered, held and
## unavailable states.
func button(name: String, base: String, states: Dictionary, margin: Array, radius: int, font: Font, size := T.TEXT_SIZE) -> void:
	if name != base: variation(name, base)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var look: Array = states[state]
		theme.set_stylebox(state, name, box(look[0], look[1], radius, margin))
	theme.set_stylebox("hover_pressed", name, box(states.pressed[0], states.pressed[1], radius, margin))
	theme.set_stylebox("focus", name, box(Color.TRANSPARENT, T.tint(T.ACCENT, 0.55), radius, margin))
	theme.set_color("font_color", name, states.normal[2])
	theme.set_color("font_hover_color", name, states.hover[2])
	theme.set_color("font_pressed_color", name, states.pressed[2])
	theme.set_color("font_hover_pressed_color", name, states.pressed[2])
	theme.set_color("font_focus_color", name, states.normal[2])
	theme.set_color("font_disabled_color", name, states.disabled[2])
	theme.set_color("icon_normal_color", name, states.normal[2])
	theme.set_color("icon_hover_color", name, states.hover[2])
	theme.set_color("icon_pressed_color", name, states.pressed[2])
	theme.set_color("icon_disabled_color", name, states.disabled[2])
	theme.set_font("font", name, font)
	theme.set_font_size("font_size", name, size)
	theme.set_constant("h_separation", name, 6)


func buttons() -> void:
	var none := Color.TRANSPARENT
	var off := [T.tint(T.RAISED, 0.45), T.tint(T.LINE2, 0.45), T.tint(T.TEXT, 0.4)]
	var secondary := {
		"normal": [T.RAISED, T.LINE2, T.TEXT],
		"hover": [T.LINE, T.LINE2, T.TEXT],
		"pressed": [T.PANEL2, T.tint(T.ACCENT, 0.53), T.ACCENT],
		"disabled": off,
	}
	button("Button", "Button", secondary, [12, 6], T.RADIUS_BUTTON, medium)
	button("PrimaryButton", "Button", {
		"normal": [T.ACCENT, none, T.ACCENT_INK],
		"hover": [T.ACCENT.lightened(0.12), none, T.ACCENT_INK],
		"pressed": [T.ACCENT.darkened(0.12), none, T.ACCENT_INK],
		"disabled": off,
	}, [12, 6], T.RADIUS_BUTTON, semibold)
	button("DangerButton", "Button", {
		"normal": [T.ERR, none, T.ERR_INK],
		"hover": [T.ERR.lightened(0.12), none, T.ERR_INK],
		"pressed": [T.ERR.darkened(0.12), none, T.ERR_INK],
		"disabled": off,
	}, [12, 6], T.RADIUS_BUTTON, semibold)
	button("Mark", "Button", {
		"normal": [T.ACCENT, none, T.ACCENT_INK],
		"hover": [T.ACCENT.lightened(0.12), none, T.ACCENT_INK],
		"pressed": [T.ACCENT, none, T.ACCENT_INK],
		"disabled": off,
	}, [0, 0], T.RADIUS_BUTTON, bold)
	var ghost := {
		"normal": [none, none, T.TEXT],
		"hover": [T.RAISED, none, T.TEXT],
		"pressed": [T.PANEL2, none, T.ACCENT],
		"disabled": [none, none, T.tint(T.TEXT, 0.4)],
	}
	button("GhostButton", "Button", ghost, [10, 6], T.RADIUS_BUTTON, medium)
	button("IconButton", "Button", ghost, [0, 0], T.RADIUS_BUTTON, medium)
	button("Chip", "Button", {
		"normal": [none, T.LINE2, T.MUTED],
		"hover": [T.RAISED, T.LINE2, T.TEXT],
		"pressed": [T.ACCENT_SOFT, T.tint(T.ACCENT, 0.53), T.ACCENT],
		"disabled": [none, T.tint(T.LINE2, 0.5), T.DIM],
	}, [10, 4], T.RADIUS_CHIP, medium, T.SMALL_SIZE)
	var quiet := {
		"normal": [none, none, T.MUTED],
		"hover": [T.RAISED, none, T.TEXT],
		"pressed": [T.PANEL2, none, T.TEXT],
		"disabled": [none, none, T.tint(T.MUTED, 0.45)],
	}
	button("RailButton", "Button", quiet, [0, 0], T.RADIUS_BUTTON, sans, T.CAPTION_SIZE)
	button("MenuButton", "MenuButton", quiet, [9, 6], T.RADIUS_BUTTON, sans)
	button("DockTab", "Button", {
		"normal": [none, none, T.MUTED],
		"hover": [none, none, T.TEXT],
		"pressed": [none, none, T.TEXT],
		"disabled": [none, none, T.tint(T.MUTED, 0.45)],
	}, [8, 6], 0, medium)
	button("RecordTab", "Button", {
		"normal": [none, none, T.MUTED],
		"hover": [T.PANEL, none, T.TEXT],
		"pressed": [T.PANEL2, none, T.TEXT],
		"disabled": [none, none, T.tint(T.MUTED, 0.45)],
	}, [14, 8], 0, medium)
	# A choice the author makes between whole cards, and a row of a list.
	button("ActionCard", "Button", {
		"normal": [T.PANEL2, T.LINE, T.TEXT],
		"hover": [T.RAISED, T.LINE2, T.TEXT],
		"pressed": [T.ACCENT_SOFT, T.tint(T.ACCENT, 0.7), T.TEXT],
		"disabled": [T.tint(T.PANEL2, 0.5), T.tint(T.LINE, 0.5), T.DIM],
	}, [0, 0], T.RADIUS_CARD, medium)
	theme.set_stylebox("focus", "ActionCard", box(Color.TRANSPARENT, T.tint(T.ACCENT, 0.7), T.RADIUS_CARD))
	button("ToolButton", "Button", {
		"normal": [none, none, T.TEXT],
		"hover": [T.RAISED, none, T.TEXT],
		"pressed": [T.ACCENT, none, T.ACCENT_INK],
		"disabled": [none, none, T.tint(T.TEXT, 0.35)],
	}, [7, 5], T.RADIUS_BUTTON, medium)
	theme.set_stylebox("focus", "ToolButton", empty())
	button("RowButton", "Button", {
		"normal": [none, none, T.TEXT],
		"hover": [T.RAISED, none, T.TEXT],
		"pressed": [T.tint(T.ACCENT, 0.08), T.tint(T.ACCENT, 0.5), T.TEXT],
		"disabled": [none, none, T.DIM],
	}, [0, 0], T.RADIUS_INPUT, medium)
	theme.set_stylebox("focus", "RowButton", box(Color.TRANSPARENT, T.tint(T.ACCENT, 0.4), T.RADIUS_INPUT))
	for name in ["CheckButton", "CheckBox"]:
		for state in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
			theme.set_stylebox(state, name, empty([4, 5]))
		theme.set_color("font_color", name, T.TEXT)
		theme.set_color("font_hover_color", name, T.TEXT)
		theme.set_color("font_pressed_color", name, T.TEXT)
		theme.set_color("font_hover_pressed_color", name, T.TEXT)
		theme.set_color("font_focus_color", name, T.TEXT)
		theme.set_color("font_disabled_color", name, T.DIM)
		theme.set_font_size("font_size", name, T.TEXT_SIZE)
		theme.set_constant("h_separation", name, 10)
		theme.set_constant("check_v_offset", name, 0)
	for state in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		var on: bool = state.begins_with("checked")
		var dim: bool = state.ends_with("disabled")
		var track: Color = T.ACCENT if on else T.LINE2
		var knob: Color = T.ACCENT_INK if on else T.MUTED
		if dim: track = T.tint(track, 0.4); knob = T.tint(knob, 0.5)
		var toggle: Texture2D = pill(track, knob, on)
		theme.set_icon(state, "CheckButton", toggle)
		theme.set_icon(state + "_mirrored", "CheckButton", toggle)
		var tick: Texture2D = square(T.ACCENT if on else T.FIELD, T.ACCENT if on else T.LINE2, T.ACCENT_INK, on, dim)
		theme.set_icon(state, "CheckBox", tick)
	theme.set_icon("radio_checked", "CheckBox", square(T.ACCENT, T.ACCENT, T.ACCENT_INK, true, false))
	theme.set_icon("radio_unchecked", "CheckBox", square(T.FIELD, T.LINE2, T.ACCENT_INK, false, false))


## The track and knob of a switch, drawn so the editor ships no image files.
func pill(track: Color, knob: Color, on: bool) -> ImageTexture:
	var width := 34
	var height := 18
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var centre_x: float = height / 2.0 + (width - height if on else 0.0)
	for x in range(width):
		for y in range(height):
			var inside: float = clampf(height / 2.0 - Vector2(clampf(x + 0.5, height / 2.0, width - height / 2.0), height / 2.0).distance_to(Vector2(x + 0.5, y + 0.5)), 0.0, 1.0)
			var color := Color(track.r, track.g, track.b, track.a * inside)
			var ball: float = clampf(height / 2.0 - 3.0 - Vector2(centre_x, height / 2.0).distance_to(Vector2(x + 0.5, y + 0.5)), 0.0, 1.0)
			if ball > 0.0: color = color.lerp(Color(knob.r, knob.g, knob.b, 1.0), ball)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


## A small rounded box for a check box, with a tick when `on`.
func square(fill: Color, border: Color, ink: Color, on: bool, dim: bool) -> ImageTexture:
	var side := 16
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	for x in range(side):
		for y in range(side):
			var edge: float = minf(minf(x + 0.5, side - x - 0.5), minf(y + 0.5, side - y - 0.5))
			var color := Color.TRANSPARENT
			if edge > 0.0 and _inside_round(x + 0.5, y + 0.5, side, 4.0):
				color = border if edge < 1.0 else fill
			if dim: color.a *= 0.45
			image.set_pixel(x, y, color)
	if on:
		for point in [[4, 8], [5, 9], [6, 10], [7, 9], [8, 8], [9, 7], [10, 6], [11, 5]]:
			image.set_pixel(point[0], point[1], ink)
			image.set_pixel(point[0], point[1] + 1, ink)
	return ImageTexture.create_from_image(image)


func _inside_round(x: float, y: float, side: int, radius: float) -> bool:
	var dx: float = maxf(0.0, maxf(radius - x, x - (side - radius)))
	var dy: float = maxf(0.0, maxf(radius - y, y - (side - radius)))
	return dx * dx + dy * dy <= radius * radius


func inputs() -> void:
	var rest := box(T.FIELD, T.LINE2, T.RADIUS_INPUT, [10, 6])
	var focus := box(T.FIELD, T.ACCENT, T.RADIUS_INPUT, [10, 6])
	var locked := box(T.tint(T.FIELD, 0.6), T.LINE, T.RADIUS_INPUT, [10, 6])
	for name in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", name, rest)
		theme.set_stylebox("focus", name, focus)
		theme.set_stylebox("read_only", name, locked)
		theme.set_color("font_color", name, T.TEXT)
		theme.set_color("font_placeholder_color", name, T.DIM)
		theme.set_color("font_selected_color", name, T.TEXT)
		theme.set_color("caret_color", name, T.ACCENT)
		theme.set_color("selection_color", name, T.tint(T.ACCENT, 0.3))
		theme.set_font_size("font_size", name, T.TEXT_SIZE)
	variation("LineEditError", "LineEdit")
	theme.set_stylebox("normal", "LineEditError", box(T.FIELD, T.ERR, T.RADIUS_INPUT, [10, 6]))
	theme.set_stylebox("focus", "LineEditError", box(T.FIELD, T.ERR, T.RADIUS_INPUT, [10, 6]))
	variation("LineEditMono", "LineEdit")
	theme.set_font("font", "LineEditMono", mono)
	theme.set_font_size("font_size", "LineEditMono", T.SMALL_SIZE)
	variation("LineEditMonoError", "LineEditError")
	theme.set_font("font", "LineEditMonoError", mono)
	theme.set_font_size("font_size", "LineEditMonoError", T.SMALL_SIZE)
	theme.set_color("font_uneditable_color", "LineEdit", T.MUTED)
	theme.set_color("font_readonly_color", "TextEdit", T.MUTED)
	theme.set_color("background_color", "TextEdit", Color.TRANSPARENT)
	theme.set_color("current_line_color", "TextEdit", Color.TRANSPARENT)
	theme.set_constant("line_spacing", "TextEdit", 5)
	theme.set_stylebox("normal", "OptionButton", rest)
	theme.set_stylebox("hover", "OptionButton", box(T.FIELD, T.DIM, T.RADIUS_INPUT, [10, 6]))
	theme.set_stylebox("pressed", "OptionButton", focus)
	theme.set_stylebox("hover_pressed", "OptionButton", focus)
	theme.set_stylebox("disabled", "OptionButton", locked)
	theme.set_stylebox("focus", "OptionButton", box(Color.TRANSPARENT, T.tint(T.ACCENT, 0.55), T.RADIUS_INPUT, [10, 6]))
	for item in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(item, "OptionButton", T.TEXT)
	theme.set_color("font_disabled_color", "OptionButton", T.DIM)
	theme.set_font("font", "OptionButton", sans)
	theme.set_font_size("font_size", "OptionButton", T.TEXT_SIZE)
	theme.set_constant("arrow_margin", "OptionButton", 8)


func lists() -> void:
	var chosen := box(T.ACCENT_SOFT, T.tint(T.ACCENT, 0.53), T.RADIUS_INPUT)
	var hovered := box(T.RAISED, Color.TRANSPARENT, T.RADIUS_INPUT)
	for name in ["ItemList", "Tree"]:
		theme.set_stylebox("panel", name, box(T.PANEL, T.LINE, T.RADIUS_CARD, [6, 6]))
		theme.set_stylebox("focus", name, empty())
		theme.set_stylebox("selected", name, chosen)
		theme.set_stylebox("selected_focus", name, chosen)
		theme.set_stylebox("hovered", name, hovered)
		theme.set_stylebox("hovered_selected", name, chosen)
		theme.set_stylebox("hovered_selected_focus", name, chosen)
		theme.set_stylebox("cursor", name, empty())
		theme.set_stylebox("cursor_unfocused", name, empty())
		theme.set_color("font_color", name, T.MUTED)
		theme.set_color("font_hovered_color", name, T.TEXT)
		theme.set_color("font_selected_color", name, T.TEXT)
		theme.set_color("font_hovered_selected_color", name, T.TEXT)
		theme.set_color("guide_color", name, Color.TRANSPARENT)
		theme.set_font_size("font_size", name, T.TEXT_SIZE)
		theme.set_constant("v_separation", name, 8)
		theme.set_constant("h_separation", name, 8)
	var title := box(T.PANEL, T.LINE, 0, [8, 6], ["bottom"])
	for state in ["title_button_normal", "title_button_hover", "title_button_pressed"]:
		theme.set_stylebox(state, "Tree", title)
	theme.set_color("title_button_color", "Tree", T.DIM)
	theme.set_font("title_button_font", "Tree", caption)
	theme.set_font_size("title_button_font_size", "Tree", T.CAPTION_SIZE)
	theme.set_color("relationship_line_color", "Tree", T.LINE)
	theme.set_color("children_hl_line_color", "Tree", T.LINE)
	theme.set_color("parent_hl_line_color", "Tree", T.LINE)


func panel(name: String, style: StyleBox) -> void:
	variation(name, "PanelContainer")
	theme.set_stylebox("panel", name, style)


func panels() -> void:
	theme.set_stylebox("panel", "Panel", box(T.INK))
	theme.set_stylebox("panel", "PanelContainer", box(T.PANEL, T.LINE, T.RADIUS_CARD, [14, 12]))
	panel("Card", box(T.PANEL2, T.LINE, T.RADIUS_CARD, [14, 12]))
	panel("Tile", box(T.FIELD, Color.TRANSPARENT, T.RADIUS_INPUT, [8, 6]))
	panel("InputPanel", box(T.FIELD, T.LINE2, T.RADIUS_BUTTON, [10, 0]))
	panel("OptionStrip", box(T.tint(T.PANEL, 0.7), T.LINE, T.RADIUS_BUTTON, [10, 4]))
	panel("HudPanel", box(T.tint(T.INK, 0.86), T.LINE2, 8, [10, 7]))
	var drawer := box(T.PANEL, T.LINE2, 0, [14, 12], ["left"])
	drawer.shadow_color = T.SHADOW
	drawer.shadow_size = 24
	panel("HelperPanel", drawer)
	panel("Detail", box(T.tint(T.FIELD, 0.7), T.LINE, T.RADIUS_BUTTON, [14, 10]))
	panel("Inset", box(T.PANEL2, T.LINE, T.RADIUS_CARD, [14, 12]))
	for entry in [["CircleWarn", T.WARN], ["CircleErr", T.ERR], ["CircleInfo", T.INFO], ["CircleGood", T.GOOD]]:
		panel(entry[0], box(T.tint(entry[1], 0.14), T.tint(entry[1], 0.45), 17, [0, 0]))
	panel("ActionTile", box(T.ACCENT_SOFT, T.tint(T.ACCENT, 0.35), T.RADIUS_BUTTON, [0, 0]))
	panel("ActionTileOn", box(T.ACCENT, Color.TRANSPARENT, T.RADIUS_BUTTON, [0, 0]))
	panel("HeaderBar", box(T.BAR, T.LINE, 0, [14, 0], ["bottom"]))
	panel("Rail", box(T.BAR, T.LINE, 0, [0, 6], ["right"]))
	panel("TabStrip", box(T.BAR, T.LINE, 0, [0, 0], ["bottom"]))
	panel("ApplyBar", box(T.BAR, T.LINE, 0, [16, 8], ["top"]))
	panel("Dock", box(T.PANEL, T.LINE, 0, [0, 0], ["top"]))
	panel("DockHead", box(T.PANEL, T.LINE, 0, [14, 4], ["bottom"]))
	panel("StatusBar", box(T.BAR, T.LINE, 0, [14, 0], ["top"]))
	var modal := box(T.PANEL, T.LINE2, T.RADIUS_MODAL)
	modal.shadow_color = T.SHADOW
	modal.shadow_size = 48
	modal.shadow_offset = Vector2(0, 18)
	panel("ModalPanel", modal)
	var line := StyleBoxLine.new()
	line.color = T.LINE
	theme.set_stylebox("separator", "HSeparator", line)
	theme.set_constant("separation", "HSeparator", 1)
	var upright := StyleBoxLine.new()
	upright.color = T.LINE
	upright.vertical = true
	theme.set_stylebox("separator", "VSeparator", upright)
	theme.set_constant("separation", "VSeparator", 1)
	theme.set_constant("separation", "HSplitContainer", 10)
	theme.set_constant("separation", "VSplitContainer", 10)


func progress() -> void:
	theme.set_stylebox("background", "ProgressBar", box(T.LINE, Color.TRANSPARENT, 3))
	theme.set_stylebox("fill", "ProgressBar", box(T.ACCENT, Color.TRANSPARENT, 3))


func menus_and_windows() -> void:
	theme.set_stylebox("panel", "PopupMenu", box(T.PANEL, T.LINE2, T.RADIUS_CARD, [6, 6]))
	theme.set_stylebox("hover", "PopupMenu", box(T.RAISED, Color.TRANSPARENT, T.RADIUS_INPUT))
	var rule := StyleBoxLine.new()
	rule.color = T.LINE
	theme.set_stylebox("separator", "PopupMenu", rule)
	theme.set_color("font_color", "PopupMenu", T.TEXT)
	theme.set_color("font_hover_color", "PopupMenu", T.TEXT)
	theme.set_color("font_disabled_color", "PopupMenu", T.DIM)
	theme.set_color("font_accelerator_color", "PopupMenu", T.DIM)
	theme.set_color("font_separator_color", "PopupMenu", T.DIM)
	theme.set_font_size("font_size", "PopupMenu", T.TEXT_SIZE)
	theme.set_constant("v_separation", "PopupMenu", 10)
	theme.set_constant("h_separation", "PopupMenu", 8)
	theme.set_constant("item_start_padding", "PopupMenu", 12)
	theme.set_constant("item_end_padding", "PopupMenu", 12)
	var frame := box(T.PANEL, T.LINE2, T.RADIUS_MODAL)
	frame.expand_margin_top = 36
	frame.shadow_color = T.SHADOW
	frame.shadow_size = 24
	frame.shadow_offset = Vector2(0, 10)
	theme.set_stylebox("embedded_border", "Window", frame)
	theme.set_stylebox("embedded_unfocused_border", "Window", frame)
	theme.set_color("title_color", "Window", T.TEXT)
	theme.set_font("title_font", "Window", semibold)
	theme.set_font_size("title_font_size", "Window", T.TEXT_SIZE)
	theme.set_constant("title_height", "Window", 36)
	theme.set_constant("close_h_offset", "Window", 24)
	theme.set_constant("close_v_offset", "Window", 24)
	theme.set_stylebox("panel", "AcceptDialog", box(T.PANEL, Color.TRANSPARENT, 0, [16, 12]))
	theme.set_constant("buttons_separation", "AcceptDialog", 8)


func scrolling() -> void:
	for name in ["VScrollBar", "HScrollBar"]:
		var margin := [4, 0] if name == "VScrollBar" else [0, 4]
		theme.set_stylebox("scroll", name, empty(margin))
		theme.set_stylebox("scroll_focus", name, empty(margin))
		theme.set_stylebox("grabber", name, box(T.LINE2, Color.TRANSPARENT, 4))
		theme.set_stylebox("grabber_highlight", name, box(T.DIM, Color.TRANSPARENT, 4))
		theme.set_stylebox("grabber_pressed", name, box(T.MUTED, Color.TRANSPARENT, 4))
