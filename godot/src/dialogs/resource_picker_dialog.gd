extends "res://src/widgets/modal_overlay.gd"
## Choose an icon, a picture or a sound for a field: the resource browser in a dialog. Choosing changes only the
## field's number.
signal resource_chosen(kind: String, id: int)
const Browser = preload("res://src/widgets/resource_browser.gd")
const KbdButton = preload("res://src/widgets/kbd_button.gd")

var shell: Control
var browser := Browser.new()
var _use: KbdButton
var _on_chosen := Callable()


func _init() -> void:
	super()
	panel_size = Vector2(900, 560)
	browser.custom_minimum_size = Vector2(860, 440)
	body.add_child(browser)
	browser.selected.connect(func(_kind, _id): _show_use())
	browser.activated.connect(func(_kind, id): _commit(id))
	add_button("Cancel").pressed.connect(close)
	_use = KbdButton.new()
	_use.theme_type_variation = &"PrimaryButton"
	_use.hint = "Enter"
	_use.pressed.connect(func(): _commit(browser.selected_id))
	add_footer_button(_use)


func setup(owner_shell: Control) -> void:
	shell = owner_shell
	browser.setup(owner_shell)


## Opens on the resource of `current`, for the field described by `where`.
func show_for(kind: String, current: int, where: String, on_chosen := Callable()) -> void:
	title = "Choose %s" % {"icon": "an icon", "picture": "a picture", "sound": "a sound"}[kind]
	subtitle = where
	_on_chosen = on_chosen
	open()
	await browser.open(kind, current)
	_show_use()


func _show_use() -> void:
	_use.text = "Use %s %d" % [browser.kind, browser.selected_id] if browser.selected_id != browser.NONE else "Use"
	_use.disabled = browser.selected_id == browser.NONE


func _commit(id: int) -> void:
	if id == browser.NONE: return
	close()
	resource_chosen.emit(browser.kind, id)
	if _on_chosen.is_valid(): _on_chosen.call(id)


func _unhandled_key_input(event: InputEvent) -> void:
	super(event)
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_commit(browser.selected_id)
		get_viewport().set_input_as_handled()
