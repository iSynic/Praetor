extends RefCounted
## A bounded recipe, composed by the same backend operation as the CLI. It is
## shown as the Connected mission panel: the fields, the route the recipe
## wires, the rows it adds and what makes the backend refuse it.
const Card = preload("res://src/widgets/card.gd")
const ConnectedMissionDialog = preload("res://src/dialogs/connected_mission_dialog.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

const BYTE_LIMITS := {"name": 255, "completion_name": 255, "introduction": 255, "prompt": 255, "accept_label": 79, "decline_label": 79, "declined": 255, "victory": 255, "completion": 255, "monster_name": 29}
const REJECTED := [
	"connected authoring requires a template-derived mission; create one from an unchanged import first",
	"connected recipe requires a fresh template-derived project; existing authored work will not be replaced",
	"Data LD map 0 cell (x,y) field object: recipe clearing overlaps an inherited object; choose another start",
	"Data DD: no unplaced empty program slot; no imported program will be cleared to make room",
]

var shell: Control
var window: ConnectedMissionDialog
var controls: Dictionary = {}
var receipt: Label
var counters: Dictionary = {}
var _route := VBoxContainer.new()
var _adds := VBoxContainer.new()
var _adds_card := Card.new()
var _next: Dictionary = {}
var _seed_notes: Dictionary = {}


func _init(owner_shell: Control) -> void:
	shell = owner_shell
	window = ConnectedMissionDialog.new()
	window.name = "MissionRecipeWindow"
	window.title = "Connected mission"
	window.subtitle = "from current template-derived project"
	window.panel_size = Vector2(1100, 0)
	shell.add_child(window)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	window.body.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	var defaults := {"name":"Micro Patrol","completion_name":"Patrol Complete","introduction":"A training drone blocks the patrol route.","prompt":"Engage the drone and clear the route?","accept_label":"Engage","decline_label":"Not yet","declined":"Return when the squad is ready.","victory":"Route secure. Your patrol reward has been issued.","completion":"Patrol complete. The squad has reached its destination.","monster_name":"Training Drone","credits":25,"map":0,"x":2,"y":2,"floor":155,"monster_seed":1,"battle_seed":1,"choice_seed":0}
	var mission := Card.new()
	mission.title = "Mission"
	left.add_child(mission)
	_text(mission, "Name", "name", defaults.name, false)
	_text(mission, "Completion name", "completion_name", defaults.completion_name, false)
	var start := HBoxContainer.new()
	start.add_theme_constant_override("separation", 8)
	var start_label := _label("Start")
	start.add_child(start_label)
	for key in ["map", "x", "y", "floor"]:
		var tag := Label.new()
		tag.theme_type_variation = &"Dim"
		tag.text = key.capitalize()
		start.add_child(tag)
		start.add_child(_spin(key, defaults[key]))
	mission.add_row(start)
	var note := Label.new()
	note.theme_type_variation = &"Dim"
	note.add_theme_font_size_override("font_size", 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "First create a template-derived scenario from an unchanged import. This recipe adds new linked records, a 16×16 floor clearing, a walking trigger one cell east of the start, and a completion stage two cells east. Inherited support and unknown bytes remain. It replaces stages 0 and 1; use a fresh template-derived project."
	mission.add_row(note)
	var text := Card.new()
	text.title = "Text"
	text.right.add_child(_dim("Mac Roman bytes"))
	left.add_child(text)
	for key in ["introduction", "prompt", "accept_label", "decline_label", "declined", "victory", "completion"]:
		_text(text, key.replace("_", " ").capitalize(), key, defaults[key], true)
	var seeds := Card.new()
	seeds.title = "Seeds and reward"
	left.add_child(seeds)
	_seed(seeds, "Choice seed", "choice_seed", defaults.choice_seed)
	_seed(seeds, "Battle seed", "battle_seed", defaults.battle_seed)
	_seed(seeds, "Monster seed", "monster_seed", defaults.monster_seed)
	_text(seeds, "Monster name", "monster_name", defaults.monster_name, true)
	var credits := HBoxContainer.new()
	credits.add_theme_constant_override("separation", 10)
	credits.add_child(_label("Credits"))
	credits.add_child(_spin("credits", defaults.credits))
	credits.add_child(_dim("fixed · up to 1,000,000"))
	seeds.add_row(credits)
	var route := Card.new()
	route.title = "Route"
	_route.add_theme_constant_override("separation", 4)
	route.add_row(_route)
	right.add_child(route)
	_adds_card.title = "Adds"
	_adds.add_theme_constant_override("separation", 4)
	_adds_card.add_row(_adds)
	right.add_child(_adds_card)
	var rejected := Card.new()
	rejected.title = "Rejected when"
	right.add_child(rejected)
	for reason in REJECTED:
		var line := Label.new()
		line.theme_type_variation = &"Muted"
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.text = "•  " + reason
		rejected.add_row(line)
	receipt = Label.new()
	receipt.theme_type_variation = &"Dim"
	receipt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	receipt.custom_minimum_size.x = 300
	receipt.text = "Native monster art, attacks and descriptions are kept from the seed."
	window.footer_left.add_child(receipt)
	window.add_button("Cancel").pressed.connect(window.close)
	var create := window.add_button("Author linked mission · one undo step", "primary")
	create.pressed.connect(func():
		create.disabled = true
		await author(spec())
		create.disabled = false)
	window.visibility_changed.connect(func(): if window.visible: _refresh())
	_preview()


func spec() -> Dictionary:
	var result := {}
	for key in controls: result[key] = controls[key].text if controls[key] is LineEdit else int(controls[key].value)
	return result


func _label(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"Dim"
	label.text = text
	label.custom_minimum_size.x = 120
	return label


func _dim(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"Dim"
	label.text = text
	return label


func _text(card: Card, caption: String, key: String, value: String, counted: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_label(caption))
	var input := LineEdit.new()
	input.text = value
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	controls[key] = input
	if counted:
		var counter := Label.new()
		counter.theme_type_variation = &"MonoDim"
		counter.custom_minimum_size.x = 70
		counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(counter)
		counters[key] = counter
	input.text_changed.connect(func(_value): _preview())
	card.add_row(row)


func _spin(key: String, value: int) -> SpinBox:
	var input := SpinBox.new()
	input.max_value = 1000000
	input.value = value
	input.custom_minimum_size.x = 84
	input.value_changed.connect(func(_value): _preview())
	controls[key] = input
	return input


func _seed(card: Card, caption: String, key: String, value: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_label(caption))
	row.add_child(_spin(key, value))
	var note := _dim("")
	row.add_child(note)
	_seed_notes[key] = note
	card.add_row(row)


## The next free row of each family, read when the panel opens.
func _refresh() -> void:
	if shell.summary.is_empty(): return
	var response: Dictionary = await shell.request_backend({"op": "authored_records"})
	if response.get("ok", false):
		for table in response.result.families: _next[str(table.family)] = int(table.count)
	await shell.record_ui._ensure_names()
	_preview()


func _preview() -> void:
	for key in counters:
		var length := 0
		var text: String = controls[key].text
		length = text.to_utf8_buffer().size()
		counters[key].text = "%d / %d" % [length, BYTE_LIMITS[key]]
	var monster_seed := int(controls.monster_seed.value)
	_seed_notes.choice_seed.text = "imported choice %d · four labelled branches" % int(controls.choice_seed.value)
	_seed_notes.battle_seed.text = "imported battle %d" % int(controls.battle_seed.value)
	_seed_notes.monster_seed.text = str(shell.record_ui.names.get(monster_seed, "")) if shell.record_ui != null else ""
	for child in _route.get_children(): _route.remove_child(child); child.queue_free()
	for child in _adds.get_children(): child.queue_free()
	_adds_card.title = "Adds"
	if _next.is_empty():
		_route_line("flow", "The route appears when a project is open", "", 0)
		return
	var message: int = _next.message
	var x := int(controls.x.value)
	var y := int(controls.y.value)
	_route_line("flow", "Map %d · %d, %d" % [int(controls.map.value), x + 1, y], "walking trigger, one cell east of the start", 0)
	_route_line("message", "Message %d" % message, "introduction", 0)
	_route_line("encounter", "Choice %d" % _next.choice, "prompt %d · %s / %s" % [message + 1, controls.accept_label.text, controls.decline_label.text], 0)
	_route_line("encounter", str(controls.accept_label.text), "", 1)
	_route_line("combat", "Battle extra %d" % _next.battle_extra, "ordinary battle, mode 0", 2)
	_route_line("combat", "Battle %d" % _next.battle, "1 %s" % controls.monster_name.text, 2)
	_route_line("reward", "Reward %d" % _next.reward, "%d credits" % int(controls.credits.value), 2)
	_route_line("message", "Message %d" % (message + 3), "victory", 2)
	_route_line("flow", "Stage transition -2", "stage 1, no confirmation", 2)
	_route_line("flow", "Stage 1 · %d, %d" % [x + 2, y], "%s · start story %d" % [controls.completion_name.text, _next.story], 2)
	_route_line("message", "Message %d" % (message + 4), "completion", 2)
	_route_line("encounter", str(controls.decline_label.text), "", 1)
	_route_line("message", "Message %d" % (message + 2), "back to exploration, no battle or reward", 2)
	_adds_card.title = "Adds · 11 new rows"
	window.refit()
	for entry in [["Messages", "%d – %d" % [message, message + 4]], ["Choice", str(_next.choice)], ["Story", str(_next.story)], ["Battle extra", str(_next.battle_extra)], ["Battle", str(_next.battle)], ["Monster", "%d · %s" % [_next.monster, controls.monster_name.text]], ["Reward", str(_next.reward)], ["Map %d" % int(controls.map.value), "16 × 16 floor clearing at %d, %d · walking trigger placed at %d, %d" % [x, y, x + 1, y]]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var key := _label(entry[0])
		row.add_child(key)
		var value := Label.new()
		value.theme_type_variation = &"Mono"
		value.text = entry[1]
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(value)
		_adds.add_child(row)


func _route_line(family: String, name: String, note: String, depth: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var indent := Control.new()
	indent.custom_minimum_size.x = depth * 14
	row.add_child(indent)
	var bar := ColorRect.new()
	bar.color = Tokens.FAMILY.get(family, Tokens.DIM)
	bar.custom_minimum_size = Vector2(3, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var label := Label.new()
	label.theme_type_variation = &"Mono"
	label.text = name
	row.add_child(label)
	if not note.is_empty():
		var detail := Label.new()
		detail.theme_type_variation = &"Dim"
		detail.text = note
		detail.clip_text = true
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(detail)
	_route.add_child(row)


func author(spec_values: Dictionary) -> bool:
	var response: Dictionary = await shell.request_backend({"op":"author_connected_mission","expected_revision":shell.bridge.revision,"spec":spec_values})
	if not response.get("ok",false): receipt.text = shell._error(response); return false
	await shell._set_summary(response.result.summary)
	receipt.text = "Authored records: "+JSON.stringify(response.result.recipe.records)+"\nSave a new checkpoint, then export. Runtime acceptance requires a receipt bound to the exported bytes."
	shell.status("Connected mission authored · new records and links · one undo step")
	return true
