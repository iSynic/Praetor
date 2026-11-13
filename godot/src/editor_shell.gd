extends Control
## The editor shell. It owns the adapter session, the unapplied edits and the
## guards around them, and routes between the pages. The header, workspace
## rail, record tabs, Problems dock and status bar are its parts; each page is
## its own scene under src/pages, and the project flows' dialogs are built by
## shell/project_flows.gd.
signal startup_completed

const References = preload("res://src/services/references.gd")
const Bridge = preload("res://src/native_bridge.gd")
const ExportComparison = preload("res://src/services/export_comparison.gd")
const FolderCheck = preload("res://src/services/folder_check.gd")
const ProjectFlows = preload("res://src/shell/project_flows.gd")
const WorkspaceSettings = preload("res://src/services/workspace_settings.gd")
const ROUTES := ["Project", "Stages", "Messages", "Maps", "Inspection", "Programs", "Combat", "Records", "Export", "Items", "Problems", "Shops", "Texts", "Resources", "Calendar", "Notes"]
# Each route's tab title and its place in the header.
const ROUTE_TITLES := {
	"Project": ["Project", "PROJECTS"],
	"Stages": ["Stages & startup", "WORLD / STAGES"],
	"Messages": ["Messages", "STORY / MESSAGES"],
	"Maps": ["Maps", "WORLD / MAPS"],
	"Inspection": ["Inspection", "RECORDS / INSPECTION"],
	"Programs": ["Triggers & encounters", "STORY / TRIGGERS"],
	"Combat": ["Battles & monsters", "COMBAT / BATTLES"],
	"Records": ["Author records", "RECORDS / AUTHOR RECORDS"],
	"Export": ["Export", "RELEASE / EXPORT"],
	"Items": ["Items", "RECORDS / ITEMS"],
	"Problems": ["Problems", "RELEASE / PROBLEMS"],
	"Shops": ["Shops", "RECORDS / SHOPS"],
	"Texts": ["Texts", "STORY / TEXTS"],
	"Resources": ["Resources", "RECORDS / RESOURCES"],
	"Calendar": ["Calendar", "WORLD / CALENDAR"],
	"Notes": ["Notes", "WORLD / NOTES"],
}
var bridge: Node
var summary: Dictionary = {}
var drafts: Dictionary = {}
var settings := WorkspaceSettings.new()
## The installation folder found beside the editor, and what it holds.
var folder := ""
var folder_report: Array = []
var folder_play_note := ""
var checkpoint_version := 0
var item_names: Array = []
## The icon (a cicn number) of each item, null where the item has none.
var item_icons: Array = []
var _item_names_key := ""
var references: References = References.new(self)
var last_route := 3
var _loading := false
var _folder_action := ""
var _destination_action := ""
var _source := ""
var _scenario_name := "First Patrol"
var _pending: Callable
var _pending_replace := false
var _after_save: Callable
var _closing := false
var _started := false
var _last_export: Dictionary = {}
var flows: RefCounted
var condition_ui: RefCounted
var combat_ui: Control
var record_ui: RefCounted
var play := preload("res://src/services/play_session.gd").new(self)
var play_bar := preload("res://src/shell/play_bar.gd").new()
var compact := preload("res://src/shell/compact_layout.gd").new(self)
var navigator := preload("res://src/shell/navigator.gd").new(self)
var flow_dialog := preload("res://src/dialogs/flow_dialog.gd").new()
var guide_window := preload("res://src/dialogs/guide_window.gd").new()
var goto_dialog := preload("res://src/dialogs/goto_dialog.gd").new()
var author_dialog := preload("res://src/dialogs/author_records_dialog.gd").new()
var picker_dialog := preload("res://src/dialogs/record_picker_dialog.gd").new()
var import_dialog := preload("res://src/dialogs/import_resource_dialog.gd").new()
var resource_picker := preload("res://src/dialogs/resource_picker_dialog.gd").new()
var mission_ui: RefCounted
var placement_ui: RefCounted

