extends HBoxContainer
## A folder path with the state of the folder it names, and a button that
## browses for another. For a destination, the folder must not exist yet.
signal text_changed(text: String)
signal browse_requested
const Tokens = preload("res://theme/editor_tokens.gd")

## What the field names: "destination" is a new folder under an existing
## parent; "existing" is a folder that must be there.
@export var kind := "destination"
@export var browse_text := "Browse…":
	set(value): browse_text = value; _browse.text = value
@export var placeholder := "":
	set(value): placeholder = value; edit.placeholder_text = value

var edit := LineEdit.new()
var _tag := Label.new()
var _browse := Button.new()
## "", "new", "exists", "missing", "parent" or "found".
var state := ""


func _init() -> void:
	add_theme_constant_override("separation", 8)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.theme_type_variation = &"LineEditMono"
	edit.text_changed.connect(func(text): refresh(); text_changed.emit(text))
	add_child(edit)
	_tag.theme_type_variation = &"TagGood"
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tag.offset_right = -10
	_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	edit.add_child(_tag)
	_browse.text = browse_text
	_browse.pressed.connect(func(): browse_requested.emit())
	add_child(_browse)
	for name in ["normal", "focus"]:
		edit.add_theme_stylebox_override(name, _box(Tokens.LINE2 if name == "normal" else Tokens.ACCENT))


func _box(border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Tokens.FIELD
	style.border_color = border
	for side in ["left", "top", "right", "bottom"]: style.set("border_width_" + side, 1)
	style.set_corner_radius_all(Tokens.RADIUS_INPUT)
	style.content_margin_left = 10
	style.content_margin_right = 92
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.anti_aliasing = true
	return style


var text: String:
	get: return edit.text
	set(value): edit.text = shown(value); refresh()


## A path the way Windows writes it; elsewhere it is left alone.
static func shown(path: String) -> String:
	return path.replace("/", "\\") if OS.get_name() == "Windows" else path


## Sets the text without telling the owner.
func show_path(value: String) -> void:
	edit.text = shown(value)
	refresh()


## Looks at the folder the text names and shows what is wrong with it.
func refresh() -> void:
	var path := edit.text.strip_edges()
	state = ""
	if not path.is_empty():
		if kind == "destination":
			if DirAccess.dir_exists_absolute(path) or FileAccess.file_exists(path): state = "exists"
			elif not DirAccess.dir_exists_absolute(path.get_base_dir()): state = "parent"
			else: state = "new"
		else:
			state = "found" if DirAccess.dir_exists_absolute(path) else "missing"
	_tag.text = {"new": "new folder", "found": "found", "exists": "already exists", "parent": "no parent folder", "missing": "not found"}.get(state, "")
	_tag.theme_type_variation = &"TagGood" if state in ["new", "found"] else &"TagWarn"
	var bad: bool = state in ["exists", "parent", "missing"]
	edit.add_theme_stylebox_override("normal", _box(Tokens.ERR if bad else Tokens.LINE2))
	edit.add_theme_stylebox_override("focus", _box(Tokens.ERR if bad else Tokens.ACCENT))


## Shows the folder as it was written: not editable, with `tag` at its right.
func lock(tag: String) -> void:
	edit.editable = false
	_browse.visible = false
	_tag.text = tag
	_tag.theme_type_variation = &"TagGood"
	edit.add_theme_stylebox_override("normal", _box(Tokens.LINE2))
	edit.add_theme_stylebox_override("read_only", _box(Tokens.LINE2))


func unlock() -> void:
	edit.editable = true
	_browse.visible = true
	refresh()


## The sentence that says why the path cannot be used, or "".
func problem() -> String:
	return {"exists": "destination already exists; choose a new directory", "parent": "output parent is not a directory", "missing": "folder not found"}.get(state, "")
