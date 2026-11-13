extends HBoxContainer
## The project page: open, import or start a project, the projects opened
## before, and what the selected one holds, beside the folder the editor runs
## from. Its interior is built here from the shared widgets.
const ActionCard = preload("res://src/widgets/action_card.gd")
const Card = preload("res://src/widgets/card.gd")
const CheckRow = preload("res://src/widgets/check_row.gd")
const ContentsGrid = preload("res://src/widgets/contents_grid.gd")
const Glyph = preload("res://src/widgets/glyph.gd")
const KbdButton = preload("res://src/widgets/kbd_button.gd")
const KeyValueRow = preload("res://src/widgets/key_value_row.gd")
const NoticeList = preload("res://src/widgets/notice_list.gd")
const Tokens = preload("res://theme/editor_tokens.gd")
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var shell: Control
var runtime_message := "No receipt matched to this exact export."
## The projects opened or saved before, newest first, as the settings file keeps them.
var recents: Array = []
var _selected := ""
var _group := ButtonGroup.new()
var _buttons: Dictionary = {}
var _import: ActionCard
var _open: ActionCard
var _new: ActionCard
var _filter := LineEdit.new()
var _list := VBoxContainer.new()
var _columns := HBoxContainer.new()
var _empty := Control.new()
var _selected_card := Card.new()
var _selected_name := Label.new()
var _selected_path := Label.new()
var _selected_rows := VBoxContainer.new()
var _comparison := VBoxContainer.new()
var _contents_card := Card.new()
var _contents := ContentsGrid.new()
var _notices_card := Card.new()
var _notices_count := Label.new()
var _notices := NoticeList.new()
var _history_card := Card.new()
var _history := VBoxContainer.new()
var _folder_text := Label.new()
var installation := LineEdit.new()
var _checks := VBoxContainer.new()
var _play_note := Label.new()
var _new_window: Button
var _choose_folder := Button.new()
var _open_project: KbdButton


func _init() -> void:
	_build_main()
	_build_side()


func setup(owner_shell: Control) -> void:
	shell = owner_shell
	shell.name_node("Installation", installation)
	_import.pressed.connect(func(): shell.guard(shell._import_picker, true))
	_open.pressed.connect(func(): shell.guard(shell._open_picker, true))
	_new.pressed.connect(func(): shell.guard(shell.open_new_dialog, true))
	_open_project.pressed.connect(open_selected)
	_new_window.pressed.connect(open_in_new_window)
	_choose_folder.pressed.connect(shell._pick_folder.bind("installation"))
	shell.ui("ReceiptPicker").file_selected.connect(match_receipt)


func _build_main() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 2)
	column.add_child(heading)
	var title := Label.new()
	title.theme_type_variation = &"PageTitle"
	title.text = "Open a mission pack"
	heading.add_child(title)
	var intro := Label.new()
	intro.theme_type_variation = &"Muted"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.text = "Import an extracted scenario level, or reopen a portable checkpoint. Source files and unknown bytes remain preserved."
	heading.add_child(intro)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	column.add_child(cards)
	_import = _card(cards, "ProjectImport", "Import level", "Read a New Centurions level folder into a new project. The folder itself is never changed.", "Ctrl I", "import", true)
	_open = _card(cards, "ProjectOpen", "Open checkpoint", "Reopen a saved project folder and continue editing from its last revision.", "Ctrl O", "folder", false)
	_new = _card(cards, "New", "New from template", "Start a minimal mission pack from an unchanged template, with your own stage name.", "Ctrl N", "plus", false)
	var recent_head := HBoxContainer.new()
	recent_head.custom_minimum_size.y = 36
	column.add_child(recent_head)
	var recent_title := Label.new()
	recent_title.theme_type_variation = &"CaptionMuted"
	recent_title.text = "RECENT"
	recent_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recent_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	recent_head.add_child(recent_title)
	_filter.placeholder_text = "Filter recent projects…"
	_filter.custom_minimum_size.x = 260
	_filter.clear_button_enabled = true
	_filter.text_changed.connect(func(_text): _fill())
	recent_head.add_child(_filter)
	_columns.add_theme_constant_override("separation", 12)
	_columns.add_child(_spacer(26))
	_columns.add_child(_heading("PROJECT", 0))
	_columns.add_child(_heading("ORIGIN", 132))
	_columns.add_child(_heading("EDITS", 72))
	_columns.add_child(_heading("SAVED", 150))
	_columns.add_child(_spacer(20))
	column.add_child(_columns)
	_list.add_theme_constant_override("separation", 4)
	column.add_child(_list)
	_empty.custom_minimum_size = Vector2(0, 300)
	_empty.draw.connect(_paint_empty)
	column.add_child(_empty)
	var message := VBoxContainer.new()
	message.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	message.grow_vertical = Control.GROW_DIRECTION_BOTH
	message.alignment = BoxContainer.ALIGNMENT_CENTER
	message.add_theme_constant_override("separation", 6)
	_empty.add_child(message)
	var folder := Glyph.new()
	folder.glyph = "folder"
	folder.extent = 24.0
	folder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	message.add_child(folder)
	var none := Label.new()
	none.theme_type_variation = &"Strong"
	none.text = "No project open."
	none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_child(none)
	for line in ["Choose Import level to preserve an extracted native folder, including its sidecars.", "New scenarios require an unchanged imported template."]:
		var hint := Label.new()
		hint.theme_type_variation = &"Muted"
		hint.text = line
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		message.add_child(hint)
	var note := HBoxContainer.new()
	note.add_theme_constant_override("separation", 8)
	var dot := Glyph.new()
	dot.glyph = "dot"
	dot.extent = 10.0
	dot.color = Tokens.INFO
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	note.add_child(dot)
	var words := Label.new()
	words.theme_type_variation = &"Muted"
	words.add_theme_font_size_override("font_size", 12)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.text = "Save creates a new checkpoint. Export creates a new native level folder."
	note.add_child(words)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	column.add_child(note)


