extends HBoxContainer
## Messages: the rows of the message table, searched by text, one text edited
## with its Mac Roman byte count and how it reads in the game, and a find and
## replace that drafts the changes.
const Card = preload("res://src/widgets/card.gd")
const PageHeader = preload("res://src/widgets/page_header.gd")
const RecordList = preload("res://src/widgets/record_list.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

const LIMIT := 255

var shell: Control
var message_id := -1
var rows: Array = []
var offset := 0
var total := 0
var query := ""
var list := RecordList.new()
var _text := TextEdit.new()
var _timer := Timer.new()
var _bytes := Label.new()
var _used := ProgressBar.new()
var _left := Label.new()
var _tokens := Label.new()
var header := PageHeader.new()
var _foot := Label.new()
var _previous := Button.new()
var _next := Button.new()
var _neighbours := VBoxContainer.new()
var _find := LineEdit.new()
var _replace := LineEdit.new()
var _match_case := CheckBox.new()
var _draft_button := Button.new()
var _find_count := Label.new()
var _search_timer := Timer.new()


func _init() -> void:
	add_theme_constant_override("separation", 12)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 330
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	list.title = "Messages"
	list.filter_placeholder = "Search text or ^ token…"
	list.filter_locally = false
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.set_columns([{"title": "ID", "width": 52, "mono": true}, {"title": "Text", "width": 0}])
	list.set_scopes([{"id": "all", "label": "All"}, {"id": "token", "label": "Has ^1"}])
	list.row_selected.connect(func(id): if id != null: shell.guard(load_message.bind(int(id))))
	list.filter_changed.connect(func(text): query = text; _search_timer.start())
	list.scope_changed.connect(func(id): query = "^1" if str(id) == "token" else ""; shell.guard(list_messages.bind(0)))
	left.add_child(list)
	var pager := HBoxContainer.new()
	pager.add_theme_constant_override("separation", 6)
	_foot.theme_type_variation = &"Dim"
	_foot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pager.add_child(_foot)
	_previous.text = "‹"
	_previous.pressed.connect(func(): shell.guard(list_messages.bind(maxi(0, offset - 128))))
	pager.add_child(_previous)
	_next.text = "›"
	_next.pressed.connect(func(): shell.guard(list_messages.bind(offset + 128)))
	pager.add_child(_next)
	left.add_child(pager)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 12)
	scroll.add_child(centre)
	centre.add_child(_header())
	var text_card := Card.new()
	text_card.title = "Text"
	_bytes.theme_type_variation = &"MonoDim"
	text_card.right.add_child(_bytes)
	centre.add_child(text_card)
	_text.custom_minimum_size.y = 120
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_card.add_row(_text)
	var meter := HBoxContainer.new()
	meter.add_theme_constant_override("separation", 10)
	_used.show_percentage = false
	_used.max_value = LIMIT
	_used.custom_minimum_size = Vector2(160, 6)
	_used.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.add_child(_used)
	_left.theme_type_variation = &"Dim"
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.add_child(_left)
	_tokens.theme_type_variation = &"Dim"
	meter.add_child(_tokens)
	text_card.add_row(meter)
	var note := Label.new()
	note.theme_type_variation = &"Dim"
	note.add_theme_font_size_override("font_size", 12)
	note.text = "Text is stored as Mac Roman in a %d-byte record. Only the length and new text bytes are edited; unused suffix bytes remain intact." % LIMIT
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	centre.add_child(note)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 270
	side.add_theme_constant_override("separation", 12)
	add_child(side)
	var neighbours := Card.new()
	neighbours.title = "Neighbours"
	_neighbours.add_theme_constant_override("separation", 6)
	neighbours.add_row(_neighbours)
	side.add_child(neighbours)
	side.add_child(_find_card())
	_text.name = "MessageText"
	_timer.name = "TextCheckTimer"
	_timer.one_shot = true
	_timer.wait_time = 0.35
	add_child(_timer)
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.3
	add_child(_search_timer)


func _header() -> Control:
	header.mark(Tokens.FAMILY.message)
	header.show_badges([["message", &"BadgeDim"], ["authorable", &"BadgeGood"]])
	header.add_button("Callers").pressed.connect(func(): shell.find_uses("message", message_id))
	header.add_button("Duplicate", "Messages are added from Author records")
	return header


