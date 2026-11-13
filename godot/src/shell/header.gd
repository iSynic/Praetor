extends PanelContainer
## The header: the editor's name and open project, the menus, the Go to field,
## undo and redo, Check, Save and Play from here.
signal command(name: String)
const CTRL := KEY_MASK_CTRL
const SHIFT := KEY_MASK_SHIFT

# [label, command, key]. An empty command is an entry whose screen is not built
# yet; null is a rule between groups. The key is shown beside the entry and
# run by the shell (see command_for_key).
const MENUS := {
	"File": [["Import level…", "import", CTRL | KEY_I], ["Open checkpoint…", "open", CTRL | KEY_O], ["New from template…", "new", CTRL | KEY_N],
		["Open recent", "recent", 0], null,
		["Save new checkpoint…", "save", CTRL | KEY_S], ["Export native level…", "export", CTRL | KEY_E], null,
		["Match a local validation receipt…", "receipt", 0], ["Preferences…", "preferences", CTRL | KEY_COMMA], null,
		["Close project", "close", CTRL | KEY_W]],
	"Edit": [["Undo", "undo", CTRL | KEY_Z], ["Redo", "redo", CTRL | KEY_Y], null,
		["Apply edits", "apply", CTRL | KEY_ENTER], ["Revert form", "revert", 0], null,
		["Go to…", "goto", CTRL | KEY_K], ["Find uses", "find_uses", CTRL | SHIFT | KEY_F], null,
		["Author records…", "author", 0], ["Connected mission…", "mission", 0]],
	"View": [["Maps", "route:Maps", CTRL | KEY_1], ["Stages", "route:Stages", CTRL | KEY_2], ["Triggers", "route:Programs:walking", CTRL | KEY_3],
		["Stories", "route:Programs:story", CTRL | KEY_4], ["Encounters", "route:Programs:menu", CTRL | KEY_5], ["Messages", "route:Messages", CTRL | KEY_6],
		["Battles", "route:Combat", CTRL | KEY_7], ["Monsters", "route:Records:monster", CTRL | KEY_8], ["Rewards", "route:Records:reward", CTRL | KEY_9],
		["Items", "route:Items", 0], ["Shops", "route:Shops", 0], ["Texts", "route:Texts", 0], ["Resources", "route:Resources", 0], ["Calendar", "route:Calendar", 0], ["Notes", "route:Notes", 0], null,
		["Problems", "problems", CTRL | KEY_J], ["View flow", "view_flow", 0], null,
		["Project", "route:Project", 0], ["Inspection", "route:Inspection", 0]],
	"Map": [["Select", "map:select", KEY_V], ["Sample", "map:sample", KEY_I], null, ["Paint", "map:paint", KEY_B], ["Line", "map:line", KEY_L], ["Rectangle", "map:rectangle", KEY_R], ["Fill", "map:fill", KEY_G], null,
		["Trigger", "map:trigger", KEY_T], ["Region", "map:region", KEY_E], ["Start", "map:start", KEY_S], ["Erase", "map:erase", KEY_X], null,
		["New at selected cell", "map:new", KEY_N], ["Choose floor…", "map:choose_floor", 0], ["Add map…", "map:add_map", 0], ["Remove the last map…", "map:remove_map", 0], null,
		["Grid", "map:grid", 0], ["Zoom", "zoom", 0]],
	"Play": [["Play from here", "play", KEY_F5], ["Stop", "stop", SHIFT | KEY_F5], null, ["Check", "check", CTRL | KEY_PERIOD]],
	"Help": [["Guide to the editor", "guide", KEY_F2], ["Code helper", "helper", KEY_F1], ["Technical details", "technical", 0]],
}

# The keys beside Check, Save and Play from here; a window narrower than this
# many pixels drops them to keep the commands on one row.
const HINTS := {"Check": "Ctrl .", "Save": "Ctrl S", "PlayFromHere": "F5"}
const KEYCAP_WIDTH := 1400.0