func _card(parent: Control, node_name: String, title: String, body: String, key: String, glyph: String, lead: bool) -> ActionCard:
	var card := ActionCard.new()
	card.name = node_name
	card.title = title
	card.body = body
	card.key_hint = key
	card.glyph = glyph
	card.lead = lead
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	return card


func _spacer(width: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.x = width
	return spacer


func _heading(text: String, width: float) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"Caption"
	label.text = text
	if width > 0.0: label.custom_minimum_size.x = width
	else: label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _paint_empty() -> void:
	var rect := Rect2(Vector2.ZERO, _empty.size).grow(-0.5)
	var dash := 6.0
	var gap := 5.0
	for edge in [[rect.position, Vector2(rect.end.x, rect.position.y)], [Vector2(rect.position.x, rect.end.y), rect.end], [rect.position, Vector2(rect.position.x, rect.end.y)], [Vector2(rect.end.x, rect.position.y), rect.end]]:
		var along: Vector2 = (edge[1] - edge[0])
		var length := along.length()
		var step := along / length
		var at := 0.0
		while at < length:
			_empty.draw_line(edge[0] + step * at, edge[0] + step * minf(at + dash, length), Tokens.LINE2, 1.0)
			at += dash + gap


func _build_side() -> void:
	var edge := VSeparator.new()
	add_child(edge)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 468
	side.add_theme_constant_override("separation", 0)
	add_child(side)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	_selected_card.title = "Selected project"
	_selected_card.dot_color = Tokens.INFO
	column.add_child(_selected_card)
	_selected_name.theme_type_variation = &"Heading"
	_selected_card.add_row(_selected_name)
	_selected_path.theme_type_variation = &"MonoDim"
	_selected_path.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_selected_card.add_row(_selected_path)
	_selected_rows.add_theme_constant_override("separation", 6)
	_selected_card.add_row(_selected_rows)
	_comparison.add_theme_constant_override("separation", 8)
	_selected_card.add_row(_comparison)
	_contents_card.title = "Contents"
	_contents.columns = 3
	_contents_card.add_row(_contents)
	column.add_child(_contents_card)
	_notices_card.title = "Preservation"
	_notices_count.theme_type_variation = &"Dim"
	_notices_card.right.add_child(_notices_count)
	_notices_card.add_row(_notices)
	column.add_child(_notices_card)
	_history_card.title = "Checkpoint history"
	_history.add_theme_constant_override("separation", 10)
	_history_card.add_row(_history)
	column.add_child(_history_card)
	var folder := Card.new()
	folder.title = "This folder"
	folder.dot_color = Tokens.GOOD
	column.add_child(folder)
	_folder_text.theme_type_variation = &"Muted"
	_folder_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_folder_text.text = "The editor runs from the New Centurions folder. Artwork is read locally and cached separately from the project."
	folder.add_row(_folder_text)
	installation.name = "Installation"
	installation.editable = false
	installation.theme_type_variation = &"LineEditMono"
	folder.add_row(installation)
	_checks.add_theme_constant_override("separation", 8)
	folder.add_row(_checks)
	_play_note.theme_type_variation = &"Muted"
	_play_note.add_theme_font_size_override("font_size", 12)
	_play_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	folder.add_row(_play_note)
	# Run from the source tree the editor is not in the installation's folder, so
	# the folder can be pointed at once and is remembered. A package never asks.
	_choose_folder.text = "Choose folder (development)…"
	_choose_folder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_choose_folder.visible = false
	folder.add_row(_choose_folder)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	var buttons_margin := MarginContainer.new()
	buttons_margin.add_theme_constant_override("margin_left", 24)
	buttons_margin.add_theme_constant_override("margin_right", 24)
	buttons_margin.add_theme_constant_override("margin_top", 6)
	buttons_margin.add_theme_constant_override("margin_bottom", 12)
	buttons_margin.add_child(buttons)
	side.add_child(buttons_margin)
	_new_window = Button.new()
	_new_window.text = "Open in new window"
	buttons.add_child(_new_window)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_open_project = KbdButton.new()
	_open_project.text = "Open project"
	_open_project.hint = "↵"
	_open_project.theme_type_variation = &"PrimaryButton"
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	_open_project.shortcut = Shortcut.new()
	_open_project.shortcut.events = [enter]
	buttons.add_child(_open_project)
	show_projects()


## Sets the projects opened before and draws the list.
func show_recents(list: Array) -> void:
	recents = list
	if _selected.is_empty() and not recents.is_empty() and shell != null and shell.summary.is_empty(): _selected = str(recents[0].get("path", ""))
	_fill()


func _fill() -> void:
	for child in _list.get_children(): _list.remove_child(child); child.queue_free()
	_buttons.clear()
	var needle := _filter.text.strip_edges().to_lower()
	var shown := 0
	for entry in recents:
		var text := (str(entry.get("name", "")) + " " + str(entry.get("path", ""))).to_lower()
		if not needle.is_empty() and not needle in text: continue
		_list.add_child(_row(entry))
		shown += 1
	_columns.visible = shown > 0
	_list.visible = shown > 0
	_empty.visible = recents.is_empty()
	_new.set_available(not recents.is_empty() or (shell != null and not shell.summary.is_empty()))
	show_projects()


func _row(entry: Dictionary) -> Button:
	var path := str(entry.get("path", ""))
	var row := Button.new()
	row.theme_type_variation = &"RowButton"
	row.toggle_mode = true
	row.button_group = _group
	row.custom_minimum_size = Vector2(0, 52)
	row.set_pressed_no_signal(_norm(path) == _norm(_selected))
	row.pressed.connect(func(): _selected = path; show_projects())
	row.gui_input.connect(func(event): if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT: _selected = path; open_selected())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	row.add_child(margin)
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 12)
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(cells)
	var imported: bool = entry.get("origin", "") == "imported"
	var dot := Glyph.new()
	dot.glyph = "dot"
	dot.extent = 14.0
	dot.color = Tokens.INFO if imported else Tokens.FAMILY.encounter
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cells.add_child(dot)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cells.add_child(words)
	var name := Label.new()
	name.theme_type_variation = &"Strong"
	name.text = str(entry.get("name", ""))
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(name)
	var where := Label.new()
	where.theme_type_variation = &"MonoDim"
	where.text = path.replace("/", "\\")
	where.clip_text = true
	where.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	where.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(where)
	var origin_box := Control.new()
	origin_box.custom_minimum_size.x = 132
	origin_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cells.add_child(origin_box)
	var badge := Label.new()
	badge.theme_type_variation = &"Badge" if imported else &"BadgeEncounter"
	badge.text = "imported level" if imported else "minimal template"
	badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	origin_box.add_child(badge)
	var edits := Label.new()
	edits.theme_type_variation = &"Mono"
	edits.custom_minimum_size.x = 72
	edits.text = edits_text(int(entry.get("edits", 0)))
	edits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cells.add_child(edits)
	var saved := Label.new()
	saved.theme_type_variation = &"MonoDim"
	saved.custom_minimum_size.x = 150
	saved.text = saved_text(int(entry.get("saved", 0)))
	saved.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cells.add_child(saved)
	var chevron := Glyph.new()
	chevron.glyph = "chevron_right"
	chevron.extent = 14.0
	chevron.color = Tokens.DIM
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cells.add_child(chevron)
	_buttons[path] = row
	return row


