extends RefCounted
## What the numbers in a record stand for: the names the game gives conditions, special attacks, races, castes,
## monster kinds, item classes, calibers and spells, the names and icons of items and monsters, and the icons
## themselves as textures. A field that holds one of these numbers shows its icon and its name beside it.
const Tokens = preload("res://theme/editor_tokens.gd")

## The kinds of reference a field can hold.
const NAMED := ["sound", "condition", "special_attack", "race", "caste", "monster_kind", "item_class", "caliber", "spell"]
const LISTS := {"condition": "conditions", "special_attack": "special_attacks", "race": "races", "caste": "castes",
	"monster_kind": "monster_kinds", "item_class": "item_classes", "caliber": "calibers"}

var shell: Control
var names: Dictionary = {}
## Monster id -> {name, icon}.
var monsters: Dictionary = {}
var _key := ""
var _monsters_key := ""
var _icons: Dictionary = {}
var _missing: Dictionary = {}
var _sounds: Dictionary = {}
var _pictures: Dictionary = {}
var _player: AudioStreamPlayer
var _revision := -1


func _init(owner_shell: Control) -> void:
	shell = owner_shell


## Reads the game's name lists once for the installation in use.
func ensure() -> void:
	if shell.summary.is_empty(): return
	var key := str(shell.folder)
	if key == _key: return
	var response: Dictionary = await shell.request_when_free({"op": "names", "installation": shell.folder})
	if not response.get("ok", false): return
	names = response.result
	_key = key
	_icons.clear()
	_missing.clear()
	_sounds.clear()
	_pictures.clear()


## Reads the monsters' names and icons again whenever the records change.
func ensure_monsters() -> void:
	if shell.summary.is_empty(): return
	var key := "%s:%d" % [str(shell.summary.get("path", "")), shell.bridge.revision]
	if key == _monsters_key: return
	_monsters_key = key
	monsters.clear()
	var start := 0
	while true:
		var response: Dictionary = await shell.request_when_free({"op": "combat_catalogue", "monsters": true, "offset": start, "query": ""})
		if not response.get("ok", false): break
		for row in response.result.rows: monsters[int(row.id)] = {"name": str(row.name), "icon": int(row.icon)}
		start += 128
		if start >= int(response.result.total): break


## The name the game gives `value` as a reference of `kind`, or "" when there is none.
func label(kind: String, value: int) -> String:
	match kind:
		"item": return shell.item_name(value)
		"monster": return str(monsters.get(value, {}).get("name", ""))
		"spell": return str(names.get("spells", {}).get(str(value), ""))
	var list: Array = names.get(LISTS.get(kind, ""), [])
	return str(list[value]) if value >= 0 and value < list.size() else ""


## The cicn that pictures `value` as a reference of `kind`, or 0 when it has none.
func icon_id(kind: String, value: int) -> int:
	match kind:
		"icon": return value
		"item": return int(shell.item_icons[value]) if value >= 0 and value < shell.item_icons.size() and shell.item_icons[value] != null else 0
		"monster": return int(monsters.get(value, {}).get("icon", 0))
	return 0


## Forgets what was read when the records changed, since an edit may have added or removed a resource.
func _sync() -> void:
	if shell.bridge.revision == _revision: return
	_revision = shell.bridge.revision
	_icons.clear()
	_missing.clear()
	_sounds.clear()
	_pictures.clear()


## Reads the icons with these numbers that are not in hand; those no resource file holds are remembered.
func fetch(ids: Array) -> void:
	_sync()
	var wanted: Array = []
	for id in ids:
		var number := int(id)
		if number != 0 and not _icons.has(number) and not _missing.has(number) and not wanted.has(number): wanted.append(number)
	for start in range(0, wanted.size(), 200):
		var chunk := wanted.slice(start, start + 200)
		var response: Dictionary = await shell.request_when_free({"op": "icons", "ids": chunk, "installation": shell.folder})
		if not response.get("ok", false): return
		for id in chunk:
			var path: Variant = response.result.icons.get(str(id))
			var image: Image = Image.load_from_file(str(path).replace("\\\\?\\", "")) if path != null else null
			if image != null: _icons[id] = ImageTexture.create_from_image(image)
			else: _missing[id] = true