func _find_card() -> Control:
	var card := Card.new()
	card.title = "Find and replace"
	var find_title := Label.new()
	find_title.theme_type_variation = &"Caption"
	find_title.text = "FIND"
	card.add_row(find_title)
	_find.placeholder_text = "Text to find"
	card.add_row(_find)
	_find_count.theme_type_variation = &"Dim"
	card.add_row(_find_count)
	var replace_title := Label.new()
	replace_title.theme_type_variation = &"Caption"
	replace_title.text = "REPLACE WITH"
	card.add_row(replace_title)
	_replace.placeholder_text = "Replacement"
	card.add_row(_replace)
	var options := HBoxContainer.new()
	_match_case.text = "Match case"
	_match_case.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_child(_match_case)
	_draft_button.text = "Draft changes"
	options.add_child(_draft_button)
	card.add_row(options)
	var note := Label.new()
	note.theme_type_variation = &"Dim"
	note.add_theme_font_size_override("font_size", 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Replacements are checked against each message's %d-byte budget before they are drafted." % LIMIT
	card.add_row(note)
	return card


func setup(owner_shell: Control) -> void:
	shell = owner_shell
	for entry in [["MessageText", _text], ["TextCheckTimer", _timer], ["MessageBytes", _bytes]]: shell.name_node(entry[0], entry[1])
	_text.text_changed.connect(changed)
	_timer.timeout.connect(check_text)
	_search_timer.timeout.connect(func(): shell.guard(list_messages.bind(0)))
	_find.text_changed.connect(func(_text): _count_matches())
	_match_case.toggled.connect(func(_on): _count_matches())
	_draft_button.pressed.connect(func(): shell.guard(draft_replacements))


## Forgets the listed rows when another project takes the editor's place.
func forget(first_page: bool) -> void:
	message_id = -1
	rows.clear()
	if first_page: offset = 0


func list_messages(start: int) -> void:
	var response: Dictionary = await shell.request_backend({"op": "messages", "offset": start, "limit": 128, "query": query})
	if not response.get("ok", false): return
	rows = response.result.rows
	offset = start
	total = int(response.result.total)
	var shown: Array = []
	for row in rows: shown.append({"id": int(row.id), "cells": ["%d" % int(row.id), str(row.text).replace("\n", " ").left(70) if str(row.text) != "" else "empty record"], "dirty": shell.drafts.has("message:%d" % int(row.id))})
	list.set_rows(shown)
	list.set_count(total)
	_foot.text = "%d–%d of %d" % [mini(start + 1, total), mini(start + rows.size(), total), total]
	_previous.disabled = start == 0
	_next.disabled = start + 128 >= total
	if not rows.is_empty(): await select_message(0)
	else:
		message_id = -1
		shell._loading = true
		_text.text = ""
		shell._loading = false


func search() -> void:
	await list_messages(0)


func select_message(index: int) -> void:
	if index < rows.size():
		list.select(int(rows[index].id))
		await load_message(int(rows[index].id))


func load_message(id: int) -> void:
	var response: Dictionary = await shell.request_backend({"op": "message", "id": id})
	if not response.get("ok", false): return
	message_id = id
	shell._loading = true
	_text.text = shell.drafts.get("message:%d" % id, {}).get("text", response.result.text)
	_text.set_meta("saved_text", response.result.text)
	header.title.text = "Message %d" % id
	header.sub.text = "Message table SD2 · record %d · 256-byte record, %d bytes of text" % [id, LIMIT]
	shell._loading = false
	list.select(id)
	_show_text()
	_show_neighbours()
	_timer.start()


func _show_text() -> void:
	var tokens: Array = []
	if "^1" in _text.text: tokens.append("^1  team leader's name")
	_tokens.text = " · ".join(tokens)


## The rows just before and after the open one in the list.
func _show_neighbours() -> void:
	for child in _neighbours.get_children(): _neighbours.remove_child(child); child.queue_free()
	for index in range(rows.size()):
		if int(rows[index].id) != message_id: continue
		for step in [-1, 1]:
			var at: int = index + step
			if at < 0 or at >= rows.size(): continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var number := Label.new()
			number.theme_type_variation = &"MonoDim"
			number.text = str(int(rows[at].id))
			row.add_child(number)
			var words := Label.new()
			words.text = str(rows[at].text).replace("\n", " ").left(34) if str(rows[at].text) != "" else "Empty record"
			words.theme_type_variation = &"Muted"
			words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			words.clip_text = true
			row.add_child(words)
			var go := Button.new()
			go.text = "Open"
			go.theme_type_variation = &"GhostButton"
			go.pressed.connect(func(): shell.guard(select_message.bind(at)))
			row.add_child(go)
			_neighbours.add_child(row)


## Drafts the text when it differs from the saved row.
func changed() -> void:
	if shell._loading or message_id < 0: return
	var text: String = _text.text
	var key := "message:%d" % message_id
	if text == _text.get_meta("saved_text", ""): shell.drafts.erase(key)
	else: shell.drafts[key] = {"kind": "message", "id": message_id, "text": text}
	if not shell.drafts.is_empty(): shell._invalidate_receipt()
	_show_text()
	_timer.start()
	shell._update_buttons()


func check_text() -> void:
	if shell.bridge.busy or shell.bridge.requires_reopen: return
	var text: String = _text.text
	var response: Dictionary = await shell.request_backend({"op": "text_check", "text": text})
	if not response.get("ok", false) or _text.text != text: return
	var result: Dictionary = response.result
	var count := int(result.get("encoded_bytes", 0))
	var valid: bool = result.get("valid", false)
	_bytes.text = "%s / %d bytes · Mac Roman%s" % [str(count) if result.has("encoded_bytes") else "?", LIMIT, "" if valid else " · " + str(result.get("error", "Text is too long"))]
	_bytes.add_theme_color_override("font_color", Tokens.ERR if not valid else Tokens.DIM)
	_used.value = mini(count, LIMIT)
	_left.text = "%d bytes left" % (LIMIT - count) if valid else "%d bytes over" % maxi(0, count - LIMIT)


## Puts the list's mark back on the message being edited.
func restore_selection() -> void:
	if message_id >= 0: list.select(message_id)


# ── find and replace ──

func _count_matches() -> void:
	var needle := _find.text
	_find_count.text = "" if needle.is_empty() else "%d on this page" % _matching().size()


## The listed rows whose text holds the text to find.
func _matching() -> Array:
	var needle := _find.text
	var found: Array = []
	if needle.is_empty(): return found
	for row in rows:
		var text := str(shell.drafts.get("message:%d" % int(row.id), {}).get("text", row.text))
		if (needle in text) if _match_case.button_pressed else (needle.to_lower() in text.to_lower()): found.append(row)
	return found


## Drafts the replacement in every listed row that holds the text, leaving out
## any that would pass the byte budget.
func draft_replacements() -> void:
	var needle := _find.text
	if needle.is_empty(): return
	var changed_count := 0
	var refused := 0
	for row in _matching():
		var id := int(row.id)
		var current := str(shell.drafts.get("message:%d" % id, {}).get("text", row.text))
		var replaced := current.replace(needle, _replace.text) if _match_case.button_pressed else _replace_any_case(current, needle, _replace.text)
		if replaced == current: continue
		var check: Dictionary = await shell.request_backend({"op": "text_check", "text": replaced})
		if not check.get("ok", false) or not check.result.get("valid", false): refused += 1; continue
		shell.drafts["message:%d" % id] = {"kind": "message", "id": id, "text": replaced}
		changed_count += 1
	shell._invalidate_receipt()
	shell._update_buttons()
	if message_id >= 0: await load_message(message_id)
	shell.status("%d message%s drafted%s · Apply edits" % [changed_count, "" if changed_count == 1 else "s", (" · %d left out for the byte budget" % refused) if refused > 0 else ""], "warn")


static func _replace_any_case(text: String, needle: String, with: String) -> String:
	var out := ""
	var lower := text.to_lower()
	var target := needle.to_lower()
	var at := 0
	while true:
		var found := lower.find(target, at)
		if found < 0: break
		out += text.substr(at, found - at) + with
		at = found + needle.length()
	return out + text.substr(at)