var _items: Dictionary = {}
var _keys: Dictionary = {}
var _recent: PopupMenu
var _burger := MenuButton.new()


func _ready() -> void:
	for title in MENUS:
		var button: MenuButton = get_node("%Menu" + title)
		button.set_disable_shortcuts(true)
		var menu: PopupMenu = button.get_popup()
		for entry in MENUS[title]:
			if entry == null: menu.add_separator(); continue
			var index := menu.item_count
			if entry[1] == "zoom":
				var zoom := PopupMenu.new()
				zoom.name = "ZoomMenu"
				menu.add_child(zoom)
				menu.add_submenu_node_item(entry[0], zoom)
				for level in [1, 2, 3]:
					zoom.add_item("%d×" % level)
					zoom.set_item_metadata(zoom.item_count - 1, "map:zoom:%d" % level)
					_items["map:zoom:%d" % level] = [zoom, zoom.item_count - 1]
				zoom.index_pressed.connect(func(at): command.emit(str(zoom.get_item_metadata(at))))
				continue
			if entry[1] == "recent":
				_recent = PopupMenu.new()
				_recent.name = "RecentMenu"
				menu.add_child(_recent)
				menu.add_submenu_node_item(entry[0], _recent)
				_recent.index_pressed.connect(func(at): if str(_recent.get_item_metadata(at)) != "": command.emit(str(_recent.get_item_metadata(at))))
				set_recents([])
				continue
			menu.add_item(entry[0])
			menu.set_item_disabled(index, entry[1] == "")
			menu.set_item_metadata(index, entry[1])
			if entry[2] != 0: menu.set_item_accelerator(index, entry[2])
			if entry[1] != "":
				_items[entry[1]] = [menu, index]
				if entry[2] != 0: _keys[entry[2]] = entry[1]
			if entry[1].begins_with("route:") or entry[1] == "problems": menu.set_item_as_checkable(index, true)
		menu.index_pressed.connect(func(index): if str(menu.get_item_metadata(index)) != "": command.emit(str(menu.get_item_metadata(index))))
	_burger.text = "≡"
	_burger.flat = true
	_burger.visible = false
	_burger.tooltip_text = "Menu"
	_burger.set_disable_shortcuts(true)
	_burger.get_popup().about_to_popup.connect(_fill_burger)
	get_node("CommandBar").add_child(_burger)
	get_node("CommandBar").move_child(_burger, 0)
	get_viewport().size_changed.connect(_fit)
	_fit()
	%GuideMark.icon = preload("res://theme/editor_mark.png")
	%GuideMark.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	%GuideMark.add_theme_constant_override("icon_max_width", 28)
	%GuideMark.pressed.connect(func(): command.emit("guide"))
	%GoTo.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	%GoTo.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: command.emit("goto"))
	%Undo.pressed.connect(func(): command.emit("undo"))
	%Redo.pressed.connect(func(): command.emit("redo"))
	%Save.pressed.connect(func(): command.emit("save"))
	%Check.pressed.connect(func(): command.emit("check"))
	%PlayFromHere.pressed.connect(func(): command.emit("play"))


## In the compact layout the menus fold into one button.
func set_compact(on: bool) -> void:
	get_node("CommandBar/Menus").visible = not on
	_burger.visible = on


## The folded menu lists each menu as a submenu with the entries as they stand.
func _fill_burger() -> void:
	var popup := _burger.get_popup()
	for child in popup.get_children(): popup.remove_child(child); child.queue_free()
	popup.clear()
	for title in MENUS:
		var copy := PopupMenu.new()
		copy.name = title + "Folded"
		popup.add_child(copy)
		_copy_menu(_menu_button(title).get_popup(), copy)
		popup.add_submenu_node_item(title, copy)


func _menu_button(title: String) -> MenuButton:
	return get_node("%Menu" + title)


