extends Control
## A modal panel over a scrim. It covers its parent, takes all input while
## open, and closes on Esc, the close button or a click on the scrim.
signal closed
const IconButton = preload("res://src/widgets/icon_button.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

@export var title := "":
	set(value): title = value; _title.text = value
@export var subtitle := "":
	set(value): subtitle = value; _subtitle.text = value
@export var panel_size := Vector2(720, 480):
	set(value): panel_size = value; _panel.custom_minimum_size = value
@export var dismissible := true

## Content goes here.
var body := MarginContainer.new()
## Controls at the left of the footer, such as a note.
var footer_left := HBoxContainer.new()
var _buttons := HBoxContainer.new()
var _panel := PanelContainer.new()
var _title := Label.new()
var _subtitle := Label.new()
var _scroll := ScrollContainer.new()


func _init() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	var scrim := ColorRect.new()
	scrim.color = Tokens.SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(func(event):
		if dismissible and event is InputEventMouseButton and event.pressed: close())
	add_child(scrim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_panel.theme_type_variation = &"ModalPanel"
	_panel.custom_minimum_size = panel_size
	centre.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	_panel.add_child(column)
	var bar := HBoxContainer.new()
	bar.custom_minimum_size.y = 52
	bar.add_theme_constant_override("separation", 10)
	column.add_child(_inset(bar, 20, 0))
	_title.theme_type_variation = &"Heading"
	bar.add_child(_title)
	_subtitle.theme_type_variation = &"Mono"
	_subtitle.add_theme_color_override("font_color", Tokens.DIM)
	_subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_subtitle)
	var key := Label.new()
	key.text = "Esc"
	key.theme_type_variation = &"Kbd"
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(key)
	var close_button := IconButton.new()
	close_button.glyph = "close"
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close)
	bar.add_child(close_button)
	column.add_child(HSeparator.new())
	# A body taller than the window scrolls; the title and footer stay put.
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]: body.add_theme_constant_override("margin_" + side, 20)
	_scroll.add_child(body)
	body.minimum_size_changed.connect(func(): _fit.call_deferred())
	column.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.custom_minimum_size.y = 58
	footer.add_theme_constant_override("separation", 8)
	column.add_child(_inset(footer, 20, 0))
	footer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_left)
	_buttons.add_theme_constant_override("separation", 8)
	_buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(_buttons)


func _inset(control: Control, horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
	margin.add_child(control)
	return margin


## Adds a footer button. `kind` is "primary", "secondary" or "danger".
func add_button(text: String, kind := "secondary") -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = {"primary": &"PrimaryButton", "danger": &"DangerButton"}.get(kind, &"")
	_buttons.add_child(button)
	return button


## Adds a button the caller built to the footer's right.
func add_footer_button(button: Button) -> void:
	_buttons.add_child(button)


func open() -> void:
	visible = true
	move_to_front()
	grab_focus()
	_fit()
	if not get_viewport().size_changed.is_connected(_fit): get_viewport().size_changed.connect(_fit)


## Fits the panel again after its body changed.
func refit() -> void:
	_fit.call_deferred()


## The panel is as tall as its body, but never taller than the window.
func _fit() -> void:
	if not visible: return
	var chrome := 118.0
	_scroll.custom_minimum_size.y = minf(body.get_combined_minimum_size().y, maxf(120.0, size.y - 32.0 - chrome))


## Where the panel is on screen, for checks that it stays inside the window.
func panel_rect() -> Rect2:
	return _panel.get_global_rect()


func close() -> void:
	if not visible: return
	visible = false
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and dismissible and event.is_pressed() and event is InputEventKey and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