@onready var header: Control = %Header
@onready var rail: Control = %Rail
@onready var tabs: Control = %RecordTabs
@onready var pages: Container = %Pages
@onready var apply_bar: Control = %ApplyBar
@onready var problems: Control = %ProblemsDock
@onready var status_bar: Control = %StatusBar
@onready var project: Control = %Project
@onready var stages: Control = %Stages
@onready var messages: Control = %Messages
@onready var maps: Control = %Maps
@onready var inspection: Control = %Inspection
@onready var programs: Control = %Programs
@onready var combat: Control = %Combat
@onready var records: Control = %Records
@onready var export_page: Control = %ExportPage
@onready var items_page: Control = %Items
@onready var problems_page: Control = %ProblemsPage
@onready var shops_page: Control = %ShopsPage
@onready var texts_page: Control = %TextsPage
@onready var resources_page: Control = %ResourcesPage
@onready var calendar_page: Control = %CalendarPage
@onready var notes_page: Control = %NotesPage


## Controls built in code have no owner, which find_child skips below them, so
## the ones the drivers and controllers look up by name are registered.
var _named: Dictionary = {}


func name_node(name: String, node: Node) -> void:
	_named[name] = node


func ui(name: String) -> Variant:
	if _named.has(name): return _named[name]
	return find_child(name, true, false)


func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(func(): guard(_quit, true))
	bridge = Bridge.new()
	add_child(bridge)
	bridge.transport_failed.connect(func(message): status(message, "err"))
	bridge.busy_changed.connect(func(_busy): _show_chrome())
	flows = ProjectFlows.new(self)
	for page in pages.get_children(): page.setup(self)
	header.command.connect(_run_command)
	rail.route_requested.connect(func(route): guard(_show_named_route.bind(route)))
	rail.problems_requested.connect(func(): problems.open(not ui("Problems").visible))
	problems.toggled.connect(func(opened): rail.show_problems(opened); header.show_problems(opened))
	apply_bar.apply_requested.connect(apply_draft)
	apply_bar.discard_requested.connect(func(): if not bridge.busy: _discard_continue())
	ui("FolderPicker").dir_selected.connect(_folder_selected)
	ui("DestinationDialog").closed.connect(func(): _after_save = Callable())
	ui("DraftDialog").custom_action.connect(func(_action): _discard_continue())
	ui("DraftDialog").confirmed.connect(_apply_continue)
	ui("DraftDialog").canceled.connect(_cancel_navigation)
	ui("UnsavedDialog").custom_action.connect(func(_action): var next := _pending; _pending = Callable(); if next.is_valid(): next.call())
	ui("UnsavedDialog").confirmed.connect(func(): _after_save = _pending; _pending = Callable(); _choose_destination("save"))
	ui("UnsavedDialog").canceled.connect(func(): _pending = Callable())
	condition_ui = preload("res://src/condition_editor.gd").new(self)
	combat_ui = combat
	record_ui = records.editor
	items_page.setup(self)
	problems.setup(self)
	problems_page.setup(self)
	shops_page.setup(self)
	texts_page.setup(self)
	resources_page.setup(self)
	calendar_page.setup(self)
	notes_page.setup(self)
	import_dialog.setup(self)
	resource_picker.setup(self)
	var content: Control = pages.get_parent()
	content.add_child(play_bar)
	content.move_child(play_bar, ui("ApplyBar").get_index())
	play.changed.connect(_play_changed)
	play_bar.continue_requested.connect(func(): play.continue_play())
	play_bar.step_requested.connect(func(): play.step())
	play_bar.restart_requested.connect(func(): play.restart())
	play_bar.stop_requested.connect(func(): play.stop())
	compact.setup()
	problems.changed.connect(func(): _update_buttons(); if pages.current_tab == ROUTES.find("Problems"): problems_page.refresh())
	author_dialog.name = "AuthorRecordsDialog"
	goto_dialog.name = "GoToDialog"
	flow_dialog.name = "FlowDialog"
	picker_dialog.name = "RecordPickerDialog"
	import_dialog.name = "ImportResourceDialog"
	resource_picker.name = "ResourcePickerDialog"
	guide_window.name = "GuideWindow"
	for dialog in [author_dialog, picker_dialog, import_dialog, resource_picker, goto_dialog, flow_dialog, guide_window]: add_child(dialog)
	flow_dialog.setup(self)
	goto_dialog.setup(self)
	goto_dialog.chosen.connect(_go_to_chosen)
	author_dialog.setup(self)
	picker_dialog.setup(self)
	mission_ui = preload("res://src/mission_recipe.gd").new(self)
	placement_ui = preload("res://src/trigger_placement.gd").new(self)
	_show_route(0)
	_find_folder("")
	_show_chrome()
	var response: Dictionary = await bridge.start()
	status("Ready · Open or import a scenario level" if response.get("ok",false) else _error(response), "good" if response.get("ok",false) else "err")
	if response.get("ok",false):
		var described: Dictionary = response.result
		checkpoint_version = int(described.get("checkpoint_version", 0))
		var settings_file: Variant = described.get("settings_file")
		settings.load_from(str(settings_file) if settings_file is String else "")
		_started = true
		var preferences: Variant = described.get("preferences",{})
		if preferences is Dictionary:
			_find_folder(str(preferences.get("installation","")))
			_show_recents(preferences.get("recent",[]))
			if preferences.has("warning"): status(str(preferences.warning), "err")
	var opening := OS.get_environment("CENTURIONS_PROJECT")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--project="): opening = argument.trim_prefix("--project=")
	if not opening.is_empty(): await open_project(opening)
	startup_completed.emit()
	if OS.get_cmdline_user_args().has("--verify-installation"):
		var passed: bool = not ui("Installation").text.is_empty() and ui("MapCanvas").atlas != null
		print("CENTURIONS_INSTALLATION_RESTART_PASSED" if passed else "CENTURIONS_INSTALLATION_RESTART_FAILED")
		bridge.stop(); get_tree().quit(0 if passed else 1)
	elif OS.get_cmdline_user_args().has("--verify-connected"):
		await preload("res://verification/connected_driver.gd").new().run_on_shell(self)
	elif OS.get_cmdline_user_args().has("--verify-editor"):
		await preload("res://verification/workflow_driver.gd").new().run_on_shell(self)


