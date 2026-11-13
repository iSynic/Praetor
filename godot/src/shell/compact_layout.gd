extends RefCounted
## The compact layout: below 1600 pixels, with the Preferences choice on, the
## menus fold into one button, the record list and the inspector of a page
## become drawers the tab row opens, and the Problems dock folds into the status
## bar. Nothing is removed; every part opens when it is asked for.
const BREAKPOINT := 1600.0
const PAGES := ["Stages", "Messages", "Maps", "Programs", "Combat", "Records", "Items", "Problems", "Shops"]

var shell: Control
var active := false
## Whether the list and the side of the page in view are open.
var drawers := {"list": false, "side": false}
var _parts: Dictionary = {}
var _started := false


func _init(owner_shell: Control) -> void:
	shell = owner_shell


func setup() -> void:
	_started = true
	shell.get_viewport().size_changed.connect(apply)
	shell.settings.changed.connect(func(key): if key == "compact": apply())
	shell.tabs.list_requested.connect(func(): toggle("list"))
	shell.tabs.side_requested.connect(func(): toggle("side"))
	shell.status_bar.problems_requested.connect(func(): shell.problems.open(not shell.problems.is_open()))
	apply()


## Whether the window is narrow enough, and the author has not turned it off.
func wanted() -> bool:
	return bool(shell.settings.get_value("compact")) and shell.get_viewport_rect().size.x < BREAKPOINT


func apply() -> void:
	active = wanted()
	shell.header.set_compact(active)
	shell.problems.set_compact(active)
	shell.status_bar.set_compact(active)
	show_parts()


## The page changed: its drawers start closed.
func route_changed() -> void:
	if not _started: return
	drawers = {"list": false, "side": false}
	show_parts()


func toggle(which: String) -> void:
	if not active: return
	drawers[which] = not drawers[which]
	show_parts()


## The list and the side of a page: its first and last parts when it has three,
## its first when it has two.
func parts_of(route: String) -> Dictionary:
	if _parts.has(route): return _parts[route]
	var page: Control = shell.pages.get_child(shell.ROUTES.find(route))
	var found: Array = page.get_children().filter(func(child): return child is Control and child.visible)
	var parts := {"list": found[0] if found.size() >= 2 else null, "side": found[found.size() - 1] if found.size() >= 3 else null}
	_parts[route] = parts
	return parts


func show_parts() -> void:
	var current: String = shell.ROUTES[shell.pages.current_tab]
	for route in PAGES:
		var parts := parts_of(route)
		var showing: bool = route == current
		if parts.list != null: parts.list.visible = not active or (showing and drawers.list)
		if parts.side != null: parts.side.visible = not active or (showing and drawers.side)
	var here := parts_of(current) if current in PAGES else {"list": null, "side": null}
	shell.tabs.set_compact(active, here.list != null, here.side != null, drawers.list, drawers.side)
