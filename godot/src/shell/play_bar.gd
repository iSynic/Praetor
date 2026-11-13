extends VBoxContainer
## The Play session over the pages: the message the runtime is showing, in the
## game's black window, and the controls that go on with the session.
const Tokens = preload("res://theme/editor_tokens.gd")

signal continue_requested
signal step_requested
signal restart_requested
signal stop_requested

var _window := PanelContainer.new()
var _heading := Label.new()
var _text := Label.new()
var _bar := PanelContainer.new()
var _where := Label.new()
var _continue := Button.new()
var _step := Button.new()
var _restart := Button.new()
var _stop := Button.new()


func _init() -> void:
	visible = false
	add_theme_constant_override("separation", 6)
	var style := StyleBoxFlat.new()
	style.bg_color = Color.BLACK
	style.border_color = Color.WHITE
	style.set_border_width_all(2)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	_window.add_theme_stylebox_override("panel", style)
	_window.visible = false
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	_window.add_child(inner)
	_heading.theme_type_variation = &"MonoDim"
	inner.add_child(_heading)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_color_override("font_color", Color(0.93, 0.78, 0.16))
	_text.add_theme_font_size_override("font_size", 15)
	inner.add_child(_text)
	add_child(_window)
	_bar.theme_type_variation = &"HudPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_bar.add_child(row)
	var dot := Label.new()
	dot.text = "●"
	dot.add_theme_color_override("font_color", Tokens.GOOD)
	row.add_child(dot)
	_where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_where.clip_text = true
	row.add_child(_where)
	for entry in [[_continue, "Continue", "", continue_requested], [_step, "Step", "", step_requested], [_restart, "Restart", "", restart_requested], [_stop, "Stop", "Shift F5", stop_requested]]:
		var button: Button = entry[0]
		button.text = entry[1]
		button.tooltip_text = entry[2]
		var signal_name: Signal = entry[3]
		button.pressed.connect(func(): signal_name.emit())
		row.add_child(button)
	_continue.theme_type_variation = &"PrimaryButton"
	add_child(_bar)


## Shows the session as it stands, or hides the bar when none is running.
func show_session(session: RefCounted) -> void:
	visible = session.active
	if not session.active: return
	_where.text = "Playing  %s · Map %d · %d, %d%s" % [session.title, session.map, session.position.x, session.position.y, "  · working…" if session.running else ""]
	var has_message: bool = not session.message.is_empty()
	_window.visible = has_message
	if has_message:
		_heading.text = "Message %d" % int(session.message.id)
		_text.text = str(session.message.text)
	_continue.disabled = session.running
	_step.disabled = session.running or session.queue.is_empty()
	_restart.disabled = session.running
