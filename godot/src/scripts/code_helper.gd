extends PanelContainer
## The code helper: a drawer at the right that explains the step in hand. What
## the operation is and how it is evidenced come from the reconstruction's
## capability data; the name tokens are the ones a message can carry.
signal closed
const Capability = preload("res://src/scripts/capability.gd")
const Card = preload("res://src/widgets/card.gd")
const Manual = preload("res://src/scripts/script_manual.gd")
const Prose = preload("res://src/widgets/prose.gd")
const KeyValueRow = preload("res://src/widgets/key_value_row.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

const ROUTE_NAMES := {"exploration": "walking triggers, stories and encounters", "battle_round": "battle rounds", "death_script": "death scripts", "getup": "get-up scripts", "nested_callback": "nested callbacks", "enemy_turn": "enemy turns", "combat_story": "combat stories"}

var _body := VBoxContainer.new()
var _sub := Label.new()


func _init() -> void:
	theme_type_variation = &"HelperPanel"
	visible = false
	custom_minimum_size.x = 520
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_left = -520
	offset_top = 48
	offset_bottom = -28
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"Heading"
	title.text = "Code helper"
	head.add_child(title)
	var key := Label.new()
	key.theme_type_variation = &"Kbd"
	key.text = "F1"
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(key)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var close := preload("res://src/widgets/icon_button.gd").new()
	close.glyph = "close"
	close.pressed.connect(func(): hide(); closed.emit())
	head.add_child(close)
	column.add_child(head)
	_sub.theme_type_variation = &"Dim"
	column.add_child(_sub)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_body.add_theme_constant_override("separation", 10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	var foot := Label.new()
	foot.theme_type_variation = &"Dim"
	foot.add_theme_font_size_override("font_size", 12)
	foot.text = "Ctrl Enter applies · Ctrl . checks · F5 plays from here"
	column.add_child(foot)


func _kv(parent: Control, key: String, value: String, mono := false) -> void:
	var row := KeyValueRow.new()
	row.key = key
	row.value = value
	row.mono = mono
	row.key_width = 84
	parent.add_child(row)


## Explains the step: `opcode` and its position in `where`, for example "Step 2". The code's entry in the scripting manual
## comes first, then the evidence the reconstruction records for it, then how names are written in texts.
func show_step(where: String, opcode: int, authorable: bool) -> void:
	for child in _body.get_children(): _body.remove_child(child); child.queue_free()
	_sub.text = "%s · %s" % [where, Capability.name_of(opcode, authorable)]
	var entry := Manual.entry(opcode)
	if entry.is_empty():
		_unlisted(opcode)
	else:
		_entry(entry, Capability.kind_colour(Capability.kind_of(opcode, authorable)))
	_evidence(opcode)
	_names()
	var source := Label.new()
	source.theme_type_variation = &"Dim"
	source.add_theme_font_size_override("font_size", 11)
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var manual := Manual.provenance()
	source.text = "The entry is the scripting codes manual%s; the evidence is the reconstruction's capability map, copied %s." % [(" (" + str(manual.get("revision", "")) + ")") if not str(manual.get("revision", "")).is_empty() else "", str(Capability.provenance().get("extracted", ""))]
	_body.add_child(source)


func _prose(card: Card, markup: String) -> void:
	var prose := Prose.new()
	prose.show_markup(markup)
	card.add_row(prose)


## One entry of the manual: its title, then each labelled part under a caption of its own.
func _entry(entry: Dictionary, colour: Color) -> void:
	var title := Label.new()
	title.theme_type_variation = &"Heading"
	title.text = "Code %d · %s" % [int(entry.code), str(entry.title)]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(title)
	var card := Card.new()
	card.title = "Scripting manual"
	card.dot_color = colour
	card.gap = 8
	_body.add_child(card)
	for part in entry.sections:
		var caption := Label.new()
		caption.theme_type_variation = &"CaptionMuted"
		caption.text = "EXTRA CODES" if part.label == "E-Codes" else str(part.label).to_upper()
		if part.label == "Caution": caption.add_theme_color_override("font_color", Tokens.WARN)
		card.add_row(caption)
		var paragraphs: Array = part.paragraphs
		if part.label == "E-Codes" and not paragraphs.is_empty():
			var names := _numbered(paragraphs[0])
			if not names.is_empty():
				for line in names:
					var row := HBoxContainer.new()
					row.add_theme_constant_override("separation", 10)
					var number := Label.new()
					number.theme_type_variation = &"BadgeGood"
					number.text = str(line[0])
					number.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
					row.add_child(number)
					var words := Prose.new()
					words.show_markup(str(line[1]))
					row.add_child(words)
					card.add_row(row)
				paragraphs = paragraphs.slice(1)
		for paragraph in paragraphs: _prose(card, str(paragraph))


## The lines "N) words" of a paragraph as [N, words], or [] when it is anything else.
func _numbered(paragraph: String) -> Array:
	var found: Array = []
	for line in paragraph.split("\n"):
		var at := line.find(") ")
		if at < 1 or not line.substr(0, at).is_valid_int(): return []
		found.append([line.substr(0, at), line.substr(at + 2)])
	return found


## A number the manual has no entry for: the game skips the step.
func _unlisted(opcode: int) -> void:
	var card := Card.new()
	card.title = "NOT A CODE THE GAME HANDLES"
	card.dot_color = Tokens.WARN
	_body.add_child(card)
	_prose(card, "The scripting manual gives no entry for %d. A step with a number the game does not handle is skipped, and the script goes on with the next step." % opcode)
	_blocks(card, Manual.chapter("Numbers that do nothing").get("blocks", []))


func _blocks(card: Card, blocks: Array) -> void:
	for block in blocks:
		if block.has("h"):
			var heading := Label.new()
			heading.theme_type_variation = &"Strong"
			heading.text = str(block.t)
			card.add_row(heading)
		elif block.has("p"):
			_prose(card, str(block.p))
		elif block.has("li"):
			for item in block.li: _prose(card, "• " + str(item))


## What the reconstruction records for the code: its native operation, the evidence, where it runs.
func _evidence(opcode: int) -> void:
	var row := Capability.row(opcode)
	var operation := Card.new()
	operation.title = "Evidence"
	_body.add_child(operation)
	if row.is_empty():
		_kv(operation.body, "Native", "not in the reconstruction's map", false)
		return
	_kv(operation.body, "Native", "%s · opcode %d" % [str(row.operation), opcode], true)
	var evidence := HBoxContainer.new()
	evidence.add_theme_constant_override("separation", 6)
	var key := Label.new()
	key.theme_type_variation = &"Dim"
	key.text = "Evidence"
	key.custom_minimum_size.x = 84
	evidence.add_child(key)
	for entry in [[row.status, &"BadgeGood" if row.status == "native-verified" else &"Badge"], [row.editor, &"BadgeWarn" if row.editor == "warn" else &"BadgeGood"]]:
		var badge := Label.new()
		badge.theme_type_variation = entry[1]
		badge.text = str(entry[0])
		evidence.add_child(badge)
	operation.add_row(evidence)
	if row.get("behavior") != null: _kv(operation.body, "Does", str(row.behavior))
	if Capability.has_form(opcode): _kv(operation.body, "Operand", Capability.takes(opcode))
	var seen: Array = []
	for context in row.routes: seen.append(ROUTE_NAMES.get(context, context))
	_kv(operation.body, "Runs in", ", ".join(seen))
	_kv(operation.body, "Diagnostics", "None open" if int(row.open_diagnostics) == 0 else "%d open of %d" % [int(row.open_diagnostics), int(row.diagnostics)])


## How a text names the squad: the manual's chapter.
func _names() -> void:
	var chapter := Manual.chapter("Names in text")
	if chapter.is_empty(): return
	var card := Card.new()
	card.title = "NAMES IN TEXT"
	_body.add_child(card)
	_kv(card.body, "Limit", "%d bytes, Mac Roman" % Capability.MESSAGE_LIMIT, true)
	_blocks(card, chapter.blocks)