func _error(response: Dictionary) -> String:
	return str(response.get("error",{}).get("message","Operation failed"))


## `level` colours the dot before the line; without one it is read from the line.
func status(message: String, level := "") -> void:
	status_bar.show_message(message, level)


## Looks for the installation beside the editor and shows what it holds.
func _find_folder(remembered: String) -> void:
	folder = FolderCheck.find(remembered)
	folder_report = FolderCheck.report(folder)
	folder_play_note = FolderCheck.play_note(folder_report)
	ui("Installation").text = folder
	project.show_folder(folder, folder_report)
	status_bar.show_folder(FolderCheck.summary(folder_report, folder))


func _show_recents(list: Variant) -> void:
	var known: Array = list if list is Array else []
	project.show_recents(known)
	header.set_recents(known)


## Reads the recent projects the adapter keeps, after one was opened or saved.
func refresh_recents() -> void:
	if not _started or bridge.busy or bridge.requires_reopen: return
	var response: Dictionary = await request_backend({"op":"describe"})
	if response.get("ok",false) and response.result.get("preferences") is Dictionary:
		_show_recents(response.result.preferences.get("recent",[]))


## The folder a new checkpoint or export goes under unless the author picked one.
func default_output_parent() -> String:
	var chosen := str(settings.get_value("output_parent"))
	return chosen if not chosen.is_empty() else bridge.adapter_path().get_base_dir()


## Sends an operation to the adapter once any operation under way has finished, so pages that load together never refuse each other.
func request_backend(operation: Dictionary) -> Dictionary:
	while bridge.busy: await get_tree().process_frame
	ui("MapCanvas").mouse_filter = Control.MOUSE_FILTER_IGNORE
	var response: Dictionary = await bridge.request(operation)
	ui("MapCanvas").mouse_filter = Control.MOUSE_FILTER_STOP
	if not response.get("ok",false): status(_error(response), "err")
	_update_buttons()
	return response


## Sends an operation once the adapter is free (the same as `request_backend`, kept for the callers that say so).
func request_when_free(operation: Dictionary) -> Dictionary:
	return await request_backend(operation)


func _update_buttons() -> void:
	var opened := not summary.is_empty()
	var blocked: bool = bridge.busy or bridge.requires_reopen
	for name in ["Save","Export","Check"]: ui(name).disabled = not opened or blocked
	var reason: String = play.unavailable()
	ui("PlayFromHere").disabled = not reason.is_empty() or blocked or play.running
	ui("PlayFromHere").tooltip_text = reason
	ui("Undo").disabled = blocked or not summary.get("can_undo",false)
	ui("Redo").disabled = blocked or not summary.get("can_redo",false)
	ui("ProjectTitle").text = _project_line() + (" · unsaved" if summary.get("dirty",false) else "")
	export_page.state_changed()
	_show_chrome()


## The open project's name: the scenario's native name, or its origin's label.
func project_name() -> String:
	var native: Variant = summary.get("native")
	return str(native.get("name","")) if native is Dictionary else str(summary.get("origin",{}).get("label",""))