## A project folder's path in one spelling, so two names for it compare equal.
static func _norm(path: String) -> String:
	return path.replace("\\\\?\\", "").replace("\\", "/").trim_suffix("/")


static func edits_text(count: int) -> String:
	return "%d edit" % count if count == 1 else "%d edits" % count


static func saved_text(unix: int) -> String:
	if unix <= 0: return ""
	var local := unix + int(Time.get_time_zone_from_system().bias) * 60
	var when := Time.get_datetime_dict_from_unix_time(local)
	return "%02d %s %d, %02d:%02d" % [when.day, MONTHS[int(when.month) - 1], when.year, when.hour, when.minute]


## What the details show for a project: the open one as the adapter sees it
## now, or an earlier one as the settings file recorded it.
func _details(path: String) -> Dictionary:
	if shell != null and not shell.summary.is_empty() and _norm(str(shell.summary.path)) == _norm(path):
		var summary: Dictionary = shell.summary
		var native: Variant = summary.get("native")
		return {"name": str(native.get("name", "")) if native is Dictionary else str(summary.get("origin", {}).get("label", "")), "path": path,
			"origin": str(summary.get("origin", {}).get("kind", "")), "version": int(summary.get("version", 0)), "source_files": int(summary.source_files),
			"edits": int(summary.get("edits", 0)), "contents": summary.get("contents", {}), "notices": summary.get("warnings", []), "open": true}
	for entry in recents:
		if _norm(str(entry.get("path", ""))) == _norm(path):
			var known: Dictionary = entry.duplicate()
			known["open"] = false
			return known
	return {}


