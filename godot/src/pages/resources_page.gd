extends VBoxContainer
## Resources: the pictures, icons and sounds the scenario holds and the ones it uses from the game. A file is
## imported as a new resource of the scenario, which then takes the place of the game's resource of its number;
## a resource of the scenario can be exported to a file or removed. Every change is a draft until Apply.
const Browser = preload("res://src/widgets/resource_browser.gd")
const PageHeader = preload("res://src/widgets/page_header.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

var shell: Control
var browser := Browser.new()
var header := PageHeader.new()
var _export: Button
var _remove: Button
var _save := FileDialog.new()


func _init() -> void:
	add_theme_constant_override("separation", 12)
	header.title.text = "Resources"
	header.sub.text = "Pictures, icons and sounds the scenario holds, and the ones it uses from the game"
	header.mark(Tokens.FAMILY.media)
	add_child(header)
	var import_button := header.add_button("Import file…")
	import_button.theme_type_variation = &"PrimaryButton"
	import_button.pressed.connect(func(): shell.guard(import_file))
	browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(browser)
	_export = Button.new()
	_export.text = "Export…"
	_export.pressed.connect(func(): _save.popup_centered_ratio(0.6))
	browser.actions.add_child(_export)
	_remove = Button.new()
	_remove.text = "Remove from the scenario"
	_remove.pressed.connect(func(): shell.guard(remove_selected))
	browser.actions.add_child(_remove)
	browser.selected.connect(func(_kind, _id): _show_actions())
	_save.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save.access = FileDialog.ACCESS_FILESYSTEM
	_save.use_native_dialog = true
	_save.file_selected.connect(_export_to)
	add_child(_save)


func setup(owner_shell: Control) -> void:
	shell = owner_shell
	browser.setup(owner_shell)


func refresh() -> void:
	if shell.summary.is_empty(): return
	await shell.references.ensure()
	await browser.open(browser.kind, browser.selected_id)
	_show_actions()


## The number the next import of the kind in view would take: after the scenario's own, or the first of its range.
func _suggest() -> int:
	var bases := {"icon": 3000, "picture": 23350, "sound": 20150}
	var base: int = bases[browser.kind]
	var taken: Array = browser._lists.get(browser.NAMES[browser.kind], {}).get("scenario", [])
	var next: int = base
	for id in taken: next = maxi(next, int(id) + 1)
	for key in shell.drafts:
		var draft: Dictionary = shell.drafts[key]
		if str(draft.get("kind", "")) == "resource_change": next = maxi(next, int(draft.id) + 1) if _type_of(browser.kind) == str(draft.resource_type) else next
	return next


func _type_of(kind: String) -> String:
	return {"icon": "cicn", "picture": "PICT", "sound": "snd "}[kind]


func import_file() -> void:
	shell.import_dialog.show_for(browser.kind, _suggest())


func _show_actions() -> void:
	var entry: Dictionary = browser._lists.get(browser.NAMES[browser.kind], {})
	var mine: bool = browser.selected_id != browser.NONE and entry.get("scenario", []).has(browser.selected_id)
	_export.disabled = browser.selected_id == browser.NONE
	_remove.disabled = not mine
	_save.current_file = "%s %d.%s" % [browser.kind, browser.selected_id, "wav" if browser.kind == "sound" else "png"]


## Marks the resource for removal; steps that use it keep its number.
func remove_selected() -> void:
	var id: int = browser.selected_id
	shell.drafts["resource_change:%s:%d" % [_type_of(browser.kind), id]] = {"kind": "resource_change", "resource_type": _type_of(browser.kind), "id": id, "data": null}
	shell._invalidate_receipt()
	shell._update_buttons()
	shell.status("%s %d will be removed · Apply edits" % [browser.kind.capitalize(), id])


func _export_to(path: String) -> void:
	var response: Dictionary = await shell.request_backend({"op": "export_resource", "kind": browser.kind, "id": browser.selected_id, "destination": path, "installation": shell.folder})
	if response.get("ok", false): shell.status("Exported %s %d" % [browser.kind, browser.selected_id])