## The header's second line: the project's name and where its checkpoint is.
func _project_line() -> String:
	if summary.is_empty(): return "No project open"
	var path := str(summary.get("path","")).replace("\\\\?\\","").replace("\\","/")
	var name := project_name()
	var parts := path.split("/")
	var tail := "…\\" + "\\".join(parts.slice(maxi(0, parts.size() - 2))) if parts.size() > 2 else path
	return "%s · %s" % [name, tail]


## Brings the apply bar, menus, rail counts, tab and status bar in line with
## the session.
func _show_chrome() -> void:
	var unsaved: bool = summary.get("dirty",false)
	apply_bar.show_pending(drafts.size(), bridge.busy or bridge.requires_reopen)
	for name in ["Save","Export","Undo","Redo","Apply","Check"]: header.set_available(name.to_lower(), not ui(name).disabled)
	header.set_available("play", not ui("PlayFromHere").disabled)
	header.set_available("stop", play.active)
	header.set_project_open(not summary.is_empty())
	header.show_unsaved(unsaved)
	status_bar.show_state(drafts.size(), unsaved)
	rail.show_counts(_record_counts())
	status_bar.show_problem_count(problems.count)
	_show_tab()
	maps.chrome_changed()


## The rail's counts: maps, stages and notices, and the complete rows of each
## table that holds one record per row.
func _record_counts() -> Dictionary:
	if summary.is_empty(): return {}
	var rows := {}
	for table in summary.get("tables",[]): rows[table.file] = int(table.complete_records)
	var counts := {"Maps": int(summary.get("maps",0)), "Stages": summary.get("stages",[]).size(), "Problems": problems.count}
	for entry in [["Stories","Data ED3"],["Messages","Data SD2"],["Battles","Data BD"],["Monsters","Data MD"],["Rewards","Data TD"],["Shops","Data SD"]]:
		if rows.has(entry[1]): counts[entry[0]] = rows[entry[1]]
	if rows.has("Data NI"): counts["Items"] = mini(200, int(rows["Data NI"]))
	if rows.has("Data ED") or rows.has("Data ED2"): counts["Encounters"] = int(rows.get("Data ED",0))+int(rows.get("Data ED2",0))
	return counts


func _show_tab() -> void:
	var title: String = ROUTE_TITLES[ROUTES[pages.current_tab]][0]
	if ROUTES[pages.current_tab] == "Records": title = record_ui.PLURALS[record_ui.FAMILIES[record_ui.family.selected]]
	tabs.show_tabs([{"title": title, "dirty": not drafts.is_empty()}], 0)
	var current := _current_record()
	tabs.set_record("%s %d" % [navigator.NOUNS.get(current[0], str(current[0]).capitalize()), int(current[1])] if current.size() == 2 and int(current[1]) >= 0 else title)


## Shows a route by name. The programs have one page and four families, so
## "Programs:story" opens the page on stories.
func _show_named_route(route: String) -> void:
	var parts := route.split(":")
	if parts[0] == "Programs" and parts.size() > 1:
		if programs.family != parts[1]:
			programs.family = parts[1]
			programs.id = 0
			programs.branch = 0
			programs.selected_slot = 0
	if parts[0] == "Records" and parts.size() > 1 and FAMILY_CRUMBS.has(parts[1]):
		record_ui.show_family(parts[1])
	await _show_route(ROUTES.find(parts[0]))


const FAMILY_CRUMBS := {"monster": "COMBAT / MONSTERS", "reward": "RECORDS / REWARDS"}
const PROGRAM_CRUMBS := {"walking": "STORY / TRIGGERS", "story": "STORY / STORIES", "menu": "STORY / ENCOUNTERS", "typed": "STORY / ENCOUNTERS"}


func _mark_route(index: int) -> void:
	compact.route_changed()
	var route: String = ROUTES[index]
	var crumb: String = ROUTE_TITLES[route][1]
	if route == "Programs":
		crumb = PROGRAM_CRUMBS[programs.family]
		route += ":" + ("menu" if programs.family == "typed" else programs.family)
	elif route == "Records":
		var kind: String = record_ui.FAMILIES[record_ui.family.selected]
		crumb = FAMILY_CRUMBS.get(kind, crumb)
		route += ":" + kind
	rail.show_route(route)
	header.show_route(route, crumb)
	_show_tab()