## Shows the selected project's facts, contents and notices.
func show_projects() -> void:
	if _selected.is_empty() and shell != null and not shell.summary.is_empty():
		_selected = str(shell.summary.path).replace("\\\\?\\", "")
	var details := _details(_selected)
	var has := not details.is_empty()
	for card in [_selected_card, _contents_card, _notices_card]: card.visible = has
	_history_card.visible = false
	_open_project.disabled = not has
	_new_window.disabled = not has
	for path in _buttons: _buttons[path].set_pressed_no_signal(_norm(path) == _norm(_selected))
	if not has: return
	_selected_name.text = str(details.get("name", ""))
	_selected_path.text = str(details.path).replace("/", "\\")
	for child in _selected_rows.get_children(): _selected_rows.remove_child(child); child.queue_free()
	var imported: bool = details.get("origin", "") == "imported"
	var header := str(details.get("name", ""))
	for pair in [["Origin", "Imported level" if imported else "Template-derived scenario"], ["Format", "Project version %d" % int(details.get("version", 0))],
			["Source files", "%d preserved" % int(details.get("source_files", 0))], ["Edits", "%d since import" % int(details.get("edits", 0))], ["Startup header", header]]:
		var row := KeyValueRow.new()
		row.key = pair[0]
		row.value = pair[1]
		_selected_rows.add_child(row)
	_contents.show_contents(details.get("contents", {}))
	var notices: Array = details.get("notices", [])
	_notices_count.text = "%d notice%s" % [notices.size(), "" if notices.size() == 1 else "s"]
	_notices.show_notices(notices)
	_show_comparison(str(details.path))
	_show_history(details)
	_open_project.text = "Open project" if not details.get("open", false) else "Reopen project"


## The reopen comparison a verification run left beside the checkpoint.
func _show_comparison(path: String) -> void:
	for child in _comparison.get_children(): _comparison.remove_child(child); child.queue_free()
	for candidate in [path.path_join("receipt.json"), path.get_base_dir().path_join("receipt.json")]:
		if not FileAccess.file_exists(candidate): continue
		var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate))
		if not receipt is Dictionary or receipt.get("status", "") != "passed": continue
		var rows: Array = []
		for check in [["independent_complete_byte_comparison", "GUI and CLI exports are equal in every byte", "%d files" % int(receipt.get("files", 0))],
				["input_checkpoint_unchanged", "The input checkpoint is unchanged", "passed"], ["input_export_unchanged", "The input export is unchanged", "passed"]]:
			if not receipt.has(check[0]): continue
			var row := CheckRow.new()
			row.text = check[1]
			row.state = "good" if receipt[check[0]] else "err"
			row.note = check[2] if receipt[check[0]] else "failed"
			rows.append(row)
		if rows.is_empty(): continue
		var title := Label.new()
		title.theme_type_variation = &"CaptionMuted"
		title.text = "REOPEN COMPARISON · RECEIPT.JSON"
		_comparison.add_child(title)
		for row in rows: _comparison.add_child(row)
		break
	_comparison.visible = _comparison.get_child_count() > 0


