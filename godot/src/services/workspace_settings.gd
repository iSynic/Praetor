extends RefCounted
## The workbench's own choices in the settings file the adapter keeps beside
## the editor: where checkpoints and exports go by default, the pinned seed for
## Play from here, the map grid and the compact layout. The adapter owns the
## installation and the recent projects in the same file; keys written here
## and keys written there are each kept as they were.
signal changed(key: String)

const DEFAULTS := {"output_parent": "", "seed": 12, "grid": true, "compact": true}
var path := ""
var values: Dictionary = DEFAULTS.duplicate()


## Reads the choices from the file the adapter named when it described itself.
func load_from(settings_file: String) -> void:
	path = settings_file
	values = DEFAULTS.duplicate()
	var stored := _read()
	for key in DEFAULTS:
		if not stored.has(key): continue
		# A number comes back from JSON as a float.
		if key == "seed" and stored[key] is float: values[key] = int(stored[key])
		elif typeof(stored[key]) == typeof(DEFAULTS[key]): values[key] = stored[key]


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


## Stores one choice. Returns false when the file could not be written; the
## choice then holds for this session only.
func set_value(key: String, value: Variant) -> bool:
	values[key] = value
	changed.emit(key)
	if path.is_empty(): return false
	var stored := _read()
	stored[key] = value
	var temp := path + ".part"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(stored, "  ") + "\n")
	file.close()
	return DirAccess.rename_absolute(temp, path) == OK


func _read() -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
