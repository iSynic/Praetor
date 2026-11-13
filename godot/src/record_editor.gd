extends RefCounted
## Typed native record forms: the monster and reward workspaces, and the forms
## for the other record families that Author records opens. The shell owns
## drafts; Rust owns state and validation.
const Card = preload("res://src/widgets/card.gd")
const MonsterVault = preload("res://src/pages/monster_vault.gd")
const PageHeader = preload("res://src/widgets/page_header.gd")
const RecordList = preload("res://src/widgets/record_list.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

const FAMILIES := ["message","choice","story","battle_extra","battle","monster","reward"]
const NOUNS := {"message": "Message", "choice": "Choice", "story": "Story", "battle_extra": "Battle extra", "battle": "Battle", "monster": "Monster", "reward": "Reward"}
const PLURALS := {"message": "Messages", "choice": "Choices", "story": "Stories", "battle_extra": "Battle extras", "battle": "Battles", "monster": "Monsters", "reward": "Rewards"}
const PAGE := 128

var shell: Control
var family: OptionButton
var id: SpinBox
var seed: SpinBox
var geometry: Label
var rows: VBoxContainer
var data: Dictionary = {}
var controls: Dictionary = {}
var loading := false
## The monster fields that hold a number the game gives a name or an icon.
const REFERENCE_KINDS := {"icon": "icon", "item": "item", "ammunition": "item", "category": "monster_kind", "attack_condition": "special_attack", "death_sound": "sound", "movement_sound": "sound", "attack_sound": "sound", "weapon": "item"}
var _monster_spins: Dictionary = {}
var _monster_description: TextEdit
## Where `card` puts the next card when it is not the form itself: the page of a tab.
var _card_into: Control
var _refreshing := false
var _refresh_again := false
var list := RecordList.new()
var header := PageHeader.new()
var names: Dictionary = {}
var count := 0
var imported_count := 0
var duplicate_button: Button
var callers_button: Button
var vault: MonsterVault
var _model := Control.new()
var _names_key := ""
var _rewards: Dictionary = {}
var _rewards_key := ""
var _rewards_opened := false
var _used_by := Card.new()
var _used_rows := VBoxContainer.new()


func _init(owner_shell: Control, page: Control) -> void:
	shell = owner_shell
	_model.visible = false
	page.add_child(_model)
	family = OptionButton.new(); _model.add_child(family)
	for name in FAMILIES: family.add_item(name.capitalize())
	family.select(FAMILIES.find("monster"))
	id = SpinBox.new(); id.max_value = 32767; _model.add_child(id)
	seed = SpinBox.new(); seed.max_value = 32767; _model.add_child(seed)
	geometry = Label.new(); _model.add_child(geometry)
	list.filter_placeholder = "Filter by id or name…"
	list.custom_minimum_size.x = 270
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.set_columns([{"title": "ID", "width": 52, "mono": true}, {"title": "Name", "width": 0}])
	vault = MonsterVault.new(self)
	list.row_selected.connect(func(row): if row != null and not loading and not vault.active: shell.guard(select_id.bind(int(row))))
	list.selection_changed.connect(func(ids): vault.select(ids))
	list.scope_changed.connect(func(scope): shell.guard(vault.set_scope.bind(str(scope))))
	page.add_child(list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 10)
	scroll.add_child(centre)
	callers_button = header.add_button("Callers")
	callers_button.pressed.connect(func(): shell.find_uses(FAMILIES[family.selected], int(id.value)))
	duplicate_button = header.add_button("Duplicate")
	duplicate_button.pressed.connect(func(): shell.guard(duplicate))
	vault.attach(header)
	centre.add_child(header)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	centre.add_child(rows)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 260
	side.add_theme_constant_override("separation", 10)
	page.add_child(side)
	_used_by.title = "Used by"
	_used_by.add_row(_used_rows)
	_used_rows.add_theme_constant_override("separation", 6)
	side.add_child(_used_by)


## Opens the workspace of one family: the rail's Monsters and Rewards.
func show_family(name: String) -> void:
	vault.active = false
	family.select(FAMILIES.find(name))
	id.value = 0


func open_record(record_family: String, record_id: int) -> void:
	if record_family == "battle":
		await shell.combat.open_battle(record_id)
		return
	family.select(FAMILIES.find(record_family)); id.value = record_id
	await shell._show_route(7)


func select_id(record_id: int) -> void:
	id.value = record_id
	await refresh()


## Clones the record in hand as a new row of its family.
func duplicate() -> void:
	seed.value = id.value
	await clone_record()


func clone_record() -> void:
	var response: Dictionary = await shell.request_backend({"op":"allocate_record","expected_revision":shell.bridge.revision,"family":FAMILIES[family.selected],"seed":int(seed.value)})
	if response.get("ok",false):
		id.value = int(response.result.id)
		await shell._set_summary(response.result.summary)
		shell.status("Allocated %s %d from imported seed %d · one undo step" % [FAMILIES[family.selected],int(id.value),int(seed.value)])
	else: shell.status(shell._error(response), "err")


## A card in the form column.
func card(title: String) -> Card:
	var result := Card.new()
	result.title = title
	(_card_into if _card_into != null else rows).add_child(result)
	return result


func field(label: String, key: String, value: Variant, minimum := -32768, maximum := 32767, parent: Card = null) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if parent != null: parent.add_row(row)
	else: rows.add_child(row)
	var text := Label.new()
	text.theme_type_variation = &"Dim"
	text.text = label
	text.custom_minimum_size.x = 150
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(text)
	var control: Control
	if value is String:
		var line := LineEdit.new(); line.text = value; line.size_flags_horizontal = Control.SIZE_EXPAND_FILL; line.text_changed.connect(func(_value): changed()); control = line
	else:
		var spin := SpinBox.new(); spin.min_value = mini(minimum,int(value)); spin.max_value = maxi(maximum,int(value)); spin.value = value; spin.custom_minimum_size.x = 130; spin.value_changed.connect(func(_value): changed()); control = spin
	row.add_child(control); controls[key] = control
	return control


func note(text: String, parent: Card = null) -> void:
	var label := Label.new()
	label.theme_type_variation = &"Dim"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if parent != null: parent.add_row(label)
	else: rows.add_child(label)


func action(text: String, callback: Callable, parent: Card = null) -> Button:
	var button := Button.new(); button.text = text; button.pressed.connect(callback)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if parent != null: parent.add_row(button)
	else: rows.add_child(button)
	return button


## Read-only values in a card, one per line.
func facts(parent: Card, entries: Array) -> void:
	for entry in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var key := Label.new(); key.theme_type_variation = &"Dim"; key.text = str(entry[0]); key.custom_minimum_size.x = 150
		row.add_child(key)
		var value := Label.new(); value.theme_type_variation = &"Mono"; value.text = str(entry[1]); value.size_flags_horizontal = Control.SIZE_EXPAND_FILL; value.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		row.add_child(value)
		parent.add_row(row)


## The monsters' names for the list, read again whenever the records change.
func _ensure_names() -> void:
	var key := "%s:%d" % [str(shell.summary.get("path", "")), shell.bridge.revision]
	if key == _names_key: return
	_names_key = key
	names.clear()
	var start := 0
	while true:
		var response: Dictionary = await shell.request_when_free({"op": "combat_catalogue", "monsters": true, "offset": start, "query": ""})
		if not response.get("ok", false): break
		for row in response.result.rows: names[int(row.id)] = str(row.name)
		start += PAGE
		if start >= int(response.result.total): break


## What each reward pays and gives, read again whenever the records change.
func _ensure_rewards() -> void:
	var key := "%s:%d" % [str(shell.summary.get("path", "")), shell.bridge.revision]
	if key == _rewards_key: return
	var response: Dictionary = await shell.request_backend({"op": "rewards"})
	if not response.get("ok", false): return
	_rewards_key = key
	_rewards.clear()
	for row in response.result.rows: _rewards[int(row.id)] = row


func _reward_summary(row: Dictionary) -> String:
	var parts: Array = []
	if int(row.credits) > 0: parts.append("%d credits" % int(row.credits))
	elif int(row.credits) < 0: parts.append("up to %d credits" % -int(row.credits))
	if int(row.experience) > 0: parts.append("%d experience" % int(row.experience))
	elif int(row.experience) < 0: parts.append("up to %d experience" % -int(row.experience))
	if not row["items"].is_empty(): parts.append("%d item%s" % [row["items"].size(), "" if row["items"].size() == 1 else "s"])
	return " · ".join(parts) if not parts.is_empty() else "Empty"


func _fill_list(f: String) -> void:
	if f == "monster" and vault.active: return
	list.title = PLURALS[f]
	var shown: Array = []
	for index in range(count):
		var label := str(names.get(index, "")) if f == "monster" else "%s %d" % [NOUNS[f], index]
		if f == "monster" and label.is_empty(): label = "Monster %d" % index
		if f == "reward" and _rewards.has(index): label = _reward_summary(_rewards[index])
		shown.append({"id": index, "cells": [str(index), label], "dirty": _has_draft(f, index)})
	list.set_rows(shown)
	list.set_count(count)
	list.select(int(id.value))


func _has_draft(f: String, record_id: int) -> bool:
	for edit in shell.drafts.values():
		if int(edit.get("id", -1)) != record_id: continue
		if str(edit.get("kind", "")).begins_with(f) or (f == "monster" and str(edit.get("kind", "")).begins_with("monster")): return true
	return false


## Builds the form for the selected row. A request made while a build is under way waits for it and then builds again, so the form is never built twice at once.
func refresh() -> void:
	if _refreshing:
		_refresh_again = true
		while _refreshing: await shell.get_tree().process_frame
		return
	_refreshing = true
	while true:
		_refresh_again = false
		await _build_form()
		if not _refresh_again: break
	_refreshing = false


func _build_form() -> void:
	if shell.summary.is_empty(): return
	loading = true; controls.clear(); data = {}
	for child in rows.get_children(): rows.remove_child(child); child.queue_free()
	var f: String = FAMILIES[family.selected]
	vault.sync(f)
	if f == "monster" and vault.active:
		await vault.build(rows)
		loading = false
		return
	var catalogue: Dictionary = await shell.request_when_free({"op":"authored_records"})
	if not catalogue.get("ok",false): loading = false; return
	for table in catalogue.result.families:
		if table.family == f:
			geometry.text = "%s · %d rows (%d imported) · supported limit %d · %d trailing bytes retained" % [table.file,int(table.count),int(table.imported_count),int(table.supported_limit),int(table.trailing_bytes)]
			seed.max_value = maxi(0,int(table.imported_count)-1)
			count = int(table.count); imported_count = int(table.imported_count)
	if f == "monster":
		await _ensure_names()
		await vault.load_entries()
		vault.sync(f)
	if f in ["monster", "reward"]:
		await shell.ensure_item_names()
		await shell.references.ensure()
	if f == "reward":
		await _ensure_rewards()
		if not _rewards_opened:
			_rewards_opened = true
			var first := -1
			for index in range(count):
				if _rewards.has(index) and _reward_summary(_rewards[index]) != "Empty": first = index; break
			if first >= 0 and _reward_summary(_rewards.get(int(id.value), {"credits": 0, "experience": 0, "items": []})) == "Empty": id.value = first
	id.value = clampi(int(id.value), 0, maxi(0, count - 1))
	_fill_list(f)
	var response: Dictionary = await shell.request_when_free({"op":"authored_record","family":f,"id":int(id.value)})
	if not response.get("ok",false): note(shell._error(response)); loading = false; return
	data = response.result
	_show_header(f)
	match f:
		"message":
			var text := card("Text")
			field("Message · 255 Mac Roman bytes","text",data.text,-32768,32767,text)
		"choice":
			var prompt := card("Prompt")
			field("Prompt message ID","prompt",data.prompt,0,32767,prompt)
			for index in range(4):
				var choice := card("Choice %d" % (index+1))
				field("Label · 79 bytes","label%d" % index,data.labels[index],-32768,32767,choice)
				field("Selector (0 off; 1–4 branch)","selector%d" % index,int(data.selectors[index]),0,4,choice)
				action("Edit branch %d steps" % (index+1),func(): shell.guard(func(): await shell._choose_program("menu",int(id.value),index); await shell._show_route(5)),choice)
			note("Retained policy bytes 100–103: "+str(data.retained_header_hex))
		"story": action("Edit eight story steps",func(): shell.guard(func(): await shell._choose_program("story",int(id.value),0); await shell._show_route(5)))
		"battle_extra":
			var limits := card("Battles")
			field("Minimum","minimum",data.minimum,0,32767,limits)
			field("Maximum","maximum",data.maximum,0,32767,limits)
			action("Choose minimum battle…",func(): shell.picker_dialog.show_for("battle",int(controls.minimum.value),"Extra %d · minimum battle" % int(id.value),func(chosen): controls.minimum.value = chosen),limits)
			action("Choose maximum battle…",func(): shell.picker_dialog.show_for("battle",int(controls.maximum.value),"Extra %d · maximum battle" % int(id.value),func(chosen): controls.maximum.value = chosen),limits)
			action("Open minimum battle",func(): shell.guard(open_record.bind("battle",int(controls.minimum.value))),limits)
			var around := card("Sound, message and clean-up")
			field("Sound","sound",data.sound,0,32767,around)
			field("Message","message",data.message,0,32767,around)
			field("Cleanup mode · 0 ordinary / 5 no monster loot","cleanup_mode",data.cleanup_mode,0,5,around)
			note("Maximum 0 selects the minimum battle. Cleanup mode does not load a treasure row. Follow battle opcode 2 with reward opcode 10 for an explicit award.")
		"battle":
			note("Battle populations are placed on the grid of the Battles page.")
			action("Open on the Battles page",func(): shell.guard(open_record.bind("battle",int(id.value))))
		"monster":
			_monster_form()
		"reward":
			var payout := card("Payout")
			field("Credits (below 0, up to that many at random)","credits",data.credits,-32767,2147483647,payout)
			field("Experience (below 0, up to that many at random)","experience",data.experience,-32767,2147483647,payout)
			var booty := card("Booty")
			_reward_slots(booty)
			note("Explicit opcode 10 loads this row. A listed item is added to the loot, and its level steers the random item that comes with it.")
	await _show_used_by(f)
	duplicate_button.disabled = int(id.value) >= imported_count or f == "battle"
	duplicate_button.tooltip_text = "" if not duplicate_button.disabled else "Only an imported row can be cloned"
	# Rehydrate visible drafts after navigation cancellation or adapter interruption.
	for edit in shell.drafts.values():
		if int(edit.get("id",-1)) != int(id.value): continue
		if edit.kind == "choice_label" and f == "choice": controls["label%d" % int(edit.choice)].text = edit.text
		elif edit.kind == "encounter_condition" and f == "choice" and edit.get("family") == "menu": controls["selector%d" % int(edit.index)].value = edit.value
		elif edit.kind == "choice_prompt" and f == "choice": controls.prompt.value = edit.message
		elif edit.kind == "reward_item" and f == "reward": _reward_spins["%s:%d" % ["item", int(edit.slot)]].set_value_no_signal(int(edit.item)); _reward_spins["level:%d" % int(edit.slot)].set_value_no_signal(int(edit.level))
		elif edit.kind == f or (f == "monster" and edit.kind == "monster_stats"):
			for key in controls:
				if edit.has(key):
					if controls[key] is LineEdit: controls[key].text = edit[key]
					elif controls[key] is SpinBox: controls[key].value = edit[key]
	if f == "monster": _rehydrate_monster()
	loading = false
	_show_header(f)


## The monster form: the definition's fields in cards, each change one draft.
func _monster_form() -> void:
	_monster_spins.clear()
	_monster_description = null
	var by_group: Dictionary = {}
	for row in data.fields:
		if not by_group.has(row.group): by_group[row.group] = []
		by_group[row.group].append(row)
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_child(tabs)
	var page := func(title: String) -> VBoxContainer:
		var box := VBoxContainer.new()
		box.name = title
		box.add_theme_constant_override("separation", 12)
		tabs.add_child(box)
		return box
	_card_into = page.call("Overview")
	var identity := card("Identity")
	field("Name · 29 Mac Roman bytes","name",data.name,-32768,32767,identity)
	_grid_rows(identity, by_group.get("Identity", []), 2)
	_description_card()
	var body := card("Body")
	var stat_ranges := {"level":[0,127],"stamina":[0,30000],"speed":[1,32767],"movement":[0,127]}
	for key in ["level","stamina","speed","movement"]: field(key.capitalize(),key,data[key],stat_ranges[key][0],stat_ranges[key][1],body)
	_grid_rows(body, by_group.get("Body", []), 2)
	var behaviour := card("Behaviour")
	_behaviour_fields(behaviour)
	_grid_rows(behaviour, by_group.get("Behaviour", []), 2)
	_card_into = page.call("Attacks")
	_attack_rows(card("Attacks"), by_group.get("Attacks", []))
	_card_into = page.call("Spells")
	var psi := card("Psi")
	_spell_fields(psi)
	_grid_rows(psi, by_group.get("Psi", []), 2)
	_card_into = page.call("Items")
	var loot := card("Loot")
	_grid_rows(loot, by_group.get("Loot", []), 2)
	action("Clear six inherited item drops and cash bound",func(): shell.drafts["monster_no_drops:%d" % int(id.value)] = {"kind":"monster_no_drops","id":int(id.value)}; shell._invalidate_receipt(); shell._update_buttons(); shell.status("Drop clearing drafted · Apply edits"),loot)
	_card_into = page.call("Saves")
	_grid_rows(card("Saves"), by_group.get("Saves", []).filter(func(row): return str(row.field) == "save"), 3)
	_grid_rows(card("Categories"), by_group.get("Saves", []).filter(func(row): return str(row.field) == "category"), 2)
	_card_into = page.call("Sounds")
	var sounds := card("Sounds")
	_grid_rows(sounds, by_group.get("Sounds", []), 2)
	_card_into = page.call("Conditions")
	_grid_rows(card("Conditions the monster starts with, in rounds"), by_group.get("Conditions", []), 2)
	_card_into = null
	note("Art, equipment and the fields not listed here remain inherited from the row. A value outside what the engine accepts is shown and kept.")


## What the Archives say of the monster: its slot of Data DES, a draft until it is applied.
func _description_card() -> void:
	var words := card("Description")
	var box := TextEdit.new()
	box.custom_minimum_size.y = 96
	box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.text = str(data.get("description", ""))
	var count := Label.new()
	count.theme_type_variation = &"Dim"
	var saved: String = str(data.get("description", ""))
	var show := func(): count.text = "%d bytes of 255 · Data DES" % box.text.to_utf8_buffer().size()
	show.call()
	box.text_changed.connect(func():
		var key := "monster_description:%d" % int(id.value)
		if box.text == saved: shell.drafts.erase(key)
		else: shell.drafts[key] = {"kind": "monster_description", "id": int(id.value), "text": box.text}
		show.call()
		shell._invalidate_receipt()
		shell._update_buttons())
	_monster_description = box
	words.add_row(box)
	words.add_row(count)


## The name a field row is shown under: the game name for the condition or monster kind it stands for.
func _row_label(row: Dictionary) -> String:
	var named: String = ""
	if str(row.field) == "condition": named = shell.references.label("condition", int(row.index))
	elif str(row.field) == "category": named = shell.references.label("monster_kind", int(row.index))
	if named.is_empty() and str(row.field) == "condition": return "Condition %d" % (int(row.index) + 1)
	return named if not named.is_empty() else str(row.label)


## The spin of one monster field; a change is a draft of that field.
func _monster_spin(row: Dictionary) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = mini(int(row.minimum), int(row.value))
	spin.max_value = maxi(int(row.maximum), int(row.value))
	spin.set_value_no_signal(int(row.value))
	spin.editable = bool(row.authorable)
	spin.custom_minimum_size.x = 110
	spin.value_changed.connect(func(value): _monster_field(row, int(value)))
	_monster_spins["%s:%d" % [row.field, int(row.index)]] = spin
	return spin


func _field_row(panel: Card, row: Dictionary) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.theme_type_variation = &"Dim"
	label.text = _row_label(row)
	label.custom_minimum_size.x = 230
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(label)
	var spin := _monster_spin(row)
	line.add_child(spin)
	if REFERENCE_KINDS.has(str(row.field)): shell.references.attach(line, spin, REFERENCE_KINDS[str(row.field)])
	if not bool(row.authorable):
		var kept := Label.new()
		kept.theme_type_variation = &"Dim"
		kept.text = "kept as recorded"
		line.add_child(kept)
	panel.add_row(line)


## Fields side by side, `across` of them to a line, each with the picture or name of what it holds.
func _grid_rows(panel: Card, fields: Array, across: int) -> void:
	var grid := GridContainer.new()
	grid.columns = across * 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	for row in fields:
		var label := Label.new()
		label.theme_type_variation = &"Dim"
		label.text = _row_label(row)
		label.custom_minimum_size.x = 190
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(label)
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var spin := _monster_spin(row)
		cell.add_child(spin)
		if REFERENCE_KINDS.has(str(row.field)): shell.references.attach(cell, spin, REFERENCE_KINDS[str(row.field)])
		grid.add_child(cell)
	panel.add_row(grid)


## The five attacks, one to a line: least and most damage, sound and special attack.
func _attack_rows(panel: Card, fields: Array) -> void:
	var by_key: Dictionary = {}
	for row in fields: by_key["%s:%d" % [row.field, int(row.index)]] = row
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	for entry in [["Attack", 70], ["Least damage", 110], ["Most damage", 110], ["Sound", 150], ["Special attack", 0]]:
		var title := Label.new()
		title.theme_type_variation = &"Dim"
		title.text = entry[0]
		title.custom_minimum_size.x = entry[1]
		if int(entry[1]) == 0: title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
	panel.add_row(head)
	for index in range(5):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var number := Label.new()
		number.theme_type_variation = &"MonoDim"
		number.text = "%d" % (index + 1)
		number.custom_minimum_size.x = 70
		line.add_child(number)
		for field_name in ["attack_minimum", "attack_maximum"]:
			if by_key.has("%s:%d" % [field_name, index]): line.add_child(_monster_spin(by_key["%s:%d" % [field_name, index]]))
		if by_key.has("attack_sound:%d" % index):
			var sound := _monster_spin(by_key["attack_sound:%d" % index])
			var cell := HBoxContainer.new()
			cell.custom_minimum_size.x = 150
			cell.add_child(sound)
			shell.references.attach(cell, sound, "sound", false)
			line.add_child(cell)
		if by_key.has("attack_condition:%d" % index):
			var special := _monster_spin(by_key["attack_condition:%d" % index])
			line.add_child(special)
			shell.references.attach(line, special, "special_attack")
		panel.add_row(line)


func _monster_field(row: Dictionary, value: int) -> void:
	if loading: return
	var key := "monster_field:%d:%s:%d" % [int(id.value), row.field, int(row.index)]
	if value == int(row.value): shell.drafts.erase(key)
	else: shell.drafts[key] = {"kind": "monster_field", "id": int(id.value), "field": row.field, "index": int(row.index), "value": value}
	shell._invalidate_receipt()
	shell._update_buttons()
	_show_header("monster")
	_fill_list("monster")


var _reward_spins: Dictionary = {}


## The items of a reward, one line for each slot with its icon, name and level. The slots after the last one in use
## are folded away until another is asked for; the item and level of a slot are one draft.
func _reward_slots(panel: Card) -> void:
	_reward_spins.clear()
	var lines: Array = []
	var last := -1
	for slot in data.items:
		var number := int(slot.slot)
		if int(slot.item) > 0 or int(slot.level) != 0: last = number
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var text := Label.new()
		text.theme_type_variation = &"Dim"
		text.text = "Item %d" % (number + 1)
		text.custom_minimum_size.x = 60
		line.add_child(text)
		var item := _reward_number(int(slot.item), -32767, 999, number)
		line.add_child(item)
		shell.references.attach(line, item, "item")
		var level_label := Label.new()
		level_label.theme_type_variation = &"Dim"
		level_label.text = "Level"
		line.add_child(level_label)
		var level := _reward_number(int(slot.level), -32768, 32767, number)
		line.add_child(level)
		panel.add_row(line)
		lines.append(line)
		_reward_spins["item:%d" % number] = item
		_reward_spins["level:%d" % number] = level
		_reward_saved["item:%d" % number] = int(slot.item)
		_reward_saved["level:%d" % number] = int(slot.level)
	var shown := clampi(last + 2, 1, lines.size())
	for number in range(lines.size()): lines[number].visible = number < shown
	var more := Button.new()
	more.text = "Add another item"
	more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	more.visible = shown < lines.size()
	more.pressed.connect(func():
		shown += 1
		lines[shown - 1].visible = true
		more.visible = shown < lines.size())
	panel.add_row(more)


func _reward_number(value: int, low: int, high: int, slot: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = mini(low, value)
	spin.max_value = maxi(high, value)
	spin.set_value_no_signal(value)
	spin.custom_minimum_size.x = 110
	spin.value_changed.connect(func(_value): _reward_item_changed(slot))
	return spin


var _reward_saved: Dictionary = {}


func _reward_item_changed(slot: int) -> void:
	if loading: return
	var key := "reward_item:%d:%d" % [int(id.value), slot]
	var item := int(_reward_spins["item:%d" % slot].value)
	var level := int(_reward_spins["level:%d" % slot].value)
	if item == int(_reward_saved["item:%d" % slot]) and level == int(_reward_saved["level:%d" % slot]): shell.drafts.erase(key)
	else: shell.drafts[key] = {"kind": "reward_item", "id": int(id.value), "slot": slot, "item": item, "level": level}
	shell._invalidate_receipt()
	shell._update_buttons()
	_show_header("reward")
	_fill_list("reward")


func _plain_spin(panel: Card, label: String, key: String, value: int, low: int, high: int, kind := "") -> SpinBox:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var text := Label.new()
	text.theme_type_variation = &"Dim"
	text.text = label
	text.custom_minimum_size.x = 230
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(text)
	var spin := SpinBox.new()
	spin.min_value = mini(low, value)
	spin.max_value = maxi(high, value)
	spin.set_value_no_signal(value)
	spin.custom_minimum_size.x = 110
	spin.value_changed.connect(func(_value): _behaviour_changed())
	line.add_child(spin)
	if not kind.is_empty(): shell.references.attach(line, spin, kind)
	panel.add_row(line)
	_monster_spins[key] = spin
	return spin


## Turn story chance and story, the retreat chance and the death story: the
## monster's behaviour, each pair its own draft.
func _behaviour_fields(panel: Card) -> void:
	var behaviour: Dictionary = data.behaviour
	_plain_spin(panel, "Turn story chance, percent (negative stays)", "turn_chance", int(behaviour.turn_chance), -100, 100)
	_plain_spin(panel, "Turn story", "turn_story", int(behaviour.turn_story), 0, 32767)
	_plain_spin(panel, "Run chance, percent of stamina", "run_percent", int(behaviour.run_percent), -100, 100)
	_plain_spin(panel, "Death story (0 none)", "death_story", int(behaviour.death_story), 0, 32767)


func _spell_fields(panel: Card) -> void:
	for index in range(10): _plain_spin(panel, "Spell %d (category, level and number as one code; 1100 or less none)" % (index + 1), "spell%d" % index, int(data.spells[index]), -32768, 4777, "spell")


func _behaviour_changed() -> void:
	if loading: return
	var record_id := int(id.value)
	var saved: Dictionary = data.behaviour
	var turn := {"kind": "monster_turn_story", "id": record_id, "chance": int(_monster_spins.turn_chance.value), "story": int(_monster_spins.turn_story.value)}
	var retreat := {"kind": "monster_retreat_threshold", "id": record_id, "value": int(_monster_spins.run_percent.value)}
	var death := {"kind": "monster_death_story", "id": record_id, "story": int(_monster_spins.death_story.value)}
	var slots: Array = []
	for index in range(10): slots.append(int(_monster_spins["spell%d" % index].value))
	var spells := {"kind": "monster_spell_slots", "id": record_id, "slots": slots}
	_draft_unless("monster_turn_story:%d" % record_id, turn, int(saved.turn_chance) == turn.chance and int(saved.turn_story) == turn.story)
	_draft_unless("monster_retreat_threshold:%d" % record_id, retreat, int(saved.run_percent) == retreat.value)
	_draft_unless("monster_death_story:%d" % record_id, death, int(saved.death_story) == death.story)
	_draft_unless("monster_spell_slots:%d" % record_id, spells, data.spells.map(func(value): return int(value)) == slots)
	shell._invalidate_receipt()
	shell._update_buttons()
	_show_header("monster")
	_fill_list("monster")


func _draft_unless(key: String, draft: Dictionary, as_saved: bool) -> void:
	if as_saved: shell.drafts.erase(key)
	else: shell.drafts[key] = draft


## Puts the unapplied edits of this monster back in the fields.
func _rehydrate_monster() -> void:
	var record_id := int(id.value)
	for edit in shell.drafts.values():
		if int(edit.get("id", -1)) != record_id: continue
		match str(edit.kind):
			"monster_field":
				var spin: SpinBox = _monster_spins.get("%s:%d" % [edit.field, int(edit.index)])
				if spin != null: spin.set_value_no_signal(int(edit.value))
			"monster_description":
				if _monster_description != null and _monster_description.text != str(edit.text): _monster_description.text = str(edit.text)
			"monster_turn_story":
				_monster_spins.turn_chance.set_value_no_signal(int(edit.chance))
				_monster_spins.turn_story.set_value_no_signal(int(edit.story))
			"monster_retreat_threshold": _monster_spins.run_percent.set_value_no_signal(int(edit.value))
			"monster_death_story": _monster_spins.death_story.set_value_no_signal(int(edit.story))
			"monster_spell_slots":
				for index in range(10): _monster_spins["spell%d" % index].set_value_no_signal(int(edit.slots[index]))


## The first records that name the one in view, with a way to list them all.
func _show_used_by(f: String) -> void:
	for child in _used_rows.get_children(): _used_rows.remove_child(child); child.queue_free()
	var response: Dictionary = await shell.request_when_free({"op": "uses", "kind": f, "id": int(id.value)})
	if not response.get("ok", false): return
	var uses: Dictionary = response.result
	if int(uses.total) == 0:
		var none := Label.new()
		none.theme_type_variation = &"Dim"
		none.text = "Nothing names this record."
		_used_rows.add_child(none)
		return
	for row in uses.rows.slice(0, 5):
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var where := "%s %d" % [str(row.table), int(row.id)]
		line.text = "%s · step %d" % [where, int(row.slot) + 1] if row.has("slot") else "%s · %s" % [where, str(row.name)]
		_used_rows.add_child(line)
	var all := Button.new()
	all.text = "Find all %d uses" % int(uses.total)
	all.theme_type_variation = &"GhostButton"
	all.pressed.connect(func(): shell.find_uses(f, int(id.value)))
	_used_rows.add_child(all)


func _show_header(f: String) -> void:
	var record_id := int(id.value)
	var label := str(names.get(record_id, "")) if f == "monster" else ""
	header.mark(Tokens.FAMILY.combat if f in ["monster", "battle", "battle_extra"] else Tokens.FAMILY.reward if f == "reward" else Tokens.FAMILY.message)
	header.title.text = "%s %d%s" % [NOUNS[f], record_id, " · " + label if not label.is_empty() else ""]
	header.sub.text = geometry.text
	var badges: Array = []
	if record_id >= imported_count: badges.append(["new row", &"BadgeGood"])
	if f == "monster": badges.append(["provisional", &"BadgeDim"])
	if _has_draft(f, record_id): badges.append(["unapplied", &"BadgeWarn"])
	header.show_badges(badges)


func changed() -> void:
	if loading or data.is_empty(): return
	var f: String = data.family; var record_id := int(data.id)
	var edit := {"kind":f,"id":record_id}
	for key in controls: edit[key] = controls[key].text if controls[key] is LineEdit else int(controls[key].value)
	match f:
		"choice":
			shell.drafts["choice_prompt:%d" % record_id] = {"kind":"choice_prompt","id":record_id,"message":edit.prompt}
			for index in range(4):
				shell.drafts["choice_label:%d:%d" % [record_id,index]] = {"kind":"choice_label","id":record_id,"choice":index,"text":edit["label%d" % index]}
				shell.drafts["choice_selector:%d:%d" % [record_id,index]] = {"kind":"encounter_condition","family":"menu","id":record_id,"field":"choice_selector","index":index,"value":edit["selector%d" % index]}
		"story": return
		_:
			if f == "monster": edit.kind = "monster_stats"
			shell.drafts["%s:%d" % [edit.kind,record_id]] = edit
	shell._invalidate_receipt(); shell._update_buttons()
	_show_header(f)
	_fill_list(f)


func restore_selection() -> void:
	if not data.is_empty(): family.select(FAMILIES.find(data.family)); id.value = int(data.id)
