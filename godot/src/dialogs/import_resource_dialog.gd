extends "res://src/widgets/modal_overlay.gd"
## Import a file as a picture, an icon or a sound of the scenario. The file is converted by the adapter and shown
## as the game would hold it before anything is kept; Import makes the resource an unapplied edit.
signal imported(kind: String, id: int)
const KbdButton = preload("res://src/widgets/kbd_button.gd")

const KINDS := [["icon", "Icon"], ["picture", "Picture"], ["sound", "Sound"]]
const RATES := [[0, "Keep"], [22050, "22,050"], [11025, "11,025"], [8000, "8,000"]]

var shell: Control
var kind := "icon"
var _path := ""
var _prepared: Dictionary = {}
var _serial := 0
var _fit_mode := "inside"
var _kind_chips: Dictionary = {}
var _file := LineEdit.new()
var _number := SpinBox.new()
var _availability := Label.new()
var _options := VBoxContainer.new()
var _fit_row := HBoxContainer.new()
var _size_row := HBoxContainer.new()
var _size := SpinBox.new()
var _dither := CheckBox.new()
var _rate_row := HBoxContainer.new()
var _rate := OptionButton.new()
var _before := TextureRect.new()
var _after := TextureRect.new()
var _before_label := Label.new()
var _after_label := Label.new()
var _play := Button.new()
var _notes := VBoxContainer.new()
var _import: KbdButton
var _chooser := FileDialog.new()
var _source_png := ""
var _preview_wav := ""


