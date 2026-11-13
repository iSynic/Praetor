extends RefCounted
## What the editor knows about each operation of a step: the thirteen it has a
## form for, their families and what their operand names, and the evidence the
## reconstruction records for every operation (data/capability_opcodes.json,
## copied with its provenance; see tools/extract_capability_data.py).
const Tokens = preload("res://theme/editor_tokens.gd")

const FAMILIES := [["message", "Message"], ["encounter", "Encounter"], ["combat", "Combat"], ["flow", "Flow"], ["party", "Party"], ["world", "Map and mission"], ["shop", "Shop"], ["ally", "Allies"], ["media", "Sound and picture"], ["reward", "Reward"], ["preserved", "Slot"]]
## What a step does: the groups of the picker and the colours of the steps, as [key, name].
const KINDS := [["message", "Message"], ["encounter", "Encounter"], ["combat", "Combat"], ["test", "Test and branch"], ["jump", "Run, jump and end"], ["pick", "Pick warriors"], ["vitals", "Warriors' health and state"], ["gear", "Belongings and credits"], ["map", "Map and position"], ["clock", "Time and light"], ["mission", "Mission flags and values"], ["shop", "Shop"], ["media", "Sound and picture"], ["reward", "Reward"], ["ally", "Allies"], ["preserved", "Slot"]]
## The codes whose kind is not the default of their family (flow is a test, party is health, world is the map).
const KIND_OF := {
	7: "jump", 8: "jump", 24: "jump", 25: "jump", 39: "jump", 110: "jump",
	84: "preserved", 98: "preserved", 99: "preserved",
	-14: "pick", 14: "pick", 30: "pick", 31: "pick", 50: "pick", 52: "pick", 53: "pick",
	22: "gear", 36: "gear", 60: "gear", 91: "gear", 101: "gear",
	54: "clock", 63: "clock", 106: "clock",
	47: "mission", 66: "mission", 69: "mission", 76: "mission", 103: "mission", 109: "mission", -32: "mission",
}
const MESSAGE_LIMIT := 255

static var _rows: Dictionary = {}
static var _provenance: Dictionary = {}
static var _codes: Dictionary = {}
static var _forms: Array = []


static func _load() -> void:
	if not _rows.is_empty(): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/capability_opcodes.json"))
	if not parsed is Dictionary: return
	_provenance = parsed.get("_provenance", {})
	for row in parsed.get("opcodes", []):
		_rows[int(row.value) if row.value != null else -999999] = row


## The table of script codes (data/script_codes.json, built by tools/build_script_codes.py): what each
## code's ID and Extra Codes are and whether the editor writes it.
static func code(opcode: int) -> Dictionary:
	if _codes.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/script_codes.json"))
		if parsed is Dictionary:
			for entry in parsed.get("codes", []): _codes[int(entry.code)] = entry
	return _codes.get(opcode, {})


## Whether the code also reads the row after the one its ID names.
static func has_companion(opcode: int) -> bool:
	return uses_extra(opcode) and code(opcode).get("companion") != null


## Whether the code's ID names an Extra Codes row.
static func uses_extra(opcode: int) -> bool:
	var entry := code(opcode)
	return not entry.is_empty() and entry.get("authorable", false) and str(entry.get("id_class", "")) == "extra"


## The reconstruction's row for `opcode`, or {} when it names none.
static func row(opcode: int) -> Dictionary:
	_load()
	return _rows.get(opcode, {})


static func provenance() -> Dictionary:
	_load()
	return _provenance


## How many numbered operations the reconstruction records that the editor offers no form for.
static func unlisted_count() -> int:
	_load()
	var count := 0
	for opcode in _rows.keys():
		if int(opcode) != -999999 and not has_form(int(opcode)): count += 1
	return count


## How many operations the reconstruction records.
static func known_count() -> int:
	_load()
	return _rows.size()


## The codes the editor writes, as [opcode, name, family, what the ID takes], in the picker's order.
static func forms() -> Array:
	if _forms.is_empty():
		code(0)
		var entries: Array = _codes.values().filter(func(entry): return entry.get("authorable", false))
		entries.sort_custom(func(a, b): return int(a.get("order", 1000 + int(a.code))) < int(b.get("order", 1000 + int(b.code))))
		for entry in entries:
			_forms.append([int(entry.code), str(entry.get("label", entry.name)), str(entry.get("family", "flow")), str(entry.get("takes", entry.get("id_text", "")))])
	return _forms