func _run_command(name: String) -> void:
	match name:
		"import": guard(_import_picker, true)
		"open": guard(_open_picker, true)
		"new": guard(open_new_dialog, true)
		"save": guard(_choose_destination.bind("save"))
		"export": guard(_show_route.bind(ROUTES.find("Export")))
		"receipt": project.choose_receipt()
		"preferences": flows.open_preferences()
		"close": guard(_close_project, true)
		"revert": _revert_form()
		"undo", "redo": guard(_history.bind(name))
		"apply": apply_draft()
		"check": check_project()
		"play": guard(play_from_here)
		"stop": play.stop()
		"find_uses": var current := _current_record(); if not current.is_empty(): find_uses(current[0], int(current[1]))
		"view_flow": view_flow()
		"guide": guide_window.show_guide()
		"goto": if pages.current_tab != 0 and not summary.is_empty(): goto_dialog.show_dialog()
		"author": author_dialog.show_for(record_ui.FAMILIES[record_ui.family.selected])
		"mission": guard(func(): mission_ui.window.popup_centered())
		"problems": problems.open(not ui("Problems").visible)
		"helper": if pages.current_tab == ROUTES.find("Programs"): programs.toggle_helper()
		"technical": if pages.current_tab == ROUTES.find("Programs"): programs.panel.details_button.button_pressed = not programs.panel.details_button.button_pressed
		_:
			if name.begins_with("route:"): guard(_show_named_route.bind(name.trim_prefix("route:")))
			elif name.begins_with("map:"): maps.command(name)
			elif name.begins_with("recent:"):
				var index := int(name.trim_prefix("recent:"))
				if index < project.recents.size(): guard(func(): await open_project(str(project.recents[index].path)), true)


## Plays the project from its stage start to the selected cell of the open map.
func play_from_here() -> void:
	var cell := Vector2i(-1, -1)
	if maps.canvas.selected_cell.x >= 0: cell = maps.canvas.selected_cell
	if await play.start(maps.map_id, cell): problems.show_log()


func _play_changed() -> void:
	play_bar.show_session(play)
	problems.show_play(play)
	_update_buttons()


## Puts the commands of the session on the clipboard, as the replay tool reads them.
func copy_play_commands() -> void:
	DisplayServer.clipboard_set(JSON.stringify(play.commands(), "  "))
	status("%d commands copied" % play.commands().size(), "good")


