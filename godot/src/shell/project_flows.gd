extends RefCounted
## The project flows the shell runs: the dialogs for importing, starting from a
## template, saving, preferences and the export result, and the two questions
## the shell asks before it would lose work. The shell keeps the state and runs
## the operations; this owns what the author sees.
const ConfirmDialog = preload("res://src/widgets/confirm_dialog.gd")
const ExportResultDialog = preload("res://src/dialogs/export_result_dialog.gd")
const ImportDialog = preload("res://src/dialogs/import_dialog.gd")
const NewDialog = preload("res://src/dialogs/new_dialog.gd")
const PreferencesDialog = preload("res://src/dialogs/preferences_dialog.gd")
const SaveDialog = preload("res://src/dialogs/save_dialog.gd")
const FolderCheck = preload("res://src/services/folder_check.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

var shell: Control
var draft_dialog := ConfirmDialog.new()
var unsaved_dialog := ConfirmDialog.new()
var import_dialog := ImportDialog.new()
var new_dialog := NewDialog.new()
var save_dialog := SaveDialog.new()
var preferences_dialog := PreferencesDialog.new()
var result_dialog := ExportResultDialog.new()
var _exported := ""


func _init(owner_shell: Control) -> void:
	shell = owner_shell
	for entry in [[draft_dialog, "DraftDialog"], [unsaved_dialog, "UnsavedDialog"], [import_dialog, "ImportDialog"], [new_dialog, "NewDialog"],
			[save_dialog, "DestinationDialog"], [preferences_dialog, "PreferencesDialog"], [result_dialog, "ExportResultDialog"]]:
		entry[0].name = entry[1]
		shell.add_child(entry[0])
	shell.name_node("ScenarioName", new_dialog.scenario_name)
	shell.name_node("RuntimeStatus", result_dialog.runtime_status)
	draft_dialog.tone = "warn"
	draft_dialog.heading = "Apply or discard the unapplied edits?"
	draft_dialog.message = "Discarding returns the form to its last applied state. Applied edits and the saved project are not touched."
	draft_dialog.add_button("Discard", "danger", "discard", true)
	draft_dialog.add_button("Cancel")
	draft_dialog.add_button("Apply", "primary")
	unsaved_dialog.tone = "info"
	unsaved_dialog.message = "Saving writes a new checkpoint. The imported level and the installation are never changed."
	unsaved_dialog.add_button("Don't save", "secondary", "discard", true)
	unsaved_dialog.add_button("Cancel")
	unsaved_dialog.add_button("Save", "primary")
	_connect_dialogs()


func _connect_dialogs() -> void:
	for dialog in [import_dialog, new_dialog, save_dialog]:
		dialog.destination.text_changed.connect(func(text): shell.set_destination(text, dialog.destination))
	import_dialog.browse_requested.connect(shell._pick_folder.bind("destination_parent"))
	save_dialog.browse_requested.connect(shell._pick_folder.bind("destination_parent"))
	new_dialog.destination_browse_requested.connect(shell._pick_folder.bind("destination_parent"))
	new_dialog.template_browse_requested.connect(shell._pick_folder.bind("template"))
	import_dialog.import_requested.connect(func():
		if await shell._publish():
			import_dialog.show_result(shell.summary)
			import_dialog.open())
	import_dialog.another_requested.connect(func(): import_dialog.close(); shell.guard(shell._import_picker, true))
	import_dialog.template_requested.connect(func(): import_dialog.close(); shell.guard(shell.open_new_dialog, true))
	import_dialog.open_requested.connect(func(): import_dialog.close(); shell.show_workspace())
	save_dialog.save_requested.connect(func(): await shell._publish())
	new_dialog.create_requested.connect(func():
		shell._scenario_name = new_dialog.scenario_name.text
		shell._source = new_dialog.template.text
		await shell._publish())
	new_dialog.template.text_changed.connect(func(text): shell._source = text)
	preferences_dialog.value_changed.connect(shell.settings.set_value)
	preferences_dialog.output_browse_requested.connect(shell._pick_folder.bind("output_parent"))
	result_dialog.receipt_requested.connect(func(): shell.project.choose_receipt())
	result_dialog.show_folder_requested.connect(func(): if not _exported.is_empty(): OS.shell_show_in_file_manager(_exported))


## Pushes the destination the shell holds to every field that shows it,
## except the one the author is typing in.
func sync_destination(text: String, skip: Object = null) -> void:
	for field in [import_dialog.destination, new_dialog.destination, save_dialog.destination]:
		if field != skip and field.text != text: field.show_path(text)
	if shell.export_page != skip: shell.export_page.show_destination(text)


## Shows the dialog for a destination the shell has chosen.
func open_destination(action: String) -> void:
	var path: String = shell.ui("DestinationPath").text
	match action:
		"save":
			save_dialog.destination.show_path(path)
			save_dialog.show_form()
			save_dialog.open()
		"import":
			import_dialog.destination.show_path(path)
			import_dialog.show_source(shell._source, scan(shell._source), shell.checkpoint_version)
			import_dialog.open()
		"new":
			new_dialog.scenario_name.text = shell._scenario_name
			new_dialog.template.show_path(shell._source)
			new_dialog.destination.show_path(path)
			new_dialog.show_form()
			new_dialog.open()
		"export":
			shell._show_route(shell.ROUTES.find("Export"))


## The dialogs that hold a destination are closed once it is used.
func hide_destination_dialogs() -> void:
	for dialog in [import_dialog, new_dialog, save_dialog]: dialog.hide()


## A destination that was refused comes back with the reason beside it.
func publish_failed(action: String, message: String) -> void:
	match action:
		"save":
			save_dialog.show_form(message)
			save_dialog.open()
		"import":
			import_dialog.show_failure(message)
			import_dialog.open()
		"new":
			new_dialog.show_form(message)
			new_dialog.open()


func new_dialog_open() -> bool:
	return new_dialog.visible


func template_chosen(path: String) -> void:
	new_dialog.template.show_path(path)
	new_dialog.show_gate()


## Counts what an import would read: the files and the directories with nothing in them.
func scan(folder: String) -> String:
	var counts := [0, 0]
	_count(folder, counts)
	return "%d files with their sidecars · %d empty directories" % counts


func _count(folder: String, counts: Array) -> void:
	var directory := DirAccess.open(folder)
	if directory == null: return
	var files := directory.get_files()
	var folders := directory.get_directories()
	counts[0] += files.size()
	if files.is_empty() and folders.is_empty() and folder != "": counts[1] += 1
	for child in folders: _count(folder.path_join(child), counts)


func open_preferences() -> void:
	var default_output: String = shell.default_output_parent()
	preferences_dialog.show_values(shell.settings.values, shell.folder, shell.folder_report, default_output)
	preferences_dialog.open()


func show_export_result(destination: String, result: Dictionary, comparison: Dictionary, status: String) -> void:
	_exported = destination
	result_dialog.show_result(result, comparison, status)
	result_dialog.open()


## Asks what to do with the unapplied edits before the shell goes on.
func ask_draft(record: String, count: int) -> void:
	draft_dialog.set_details([["Record", record], ["Unapplied", "%d edit%s" % [count, "" if count == 1 else "s"]]])
	draft_dialog.popup_centered()


## Asks whether to save the checkpoint before the shell goes on.
func ask_unsaved(project: String, path: String) -> void:
	unsaved_dialog.heading = "Save changes to %s?" % project
	unsaved_dialog.set_details([["Project", path]])
	unsaved_dialog.popup_centered()