func _init() -> void:
	super()
	title = "Import a file"
	panel_size = Vector2(660, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	body.add_child(column)
	var kinds := HBoxContainer.new()
	kinds.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for entry in KINDS:
		var chip := Button.new()
		chip.theme_type_variation = &"Chip"
		chip.toggle_mode = true
		chip.button_group = group
		chip.text = entry[1]
		chip.set_pressed_no_signal(entry[0] == kind)
		chip.pressed.connect(func(): _set_kind(entry[0]))
		kinds.add_child(chip)
		_kind_chips[entry[0]] = chip
	column.add_child(kinds)
	var file_line := _line("File")
	_file.editable = false
	_file.placeholder_text = "Choose a PNG, JPEG, WebP or BMP file"
	_file.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_line.add_child(_file)
	var choose := Button.new()
	choose.text = "Choose…"
	choose.pressed.connect(func(): _chooser.popup_centered_ratio(0.6))
	file_line.add_child(choose)
	column.add_child(file_line)
	var number_line := _line("Becomes number")
	_number.min_value = -32768
	_number.max_value = 32767
	_number.custom_minimum_size.x = 110
	_number.value_changed.connect(func(_value): _convert())
	number_line.add_child(_number)
	_availability.theme_type_variation = &"Dim"
	_availability.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_availability.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	number_line.add_child(_availability)
	column.add_child(number_line)
	_options.add_theme_constant_override("separation", 10)
	column.add_child(_options)
	var fit_label := _line_label("Fit")
	_fit_row.add_theme_constant_override("separation", 8)
	_fit_row.add_child(fit_label)
	var fit_group := ButtonGroup.new()
	for entry in [["inside", "Fit inside"], ["fill", "Fill and crop"], ["stretch", "Stretch"]]:
		var chip := Button.new()
		chip.theme_type_variation = &"Chip"
		chip.toggle_mode = true
		chip.button_group = fit_group
		chip.text = entry[1]
		chip.set_pressed_no_signal(entry[0] == _fit_mode)
		chip.pressed.connect(func(): _fit_mode = entry[0]; _convert())
		_fit_row.add_child(chip)
	_options.add_child(_fit_row)
	_size_row.add_theme_constant_override("separation", 8)
	_size_row.add_child(_line_label("Size"))
	_size.min_value = 8
	_size.max_value = 256
	_size.value = 32
	_size.suffix = "px"
	_size.value_changed.connect(func(_value): _convert())
	_size_row.add_child(_size)
	_dither.text = "Dither the colours"
	_dither.toggled.connect(func(_on): _convert())
	_size_row.add_child(_dither)
	_options.add_child(_size_row)
	_rate_row.add_theme_constant_override("separation", 8)
	_rate_row.add_child(_line_label("Rate"))
	for entry in RATES: _rate.add_item(entry[1], int(entry[0]))
	_rate.item_selected.connect(func(_index): _convert())
	_rate_row.add_child(_rate)
	var rate_note := Label.new()
	rate_note.theme_type_variation = &"Dim"
	rate_note.text = "samples a second"
	_rate_row.add_child(rate_note)
	_options.add_child(_rate_row)
	var compare := PanelContainer.new()
	compare.theme_type_variation = &"Detail"
	var pair := HBoxContainer.new()
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	pair.add_theme_constant_override("separation", 24)
	compare.add_child(pair)
	pair.add_child(_picture_box(_before, _before_label))
	var arrow := Label.new()
	arrow.text = "→"
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pair.add_child(arrow)
	pair.add_child(_picture_box(_after, _after_label))
	column.add_child(compare)
	_play.text = "▶ Play the result"
	_play.visible = false
	_play.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_play.pressed.connect(func(): _after_label.text = await shell.references.play_file(_preview_wav))
	column.add_child(_play)
	_notes.add_theme_constant_override("separation", 4)
	column.add_child(_notes)
	add_button("Cancel").pressed.connect(close)
	_import = KbdButton.new()
	_import.theme_type_variation = &"PrimaryButton"
	_import.text = "Import"
	_import.hint = "Enter"
	_import.disabled = true
	_import.pressed.connect(_commit)
	add_footer_button(_import)
	var note := Label.new()
	note.theme_type_variation = &"Dim"
	note.text = "Nothing is written until you apply the edit."
	footer_left.add_child(note)
	_chooser.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_chooser.access = FileDialog.ACCESS_FILESYSTEM
	_chooser.use_native_dialog = true
	_chooser.file_selected.connect(_file_chosen)
	add_child(_chooser)


func _line(label: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.add_child(_line_label(label))
	return line


func _line_label(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"Dim"
	label.text = text
	label.custom_minimum_size.x = 120
	return label


func _picture_box(picture: TextureRect, caption: Label) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	picture.custom_minimum_size = Vector2(128, 128)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(picture)
	caption.theme_type_variation = &"Dim"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.custom_minimum_size.x = 160
	box.add_child(caption)
	return box


func setup(owner_shell: Control) -> void:
	shell = owner_shell


## Opens for a kind, suggesting the first number after the scenario's own of that kind.
func show_for(import_kind: String, suggested := 0) -> void:
	_path = ""
	_prepared = {}
	_file.text = ""
	_before.texture = null
	_after.texture = null
	_before_label.text = ""
	_after_label.text = ""
	_import.disabled = true
	_number.set_value_no_signal(suggested)
	_set_kind(import_kind, false)
	_show_notes([])
	_availability.text = ""
	open()


func _set_kind(next: String, convert := true) -> void:
	kind = next
	_kind_chips[kind].set_pressed_no_signal(true)
	title = "Import %s" % {"icon": "an icon", "picture": "a picture", "sound": "a sound"}[kind]
	_fit_row.visible = kind != "sound"
	_size_row.visible = kind == "icon"
	_dither.visible = kind != "sound"
	_dither.set_pressed_no_signal(kind == "picture")
	_rate_row.visible = kind == "sound"
	_chooser.filters = PackedStringArray(["*.wav ; WAV sound"]) if kind == "sound" else PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; Images"])
	_file.placeholder_text = "Choose a WAV file" if kind == "sound" else "Choose a PNG, JPEG, WebP or BMP file"
	_play.visible = false
	if convert and not _path.is_empty(): _path = ""; _file.text = ""; _prepared = {}; _import.disabled = true


func _file_chosen(path: String) -> void:
	_file.text = path
	_before.texture = null
	if kind == "sound":
		_path = path
		_before_label.text = path.get_file()
	else:
		var image := Image.load_from_file(path)
		if image == null or image.is_empty():
			_show_notes([["The file could not be read as an image.", true]])
			return
		_before.texture = ImageTexture.create_from_image(image)
		_before_label.text = "Your file · %d × %d" % [image.get_width(), image.get_height()]
		if path.get_extension().to_lower() == "png":
			_path = path
		else:
			var folder := ProjectSettings.globalize_path("user://import")
			DirAccess.make_dir_recursive_absolute(folder)
			_path = folder.path_join("source-%d.png" % Time.get_ticks_msec())
			image.save_png(_path)
	_convert()


## Converts the file with the options in hand and shows the result; a later request wins over an earlier one.
func _convert() -> void:
	if _path.is_empty(): return
	_serial += 1
	var serial := _serial
	_import.disabled = true
	_after_label.text = "Converting…"
	var options := {"fit": _fit_mode, "size": int(_size.value), "dither": _dither.button_pressed}
	if kind == "sound" and _rate.get_selected_id() > 0: options["rate"] = _rate.get_selected_id()
	var response: Dictionary = await shell.request_backend({"op": "import_prepare", "kind": kind, "path": _path, "id": int(_number.value), "options": options, "installation": shell.folder})
	if serial != _serial: return
	if not response.get("ok", false):
		_prepared = {}
		_after.texture = null
		_after_label.text = ""
		_show_notes([[shell._error(response), true]])
		return
	_prepared = response.result
	_show_result()


func _show_result() -> void:
	var notes: Array = []
	for warning in _prepared.get("warnings", []): notes.append([str(warning), false])
	if kind == "sound":
		_after.texture = null
		_preview_wav = str(_prepared.preview).replace("\\\\?\\", "")
		_play.visible = true
		_after_label.text = "%.1f s at %d samples a second" % [float(_prepared.seconds), int(_prepared.rate)]
	else:
		var image := Image.load_from_file(str(_prepared.preview).replace("\\\\?\\", ""))
		if image != null: _after.texture = ImageTexture.create_from_image(image)
		_after_label.text = "In the game · %d × %d, %d colours" % [int(_prepared.width), int(_prepared.height), int(_prepared.colours)]
	var id := int(_number.value)
	if shell.drafts.has(_key()):
		_availability.text = "You have an unapplied import with this number; this one replaces it."
	elif bool(_prepared.replaces):
		_availability.text = "The scenario already holds %s %d; importing replaces it." % [kind, id]
	elif bool(_prepared.in_game):
		_availability.text = "The game holds a %s %d. The scenario's is used wherever the game looks it up after opening the scenario; one the game loads at start-up, such as the party marker (icon 192), stays the game's." % [kind, id]
	else:
		_availability.text = "Free. The scenario holds no %s %d." % [kind, id]
	_show_notes(notes)
	_import.disabled = false


func _show_notes(notes: Array) -> void:
	for child in _notes.get_children(): _notes.remove_child(child); child.queue_free()
	for note in notes:
		var label := Label.new()
		label.theme_type_variation = &"Warn" if not bool(note[1]) else &"Err"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = str(note[0])
		_notes.add_child(label)


func _key() -> String:
	return "resource_change:%s:%d" % [str(_prepared.get("resource_type", "")), int(_number.value)]


func _commit() -> void:
	if _prepared.is_empty(): return
	var id := int(_number.value)
	shell.drafts[_key()] = {"kind": "resource_change", "resource_type": str(_prepared.resource_type), "id": id, "data": str(_prepared.data)}
	shell._invalidate_receipt()
	shell._update_buttons()
	shell.status("Imported %s %d · Apply edits" % [kind, id])
	close()
	imported.emit(kind, id)


func _unhandled_key_input(event: InputEvent) -> void:
	super(event)
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not _import.disabled:
		_commit()
		get_viewport().set_input_as_handled()