## What the sound with this number is: {"stream": AudioStreamWAV, "seconds": float}, or {"note": why there is none}.
func sound(id: int) -> Dictionary:
	_sync()
	if _sounds.has(id): return _sounds[id]
	var response: Dictionary = await shell.request_backend({"op": "sound", "id": id, "installation": shell.folder})
	var found := {"note": "no sound resource has this number"}
	if response.get("ok", false):
		var result: Dictionary = response.result
		if result.get("status") == "available":
			var stream := _stream_of(str(result.wav).replace("\\\\?\\", ""))
			found = {"stream": stream, "seconds": float(result.seconds)} if stream != null else {"note": "the sound could not be read"}
		elif result.get("status") == "unconverted":
			found = {"note": "this sound is stored compressed and cannot be played here"}
	_sounds[id] = found
	return found


## Plays the sound and reports how long it is or why it cannot be heard.
func play_sound(id: int) -> String:
	var found := await sound(id)
	if not found.has("stream"): return str(found.note)
	_play_stream(found.stream)
	return "%.1f s" % float(found.seconds)


## Plays a WAV file made by the adapter and reports how long it is.
func play_file(path: String) -> String:
	var stream := _stream_of(path)
	if stream == null: return "the sound could not be read"
	_play_stream(stream)
	return "%.1f s" % stream.get_length()


func _play_stream(stream: AudioStream) -> void:
	if _player == null:
		_player = AudioStreamPlayer.new()
		shell.add_child(_player)
	_player.stream = stream
	_player.play()


## A WAV file of 8-bit unsigned or 16-bit signed samples, as the stream Godot plays.
func _stream_of(path: String) -> AudioStreamWAV:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 45: return null
	var stream := AudioStreamWAV.new()
	var bits := bytes.decode_u16(34)
	stream.stereo = bytes.decode_u16(22) == 2
	stream.mix_rate = bytes.decode_u32(24)
	var data := bytes.slice(44)
	if bits == 8:
		for index in range(data.size()): data[index] = (data[index] + 128) & 255
		stream.format = AudioStreamWAV.FORMAT_8_BITS
	else:
		stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.data = data
	return stream


## The picture with this number, or null when no resource file holds it or it cannot be read.
func picture(id: int) -> Texture2D:
	_sync()
	if _pictures.has(id): return _pictures[id]
	var response: Dictionary = await shell.request_backend({"op": "picture", "id": id, "installation": shell.folder})
	var texture: Texture2D = null
	if response.get("ok", false) and response.result.get("status") == "available":
		var image: Image = Image.load_from_file(str(response.result.png).replace("\\\\?\\", ""))
		if image != null: texture = ImageTexture.create_from_image(image)
	_pictures[id] = texture
	return texture


## The eight frames of animation `number` (icons 12000 + 8 x number and the seven after it); a frame no resource
## file holds is null.
func animation_frames(number: int) -> Array:
	var first := 12000 + 8 * number
	var ids: Array = []
	for frame in range(8): ids.append(first + frame)
	await fetch(ids)
	return ids.map(func(id): return icon(id))


## The icon with this number, or null when it has not been read or no resource file holds it.
func icon(id: int) -> Texture2D:
	return _icons.get(id)


## Puts the icon and the name of what a number field holds after the field, and keeps them in step with it.
func attach(line: HBoxContainer, spin: SpinBox, kind: String, expand := true) -> void:
	var badge := TextureRect.new()
	badge.custom_minimum_size = Vector2(32, 32)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var name := Label.new()
	name.theme_type_variation = &"Muted"
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL if expand else Control.SIZE_SHRINK_BEGIN
	name.clip_text = expand
	var show := func(value: int) -> void:
		name.text = label(kind, value) if kind not in ["icon", "sound"] else ""
		var id := icon_id(kind, value)
		badge.texture = icon(id)
		badge.visible = kind in ["icon", "item", "monster"]
		if id != 0 and badge.texture == null and not _missing.has(id):
			await fetch([id])
			if is_instance_valid(badge) and is_instance_valid(spin) and int(spin.value) == value: badge.texture = icon(id)
	spin.value_changed.connect(func(value): show.call(int(value)))
	line.add_child(badge)
	if kind in ["icon", "sound"]:
		var choose := Button.new()
		choose.text = "Choose…"
		choose.theme_type_variation = &"GhostButton"
		choose.pressed.connect(func(): shell.resource_picker.show_for(kind, int(spin.value), "", func(id): if is_instance_valid(spin): spin.value = id))
		line.add_child(choose)
	if kind == "sound":
		var play := Button.new()
		play.text = "▶"
		play.tooltip_text = "Play the sound"
		play.theme_type_variation = &"GhostButton"
		play.pressed.connect(func():
			var text := await play_sound(int(spin.value))
			if is_instance_valid(name): name.text = text)
		line.add_child(play)
	line.add_child(name)
	show.call(int(spin.value))
