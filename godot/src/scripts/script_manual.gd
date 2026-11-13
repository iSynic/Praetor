extends RefCounted
## The scripting codes manual, as the editor carries it (data/script_manual.json, built by tools/build_script_manual.py): the
## entry of every code and the chapters around them.
static var _codes: Dictionary = {}
static var _chapters: Dictionary = {}
static var _provenance: Dictionary = {}


static func _load() -> void:
	if not _codes.is_empty(): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/script_manual.json"))
	if not parsed is Dictionary: return
	_provenance = parsed.get("_provenance", {})
	for entry in parsed.get("codes", []): _codes[int(entry.code)] = entry
	for chapter in parsed.get("chapters", []): _chapters[str(chapter.title)] = chapter


## The entry of `code`: {code, title, sections: [{label, paragraphs}]}, or {} when the manual gives none.
static func entry(code: int) -> Dictionary:
	_load()
	return _codes.get(code, {})


## One section of an entry (its paragraphs), or [] when the entry has none.
static func section(code: int, label: String) -> Array:
	for part in entry(code).get("sections", []):
		if str(part.label) == label: return part.paragraphs
	return []


## A chapter by its title: {title, blocks}.
static func chapter(title: String) -> Dictionary:
	_load()
	return _chapters.get(title, {})


static func provenance() -> Dictionary:
	_load()
	return _provenance