## Writes the commands of the session beside the project's other output.
func save_play_replay() -> void:
	var folder := default_output_parent().path_join("replays")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("replay-%s.json" % Time.get_datetime_string_from_system().replace(":", "-"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: status("The replay could not be written to %s" % path, "err"); return
	file.store_string(JSON.stringify(play.commands(), "  "))
	file.close()
	status("Replay saved · %s" % path, "good")


## Runs the checks again and says how they came out.
func check_project() -> void:
	if summary.is_empty() or bridge.busy: return
	await problems.refresh()
	var counts: Dictionary = problems.result.get("counts", {})
	status("Checked after the last edit · %d errors · %d warnings · %d read-only" % [int(counts.get("errors", 0)), int(counts.get("warnings", 0)), int(counts.get("readonly", 0))], "good" if int(counts.get("errors", 0)) == 0 else "err")


## The record the page in view is showing, as [kind, id], or [] when it shows none.
func _current_record() -> Array:
	match ROUTES[pages.current_tab]:
		"Stages": return ["stage", stages.stage_id]
		"Messages": return ["message", messages.message_id]
		"Combat": return ["battle", combat.selected_id]
		"Records": return [record_ui.FAMILIES[record_ui.family.selected], int(record_ui.id.value)]
		"Items": return ["item", 800 + items_page.index]
		"Programs": return [{"walking": "walking", "story": "story", "menu": "choice", "typed": "typed"}[programs.family], programs.id]
	return []


## The names of items 0 to 999, read once for each project and folder: the
## stock items from the installation's Data ID, the scenario's own from its STR# 801.
func ensure_item_names() -> void:
	if summary.is_empty(): return
	var key := "%s|%s|%d" % [str(summary.get("path", "")), folder, bridge.revision]
	if key == _item_names_key: return
	var response: Dictionary = await request_when_free({"op": "item_names", "installation": folder})
	item_names = response.result.names if response.get("ok", false) else []
	item_icons = response.result.icons if response.get("ok", false) else []
	_item_names_key = key


## What the game calls item `id`, or "" when no name could be read.
func item_name(id: int) -> String:
	if id < 0 or id >= item_names.size() or item_names[id] == null: return ""
	return str(item_names[id])


## Lists what names a record in the dock's Find tab.
func find_uses(kind: String, id: int, label := "") -> void:
	await problems.find_uses(kind, id, label)


## Opens the flow of the program in view.
func view_flow() -> void:
	if pages.current_tab == ROUTES.find("Programs"): await flow_dialog.show_for(programs.family, programs.id)
	elif pages.current_tab == ROUTES.find("Stages"): await view_stage_flow()


## Opens the flow of the stage in view, from its start script.
func view_stage_flow() -> void:
	var stage: Dictionary = summary.get("stages", [])[stages.stage_id] if stages.stage_id < summary.get("stages", []).size() else {}
	if stage.is_empty() or int(stage.start_script) <= 0:
		status("This stage runs no start script", "dim")
		return
	await flow_dialog.show_for("story", int(stage.start_script))


## Opens what Go to chose, once nothing unapplied would be lost.
func _go_to_chosen(entry: Dictionary) -> void:
	if entry.kind == "cell": guard(navigator.go_to_cell.bind(entry.cell))
	else: guard(navigator.go.bind(str(entry.kind), int(entry.id)))


## Revert form asks the same question as leaving it with unapplied edits.
func _revert_form() -> void:
	if bridge.busy: status("Wait for the current operation."); return
	if drafts.is_empty(): status("No unapplied edits to revert", "dim"); return
	_pending = Callable()
	flows.ask_draft(ROUTE_TITLES[ROUTES[pages.current_tab]][0], drafts.size())


## Runs `action` once nothing would be lost by it: unapplied edits are applied
## or discarded first, and with `replace` an unsaved checkpoint is saved or
## given up first.
func guard(action: Callable, replace := false) -> void:
	if bridge.busy: status("Wait for the current operation."); return
	if bridge.requires_reopen:
		if not summary.is_empty(): open_project(str(summary.path))
		else: _open_picker()
		return
	if not drafts.is_empty():
		_pending = action; _pending_replace = replace
		flows.ask_draft(ROUTE_TITLES[ROUTES[pages.current_tab]][0], drafts.size())
	elif replace and summary.get("dirty",false):
		_pending = action
		flows.ask_unsaved(project_name(), str(summary.path).replace("\\\\?\\",""))
	else: action.call()


func _discard_continue() -> void:
	ui("DraftDialog").hide()
	drafts.clear()
	await _refresh_forms()
	var next := _pending; var replace := _pending_replace
	_pending = Callable()
	if next.is_valid(): guard(next,replace)


func _cancel_navigation() -> void:
	_pending = Callable()
	stages.refresh()
	if pages.current_tab == 5: await programs.load_program()
	if pages.current_tab == 6: await combat.catalogue(0)
	if pages.current_tab == 7: record_ui.restore_selection(); await record_ui.refresh()
	messages.restore_selection()
	maps.restore_choice()
	_mark_route(pages.current_tab)


func _apply_continue() -> void:
	var next := _pending; var replace := _pending_replace
	_pending = Callable()
	if await apply_draft() and next.is_valid(): guard(next,replace)


func _show_route(index: int) -> void:
	if ROUTES[index] == "Export" and pages.current_tab != index: last_route = pages.current_tab
	pages.current_tab = index
	_mark_route(index)
	if index == 0: await refresh_recents()
	if summary.is_empty(): return
	match index:
		1: stages.refresh(); await stages.show_story()
		2: if messages.rows.is_empty(): await messages.list_messages(0)
		3: await maps.show_map()
		4: await inspection.show_story()
		5: await programs.load_program()
		6: await combat.catalogue(0)
		7: await record_ui.refresh()
		8: export_page.refresh()
		9: await items_page.refresh()
		10: problems_page.refresh()
		11: await shops_page.refresh()
		12: await texts_page.refresh()
		13: await resources_page.refresh()
		14: await calendar_page.refresh()
		15: await notes_page.refresh()


## Opens the first workspace after a project was opened from the Project page.
func show_workspace() -> void:
	if pages.current_tab == 0: await _show_route(ROUTES.find("Maps"))


func open_project(path: String) -> void:
	var recovering: bool = bridge.requires_reopen
	var retained := drafts.duplicate(true) if recovering else {}
	var selected_message: int = messages.message_id
	if recovering: await bridge.start()
	var response := await request_backend({"op":"open","path":path})
	if response.get("ok",false):
		drafts.clear(); messages.forget(true); maps.map_id = 0; stages.stage_id = 0
		await _set_summary(response.result)
		drafts = retained
		if recovering:
			messages.message_id = selected_message
			await _refresh_forms()
		status("Reopened saved checkpoint · pending drafts retained; applied edits require a saved checkpoint to survive interruption" if recovering else "Opened checkpoint")
		await refresh_recents()


## Close project: the session forgets the open project. The checkpoint on disk
## is untouched.
func _close_project() -> void:
	summary = {}
	drafts.clear()
	project.show_summary({})
	problems.clear()
	_update_buttons()
	_show_route(0)
	status("No project open", "dim")


func _set_summary(value: Dictionary) -> void:
	summary = value
	_loading = true
	stages.list_stages(summary)
	maps.list_maps(summary)
	_loading = false
	project.show_summary(summary)
	await problems.refresh()
	inspection.show_geometry(summary)
	project.forget_receipt()
	_update_buttons()
	await _refresh_forms()
	if pages.current_tab != 3: await load_artwork()


func _refresh_forms() -> void:
	if summary.is_empty(): return
	stages.refresh()
	if messages.message_id >= 0: await messages.load_message(messages.message_id)
	if pages.current_tab == 3: await maps.show_map()
	if pages.current_tab == 5: await programs.load_program()
	if pages.current_tab == 6: await combat.catalogue(0)
	if pages.current_tab == 7: await record_ui.refresh()
	if pages.current_tab == 8: export_page.refresh()
	if pages.current_tab == 9: await items_page.refresh()
	if pages.current_tab == 12: await texts_page.refresh()
	if pages.current_tab == 13: await resources_page.refresh()
	if pages.current_tab == 14: await calendar_page.refresh()
	if pages.current_tab == 15: await notes_page.refresh()
	if pages.current_tab == 1: await stages.show_story()
	_update_buttons()


func apply_draft() -> bool:
	if drafts.is_empty(): return true
	var response := await request_backend({"op":"apply","expected_revision":bridge.revision,"edits":drafts.values()})
	if not response.get("ok",false): return false
	drafts.clear()
	await _set_summary(response.result)
	status("Edits applied · Save a new checkpoint to keep them")
	return true


func _history(operation: String) -> void:
	var response := await request_backend({"op":operation,"expected_revision":bridge.revision})
	if response.get("ok",false): await _set_summary(response.result); status(operation.capitalize()+" complete")


func _pick_folder(action: String) -> void:
	_folder_action = action
	ui("FolderPicker").title = {"open":"Open checkpoint folder","import":"Import extracted scenario level","template":"Choose unchanged template checkpoint","installation":"Choose the New Centurions folder","destination_parent":"Choose output parent","output_parent":"Choose output parent"}.get(action,"Choose folder")
	ui("FolderPicker").popup_centered(Vector2i(900,600))


func _open_picker() -> void: _pick_folder("open")
func _import_picker() -> void: _pick_folder("import")


## New from template: the dialog asks for the template, the name and the folder.
func open_new_dialog() -> void:
	_choose_destination("new")


func _folder_selected(path: String) -> void:
	match _folder_action:
		"open": await open_project(path)
		"import": _source = path; _choose_destination("import")
		"template":
			_source = path
			if flows.new_dialog_open(): flows.template_chosen(path)
			else: _choose_destination("new")
		"installation": await _use_installation(path)
		"destination_parent": set_destination(path.path_join(ui("DestinationPath").text.get_file()))
		"output_parent": settings.set_value("output_parent", path); flows.preferences_dialog.output_parent.show_path(path)


## Development runs only: the folder the author pointed at is checked, remembered
## and used for the artwork.
func _use_installation(path: String) -> void:
	if not FolderCheck.holds_original_data(path):
		status("Choose the New Centurions folder: it holds Data Files and Scenarios", "warn")
		return
	_find_folder(path)
	await _remember_installation()


## The destination the next save, import, new scenario or export writes to. The
## fields that show it follow; `source` is the one the author typed in.
func set_destination(path: String, source: Object = null) -> void:
	ui("DestinationPath").text = path
	flows.sync_destination(path, source)


func _choose_destination(action: String) -> void:
	_destination_action = action
	var timestamp := Time.get_datetime_string_from_system().replace(":","").replace("-","").replace("T","-")
	ui("DestinationPath").text = default_output_parent().path_join(action+"-"+timestamp)
	flows.sync_destination(ui("DestinationPath").text)
	flows.open_destination(action)


## Writes the open project to the destination. Returns whether it was written.
func _publish() -> bool:
	flows.hide_destination_dialogs()
	var op := {"op":_destination_action,"destination":ui("DestinationPath").text,"expected_revision":bridge.revision}
	match _destination_action:
		"save": op.op = "save_as"
		"import": op.source = _source
		"new": op.template = _source; op.name = _scenario_name
	var response := await request_backend(op)
	if not response.get("ok",false):
		_after_save = Callable()
		flows.publish_failed(_destination_action, _error(response))
		return false
	if _destination_action == "export":
		var line := "Exported %d files to %s · installation and runtime checks remain separate" % [response.result.files,op.destination]
		status(line)
		_last_export = {"destination": op.destination, "result": response.result, "status": line}
	else:
		drafts.clear(); messages.forget(false); stages.stage_id = 0; maps.map_id = 0
		await _set_summary(response.result)
		status("Checkpoint ready · "+str(op.destination))
		await refresh_recents()
		var next := _after_save; _after_save = Callable()
		if next.is_valid(): next.call()
	return true


## The Export page's button: writes the folder, compares it with the import and
## shows what was written.
func start_export(compare: bool) -> void:
	_destination_action = "export"
	var project_folder := str(summary.path).replace("\\\\?\\","")
	if not await _publish(): return
	var comparison := {}
	if compare: comparison = ExportComparison.compare(project_folder, _last_export.destination)
	flows.show_export_result(_last_export.destination, _last_export.result, comparison, _last_export.status)


func _quit() -> void:
	_closing = true
	bridge.stop()
	get_tree().quit()


## Whether a dialog is open; while one is, keys and the page behind it stay quiet.
func modal_open() -> bool:
	for name in ["DraftDialog","UnsavedDialog","DestinationDialog","NewDialog","ImportDialog","PreferencesDialog","ExportResultDialog","ChooseActionDialog","ChooseMessageDialog","ChooseTileDialog","RemoveDialog","AuthorRecordsDialog","RecordPickerDialog","GoToDialog","AddMapDialog","RemoveMapDialog","ChooseCellDialog","FolderPicker","ReceiptPicker","ConditionsWindow","MissionRecipeWindow"]:
		if ui(name).visible: return true
	return false


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if modal_open(): return
	var command: String = header.command_for_key(event)
	if command.is_empty(): return
	var focused := get_viewport().gui_get_focus_owner()
	var typing: bool = focused is TextEdit or focused is LineEdit
	if command in ["undo","redo"] and typing: return
	# The Map menu's keys are single letters: they belong to the map, and never to a field.
	if command.begins_with("map:") and (typing or pages.current_tab != ROUTES.find("Maps")): return
	_run_command(command)
	get_viewport().set_input_as_handled()


# The page state and entry points that the feature controllers and the
# verification drivers reach through the shell.
var _stage_id: int:
	get: return stages.stage_id
	set(value): stages.stage_id = value
var _map_id: int:
	get: return maps.map_id
var _program: Dictionary:
	get: return programs.program
var _program_family: String:
	get: return programs.family
var _program_id: int:
	get: return programs.id
var _step_controls: Array:
	get: return programs.step_controls

func _select_stage(index: int) -> void: stages.select_stage(index)
func _stage_changed() -> void: stages.changed()
func _load_message(id: int) -> void: await messages.load_message(id)
func _message_changed() -> void: messages.changed()
func _select_map(index: int) -> void: await maps.select_map(index)
func _paint_stroke(cells: Array) -> void: await maps.paint_stroke(cells)
func _map_cell_selected(cell: Vector2i, tile: int) -> void: maps.cell_selected(cell, tile)
func load_artwork() -> void: await maps.load_artwork()
func _place_trigger(cell: Vector2i) -> void: await placement_ui.place(cell)
func _choose_program(family: String, id: int, branch: int) -> void: await programs.choose(family, id, branch)
func _open_map_program(id: int) -> void: await programs.open_map_program(id)
func _load_program() -> void: await programs.load_program()
func _program_changed(slot: int) -> void: programs.changed(slot)
func _follow_step(slot: int) -> void: await programs.follow_step(slot)
func _match_receipt(path: String) -> void: await project.match_receipt(path)
func _invalidate_receipt() -> void: project.invalidate_receipt()
func _remember_installation() -> void: await project.remember_installation()