## Earlier checkpoints of the same scenario, oldest first.
func _show_history(details: Dictionary) -> void:
	for child in _history.get_children(): _history.remove_child(child); child.queue_free()
	var same := recents.filter(func(entry): return str(entry.get("name", "")) == str(details.get("name", ""))).duplicate()
	same.sort_custom(func(a, b): return int(a.get("saved", 0)) < int(b.get("saved", 0)))
	_history_card.visible = same.size() > 1
	for entry in same:
		var imported: bool = entry.get("origin", "") == "imported"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var dot := Glyph.new()
		dot.glyph = "dot"
		dot.extent = 12.0
		dot.color = Tokens.ACCENT if str(entry.get("path", "")) == str(details.get("path", "")) else Tokens.DIM
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		dot.custom_minimum_size.y = 18
		row.add_child(dot)
		var words := VBoxContainer.new()
		words.add_theme_constant_override("separation", 0)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		var name := Label.new()
		name.theme_type_variation = &"Strong"
		name.text = str(entry.get("name", ""))
		head.add_child(name)
		var badge := Label.new()
		badge.theme_type_variation = &"Badge" if imported else &"BadgeEncounter"
		badge.text = "imported" if imported else "template"
		head.add_child(badge)
		words.add_child(head)
		var where := Label.new()
		where.theme_type_variation = &"MonoDim"
		where.text = str(entry.get("path", "")).get_file()
		words.add_child(where)
		var edits := Label.new()
		edits.theme_type_variation = &"MonoDim"
		edits.text = edits_text(int(entry.get("edits", 0))) + " · " + str(int(entry.get("source_files", 0))) + " files"
		words.add_child(edits)
		row.add_child(words)
		_history.add_child(row)


## The folder the editor found and what it holds.
func show_folder(folder: String, report: Array) -> void:
	installation.text = folder.replace("/", "\\")
	_choose_folder.visible = folder.is_empty() and not OS.has_feature("template")
	for child in _checks.get_children(): _checks.remove_child(child); child.queue_free()
	for entry in report:
		var check := CheckRow.new()
		check.text = entry.label
		check.state = entry.state
		check.note = entry.note
		_checks.add_child(check)
	_play_note.text = shell.folder_play_note
	_play_note.visible = not _play_note.text.is_empty()


func open_selected() -> void:
	if _selected.is_empty() or shell.modal_open(): return
	var path := _selected
	shell.guard(func(): await shell.open_project(path), true)


## Starts another editor window on the selected project.
func open_in_new_window() -> void:
	if _selected.is_empty(): return
	var started := OS.create_instance(PackedStringArray(["--", "--project=" + _selected]))
	if started < 0: shell.status("Could not open a new window")


## A checkpoint pick by path, from the recent list or a menu.
func choose(path: String) -> void:
	_selected = path
	show_projects()


func choose_receipt() -> void:
	shell.ui("ReceiptPicker").popup_centered(Vector2i(900, 600))


## Describes the open checkpoint and forgets any matched receipt.
func show_summary(summary: Dictionary) -> void:
	_selected = str(summary.get("path", "")).replace("\\\\?\\", "")
	show_projects()


func _set_runtime(text: String) -> void:
	runtime_message = text
	shell.ui("RuntimeStatus").text = text


func forget_receipt() -> void:
	_set_runtime("No receipt matched to this exact export.")


## A receipt speaks for one exact export, so pending edits end its match.
func invalidate_receipt() -> void:
	_set_runtime("Edits are pending · match a validation receipt after applying them.")


func match_receipt(path: String) -> void:
	var response: Dictionary = await shell.request_backend({"op": "check_receipt", "path": path})
	if response.get("ok", false):
		var result: Dictionary = response.result
		_set_runtime(("Exact export match · Startup: %s · Prologue: %s\n%s" % [result.startup_status, result.prologue_status, result.get("limitation", "")]) if result.matched else "Receipt does not match this exact export. Startup remains unverified for the current edits.")


## The detected folder is remembered so a later launch finds its artwork even
## when it is started from elsewhere.
func remember_installation() -> void:
	var response: Dictionary = await shell.request_backend({"op": "set_installation", "path": installation.text})
	if response.get("ok", false):
		installation.text = str(response.result.installation).replace("/", "\\")
		await shell.load_artwork()
		shell.status("Local installation remembered for subsequent launches")