func _copy_menu(source: PopupMenu, target: PopupMenu) -> void:
	for index in range(source.item_count):
		if source.is_item_separator(index):
			target.add_separator()
			continue
		var submenu := source.get_item_submenu_node(index)
		if submenu != null:
			var copy := PopupMenu.new()
			copy.name = str(submenu.name) + "Folded"
			target.add_child(copy)
			_copy_menu(submenu, copy)
			target.add_submenu_node_item(source.get_item_text(index), copy)
			continue
		target.add_item(source.get_item_text(index))
		var at := target.item_count - 1
		target.set_item_disabled(at, source.is_item_disabled(index))
		target.set_item_metadata(at, source.get_item_metadata(index))
		target.set_item_accelerator(at, source.get_item_accelerator(index))
		if source.is_item_checkable(index):
			target.set_item_as_checkable(at, true)
			target.set_item_checked(at, source.is_item_checked(index))
	target.index_pressed.connect(func(at): if str(target.get_item_metadata(at)) != "": command.emit(str(target.get_item_metadata(at))))


## The command a key press runs, or "" when the key means nothing here or its
## entry is unavailable.
func command_for_key(event: InputEventKey) -> String:
	var keycode: int = event.keycode
	if event.ctrl_pressed: keycode |= KEY_MASK_CTRL
	if event.shift_pressed: keycode |= KEY_MASK_SHIFT
	if event.alt_pressed: keycode |= KEY_MASK_ALT
	var name: String = _keys.get(keycode, "")
	if name.is_empty() or _items[name][0].is_item_disabled(_items[name][1]): return ""
	return name


## A menu entry is available exactly when its button is.
func set_available(name: String, available: bool) -> void:
	if _items.has(name): _items[name][0].set_item_disabled(_items[name][1], not available)


## The File menu's entries that need an open project.
func set_project_open(opened: bool) -> void:
	for name in ["close", "revert"]: set_available(name, opened)


## Lists the projects opened before under File ▸ Open recent.
func set_recents(list: Array) -> void:
	if _recent == null: return
	_recent.clear()
	if list.is_empty():
		_recent.add_item("No recent projects")
		_recent.set_item_disabled(0, true)
		_recent.set_item_metadata(0, "")
		return
	for index in range(list.size()):
		_recent.add_item("%s · %s" % [str(list[index].get("name", "")), str(list[index].get("path", "")).get_file()])
		_recent.set_item_metadata(index, "recent:%d" % index)


func show_route(route: String, crumb: String) -> void:
	%Breadcrumb.text = crumb
	%GoToPlaceholder.text = "Go to a recent project or folder…" if route == "Project" else "Go to map, trigger, story, message or cell…"
	%GoTo.modulate = Color(1, 1, 1, 0.6 if route == "Project" else 1.0)
	for name in _items:
		if name.begins_with("map:"): _items[name][0].set_item_disabled(_items[name][1], route != "Maps")
		if name in ["helper", "technical"]: _items[name][0].set_item_disabled(_items[name][1], not route.begins_with("Programs"))
	if _items.has("map:grid"): _items["map:grid"][0].set_item_as_checkable(_items["map:grid"][1], true)
	for name in _items:
		if name.begins_with("route:"): _items[name][0].set_item_checked(_items[name][1], name == "route:" + route)


## The Map menu's Grid entry follows the grid choice.
func show_grid(on: bool) -> void:
	if _items.has("map:grid"): _items["map:grid"][0].set_item_checked(_items["map:grid"][1], on)


func show_problems(opened: bool) -> void:
	_items.problems[0].set_item_checked(_items.problems[1], opened)


## The Save button carries a mark while the checkpoint is behind the edits.
func show_unsaved(unsaved: bool) -> void:
	%Save.marked = unsaved


func _fit() -> void:
	var wide := get_viewport_rect().size.x >= KEYCAP_WIDTH
	for name in HINTS: get_node("%" + name).hint = HINTS[name] if wide else ""