static func form(opcode: int) -> Array:
	for entry in forms():
		if entry[0] == opcode: return entry
	return []


## What the ID of the code takes, in a few words.
static func takes(opcode: int) -> String:
	var entry := form(opcode)
	return str(entry[3]) if not entry.is_empty() else ""


## Whether the ID names a record the author can open.
static func linked(opcode: int) -> bool:
	return bool(code(opcode).get("link", false))


## The least and greatest value the ID takes, for the field that edits it.
static func limits(opcode: int) -> Array:
	return kind_limits(code(opcode).get("id", {}))


## The same for any kind of the table, an Extra Code's as well as an ID's.
static func kind_limits(kind: Dictionary) -> Array:
	if str(kind.get("kind", "")) == "soft": return kind_limits(kind.inner)
	match str(kind.get("kind", "")):
		"range": return [int(kind.min), int(kind.max)]
		"signed_count": return [-int(kind.max), int(kind.max)]
		"enum":
			var values: Array = kind.values.map(func(value): return int(value))
			return [values.min(), values.max()]
		"stage": return [-20, 20]
		"extra": return [0, 32767]
		"map": return [-32768 if bool(kind.keep_negative) else 0, 32767]
		"treasure_or_shop": return [-32768, 32767]
		"record": return [-32768 if str(kind.sign) == "magnitude" else 0, 32767]
	return [-32768, 32767]


static func has_form(opcode: int) -> bool:
	return not form(opcode).is_empty()


static func name_of(opcode: int, authorable := true) -> String:
	var entry := form(opcode)
	if entry.is_empty() and authorable: return "Does nothing · %d" % opcode
	return str(entry[1]) if not entry.is_empty() and authorable else "Opcode %d" % opcode


static func family_of(opcode: int, authorable := true) -> String:
	var entry := form(opcode)
	return str(entry[2]) if not entry.is_empty() and authorable else "preserved"


static func colour(family: String) -> Color:
	return Tokens.FAMILY.get(family, Tokens.DIM)


## What the step does, for its colour and its group in the picker.
static func kind_of(opcode: int, authorable := true) -> String:
	if not authorable: return "preserved"
	if KIND_OF.has(opcode): return KIND_OF[opcode]
	match family_of(opcode, authorable):
		"flow": return "test"
		"party": return "vitals"
		"world": return "map"
		var other: return other


static func kind_colour(kind: String) -> Color:
	return Tokens.KIND.get(kind, Tokens.DIM)


## The bytes a step owns in its program row: [opcode offset, opcode width, operand offset].
static func offsets(family: String, branch: int, slot: int) -> Array:
	if family in ["walking", "story"]: return [8 + slot * 2, 2, 24 + slot * 2]
	return [branch * 8 + slot, 1, 32 + branch * 16 + slot * 2]


## The record a step's operand names, as {kind, id} for linking, or {}.
static func target(opcode: int, operand: int) -> Dictionary:
	match opcode:
		1: return {"kind": "message", "id": absi(operand)}
		2: return {"kind": "battle_extra", "id": absi(operand)}
		10: return {"kind": "reward", "id": absi(operand)}
		4: return {"kind": "menu", "id": absi(operand)}
		5: return {"kind": "typed", "id": absi(operand)}
		39: return {"kind": "story", "id": absi(operand)}
		110: return {"kind": "stage", "id": absi(operand) - 1}
	return {}


## The short line under a step's name: what its operand points at.
static func subtitle(opcode: int, operand: int, authorable: bool, message_text := "") -> String:
	if not authorable: return "Preserved · plays as recorded"
	match opcode:
		0: return "Continue"
		1: return "Message %d%s" % [absi(operand), (" · " + message_text) if not message_text.is_empty() else ""]
		2: return "Battle extra %d" % operand
		4: return "Choice %d" % absi(operand)
		5: return "Typed %d" % absi(operand)
		9: return "Sound %d" % operand
		10: return "Reward %d" % operand
		14: return "Count %d" % operand
		24: return "Ends the script"
		39: return "Story %d" % absi(operand)
		48: return "Selected battle %d" % operand
		100: return "Reward kind %d" % operand
		110: return "Stage %d" % absi(operand)
	if form(opcode).is_empty(): return "The game skips this number" if authorable else ""
	return "Extra Codes row %d" % operand if uses_extra(opcode) else "ID %d" % operand
