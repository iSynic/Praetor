extends RefCounted
## The monster vault on the Monsters page: the monsters kept beside the editor, shared by every scenario. A scenario brings
## its own monsters (the game reads them from the scenario's files), so a scenario is filled from the vault, and a monster
## of any scenario is added to it. The store and the copy are in Rust (`vault.rs`); this is the page's side of them.
const Card = preload("res://src/widgets/card.gd")
const ConfirmDialog = preload("res://src/widgets/confirm_dialog.gd")
const Prose = preload("res://src/widgets/prose.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

const ICON_NOTES := {
	"imported": "Icon %d is not in this scenario or the game: its picture is imported with the monster.",
	"renumbered": "Another picture already has icon %d here: the monster takes the next free number and its picture comes with it.",
	"present": "Icon %d is already in this scenario.",
	"game": "Icon %d is one the game or the scenario provides.",
}

## The record editor owns the vault, so the vault holds it weakly: a strong hold both ways would never be freed.
var editor:
	get: return _owner.get_ref()
var shell: Control
var _owner: WeakRef
## Whether the page shows the vault instead of the scenario's monsters.
var active := false
var entries: Array = []
## The keys of the entries chosen in the list.
var selected: Array = []
var removing := ConfirmDialog.new()
var _add: Button
var _add_all: Button
var _columns_for := ""
var _populate: MenuButton
var _populate_sources: Array = []
var _copy: Button
var _remove: Button
var _pending_removal: Array = []


func _init(owner_editor) -> void:
	_owner = weakref(owner_editor)
	shell = owner_editor.shell


## Puts the vault's buttons in the page's header, beside Callers and Duplicate.
func attach(header) -> void:
	_add = header.add_button("Add to vault")
	_add.tooltip_text = "Keep this monster in the vault, so any scenario can be filled from it"
	_add.pressed.connect(func(): shell.guard(add_current))
	_add_all = header.add_button("Add all to vault")
	_add_all.tooltip_text = "Keep every named monster of this scenario in the vault; ones already there are skipped"
	_add_all.pressed.connect(func(): shell.guard(add_all))
	removing.name = "RemoveFromVaultDialog"
	removing.tone = "err"
	removing.custom_action.connect(func(action): if action == "remove": shell.guard(_remove_now))
	shell.add_child(removing)


func _installation() -> String:
	return shell.ui("Installation").text


## The page's scope chips: the scenario's monsters or the vault. Other families have none.
func sync(family_name: String) -> void:
	var monster: bool = family_name == "monster"
	if not monster: active = false
	var list = editor.list
	if monster:
		list.set_scopes([{"id": "scenario", "label": "Scenario", "count": editor.count}, {"id": "vault", "label": "Vault", "count": entries.size()}])
		list.press_scope(1 if active else 0)
	else:
		list.set_scopes([])
	list.multi = active
	var mode := "vault" if active else "scenario"
	if _columns_for != mode:
		_columns_for = mode
		if active: list.set_columns([{"title": "#", "width": 40, "mono": true}, {"title": "Name", "width": 0}, {"title": "Kind", "width": 56, "mono": true}, {"title": "In", "width": 30, "mono": true}])
		else: list.set_columns([{"title": "ID", "width": 52, "mono": true}, {"title": "Name", "width": 0}])
	editor.callers_button.visible = not active
	editor._used_by.visible = not active
	editor.duplicate_button.visible = not active
	_add.visible = monster and not active
	_add_all.visible = monster and not active


func set_scope(scope: String) -> void:
	active = scope == "vault"
	selected.clear()
	await editor.refresh()


## Reads the vault from the adapter.
func load_entries() -> void:
	var response: Dictionary = await shell.request_when_free({"op": "vault_list", "installation": _installation()})
	if response.get("ok", false): entries = response.result.entries
	else: shell.status(shell._error(response), "warn")


func select(ids: Array) -> void:
	selected = ids
	if active: shell.guard(editor.refresh)


## The vault in the list and its preview in the form.
func build(rows: VBoxContainer) -> void:
	await load_entries()
	var list = editor.list
	var shown: Array = []
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		shown.append({"id": str(entry.key), "cells": [str(index + 1), str(entry.name), "stock" if entry.stock else "added", "✓" if entry.in_scenario else ""]})
	list.title = "Vault"
	list.set_rows(shown)
	list.set_count(entries.size())
	selected = selected.filter(func(key): return entries.any(func(entry): return entry.key == key))
	list.set_scopes([{"id": "scenario", "label": "Scenario", "count": editor.count}, {"id": "vault", "label": "Vault", "count": entries.size()}])
	list.press_scope(1)
	list.select_many(selected)
	var header = editor.header
	header.mark(Tokens.FAMILY.combat)
	header.title.text = "Monster vault"
	var stock_count := entries.filter(func(entry): return entry.stock).size()
	header.sub.text = "%d stock monsters of the game's own scenarios and %d added by you, shared by every scenario · ✓ marks one the scenario already holds" % [stock_count, entries.size() - stock_count]
	header.show_badges([])
	_actions(rows)
	if selected.size() == 1: _preview(rows, _entry(str(selected[0])))
	elif selected.size() > 1: _several(rows)
	else: _empty(rows)


func _entry(key: String) -> Dictionary:
	for entry in entries:
		if entry.key == key: return entry
	return {}


func _actions(rows: VBoxContainer) -> void:
	var card := Card.new()
	card.title = "Copy and keep"
	rows.add_child(card)
	var line := HFlowContainer.new()
	line.add_theme_constant_override("h_separation", 8)
	line.add_theme_constant_override("v_separation", 6)
	_copy = Button.new()
	_copy.text = "Copy %d to scenario" % selected.size() if selected.size() > 0 else "Copy to scenario"
	_copy.disabled = selected.is_empty()
	_copy.theme_type_variation = &"PrimaryButton"
	_copy.pressed.connect(func(): shell.guard(copy_to_scenario.bind(selected.duplicate())))
	line.add_child(_copy)
	_populate = MenuButton.new()
	_populate.text = "Populate scenario…"
	_populate.theme_type_variation = &"Chip"
	_populate.disabled = entries.is_empty()
	var popup := _populate.get_popup()
	popup.clear()
	_populate_sources.clear()
	var missing := entries.filter(func(entry): return not entry.in_scenario)
	popup.add_item("Every vault monster the scenario lacks (%d)" % missing.size(), 0)
	popup.set_item_disabled(0, missing.is_empty())
	var sources: Array = []
	for entry in entries:
		var scenario := str(entry.source).split(" · monster")[0]
		if scenario not in sources: sources.append(scenario)
	for index in range(sources.size()):
		var lacking := missing.filter(func(entry): return str(entry.source).begins_with(str(sources[index]) + " · monster")).size()
		popup.add_item("From %s (%d new)" % [sources[index], lacking], index + 1)
		popup.set_item_disabled(popup.get_item_index(index + 1), lacking == 0)
		_populate_sources.append(sources[index])
	popup.id_pressed.connect(func(item): shell.guard(populate.bind(item)))
	line.add_child(_populate)
	_remove = Button.new()
	_remove.text = "Remove from vault"
	_remove.disabled = selected.is_empty() or _any_stock(selected)
	_remove.tooltip_text = "Stock monsters come from the game's own scenarios and stay in the vault" if _any_stock(selected) else "Take the chosen monsters out of the vault"
	_remove.pressed.connect(func(): _ask_removal(selected.duplicate()))
	line.add_child(_remove)
	card.add_row(line)
	var note := Prose.new()
	note.show_markup("A copy is added after the scenario's last monster, with the monster's fields and description. Its spells, drops and stories name records by number, so check them in the new monster.")
	card.add_row(note)


func _empty(rows: VBoxContainer) -> void:
	var card := Card.new()
	card.title = "Vault"
	rows.add_child(card)
	var words := Prose.new()
	words.show_markup("Choose a monster in the list to see it, or hold Ctrl or Shift to choose several. **Stock** monsters are those of the game's own scenarios and stay in the vault. To keep more, open **Scenario**, select a monster and press **Add to vault**, or **Add all to vault**; only monsters that were added can be removed.")
	card.add_row(words)


func _several(rows: VBoxContainer) -> void:
	var card := Card.new()
	card.title = "%d monsters chosen" % selected.size()
	rows.add_child(card)
	for key in selected:
		var entry := _entry(str(key))
		var words := Label.new()
		words.text = "%s · %s" % [entry.get("name", ""), entry.get("source", "")]
		card.add_row(words)


func _preview(rows: VBoxContainer, entry: Dictionary) -> void:
	if entry.is_empty(): return
	var card := Card.new()
	card.title = "Vault entry"
	rows.add_child(card)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(64, 64)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if entry.get("icon_image") != null:
		var image: Image = Image.load_from_file(str(entry.icon_image).replace("\\\\?\\", ""))
		if image != null: art.texture = ImageTexture.create_from_image(image)
	top.add_child(art)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name := Label.new()
	name.theme_type_variation = &"Heading"
	name.add_theme_font_size_override("font_size", 20)
	name.text = str(entry.name)
	words.add_child(name)
	var from := Label.new()
	from.theme_type_variation = &"Dim"
	from.text = "%s · stock monster of the game, always in the vault" % entry.source if entry.stock else "%s · added %s" % [entry.source, entry.added]
	words.add_child(from)
	top.add_child(words)
	card.add_row(top)
	var does := Card.new()
	does.title = "What copying does"
	rows.add_child(does)
	var first := Prose.new()
	first.show_markup("Adds a new monster after the last one (monster %d) with these fields and this description." % editor.count)
	does.add_row(first)
	if int(entry.icon) > 0:
		var icon_note := Prose.new()
		icon_note.show_markup(ICON_NOTES.get(str(entry.icon_state), "") % int(entry.icon))
		does.add_row(icon_note)
	if entry.in_scenario:
		var held := Prose.new()
		held.show_markup("The scenario already holds a monster with these fields; a copy would be a second one.")
		does.add_row(held)
	var description := Card.new()
	description.title = "Description"
	rows.add_child(description)
	var text := Prose.new()
	text.show_markup(str(entry.description) if not str(entry.description).is_empty() else "No description.")
	description.add_row(text)
	var facts := Card.new()
	facts.title = "Body"
	rows.add_child(facts)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	for field in entry.fields:
		if str(field.group) != "Body": continue
		var label := Label.new()
		label.theme_type_variation = &"Dim"
		label.text = str(field.label)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 200
		grid.add_child(label)
		var value := Label.new()
		value.theme_type_variation = &"Mono"
		value.text = str(int(field.value))
		grid.add_child(value)
	facts.add_row(grid)


# ── what the buttons do ──

func add_current() -> void:
	await _add_ids([int(editor.id.value)])


func add_all() -> void:
	await _add_ids(range(editor.count))


func _add_ids(ids: Array) -> void:
	var response: Dictionary = await shell.request_backend({"op": "vault_add", "ids": ids, "installation": _installation()})
	if not response.get("ok", false):
		shell.status(shell._error(response), "err")
		return
	var added := int(response.result.added)
	var skipped := int(response.result.skipped)
	shell.status("Added %d to the vault%s · %d in the vault" % [added, " · %d already there or empty" % skipped if skipped > 0 else "", int(response.result.count)], "good" if added > 0 else "warn")
	await load_entries()
	sync("monster")


## Copies vault monsters into the scenario as new monsters after the last; one undo step.
func copy_to_scenario(keys: Array) -> void:
	if keys.is_empty(): return
	var response: Dictionary = await shell.request_backend({"op": "vault_copy", "expected_revision": shell.bridge.revision, "keys": keys, "installation": _installation()})
	if not response.get("ok", false):
		shell.status(shell._error(response), "err")
		return
	await shell._set_summary(response.result.summary)
	var ids: Array = response.result.ids
	shell.status("Copied %d to the scenario as monsters %d to %d · one undo step" % [ids.size(), int(ids[0]), int(ids[ids.size() - 1])], "good")
	active = false
	selected.clear()
	editor.id.value = int(ids[0])
	await editor.refresh()


func populate(item: int) -> void:
	var keys: Array = []
	for entry in entries:
		if entry.in_scenario: continue
		if item > 0 and not str(entry.source).begins_with(str(_populate_sources[item - 1]) + " · monster"): continue
		keys.append(entry.key)
	await copy_to_scenario(keys)


func _any_stock(keys: Array) -> bool:
	return keys.any(func(key): return bool(_entry(str(key)).get("stock", false)))


func _ask_removal(keys: Array) -> void:
	if keys.is_empty(): return
	if _any_stock(keys):
		shell.status("A stock monster stays in the vault; only monsters that were added can be removed", "warn")
		return
	_pending_removal = keys
	removing.clear_buttons()
	removing.heading = "Remove %d from the vault?" % keys.size()
	removing.message = "The monsters leave the vault for every scenario. Scenarios that already hold copies keep them."
	removing.set_details(keys.slice(0, 8).map(func(key): return ["", str(_entry(str(key)).get("name", ""))]))
	removing.set_note("" if keys.size() <= 8 else "%d more are not listed." % (keys.size() - 8))
	removing.add_button("Remove", "danger", "remove")
	removing.add_button("Keep", "primary", "cancel")
	removing.popup_centered()


func _remove_now() -> void:
	var response: Dictionary = await shell.request_backend({"op": "vault_remove", "keys": _pending_removal})
	if not response.get("ok", false):
		shell.status(shell._error(response), "err")
		return
	selected.clear()
	shell.status("Removed %d from the vault · %d left" % [int(response.result.removed), int(response.result.count)], "good")
	await editor.refresh()
