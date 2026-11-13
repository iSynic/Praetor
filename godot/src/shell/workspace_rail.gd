extends PanelContainer
## The workspace rail: every workspace of the design in its section, with
## record counts and the locks on Items and Shops.
signal route_requested(route: String)
signal problems_requested
const RailButton = preload("res://src/shell/rail_button.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

# [name, glyph, route]. A route names the page the workspace opens; an empty
# route is a workspace whose own page has not been built yet.
const SECTIONS := [
	["World", [["Maps", "maps", "Maps"], ["Stages", "stages", "Stages"], ["Calendar", "calendar", "Calendar"], ["Notes", "messages", "Notes"]]],
	["Story", [["Triggers", "triggers", "Programs:walking"], ["Stories", "stories", "Programs:story"], ["Encounters", "encounters", "Programs:menu"], ["Messages", "messages", "Messages"], ["Texts", "messages", "Texts"]]],
	["Combat", [["Battles", "battles", "Combat"], ["Monsters", "monsters", "Records:monster"]]],
	["Records", [["Rewards", "rewards", "Records:reward"], ["Items", "items", "Items"], ["Shops", "shops", "Shops"], ["Resources", "folder", "Resources"]]],
	["Release", [["Problems", "problems", "Problems"], ["Export", "export", "Export"]]],
]
const PAGE_TITLES := {"Programs": "Triggers & encounters", "Combat": "Battles & monsters", "Stages": "Stages & startup"}

var _buttons: Dictionary = {}
var _captions: Array = []


func _ready() -> void:
	for section in SECTIONS:
		var heading := Label.new()
		heading.text = section[0]
		heading.uppercase = true
		heading.theme_type_variation = &"Caption"
		heading.add_theme_font_size_override("font_size", 9)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		%Entries.add_child(heading)
		_captions.append(heading)
		for entry in section[1]:
			var button := RailButton.new()
			var route: String = entry[2]
			button.caption = entry[0]
			button.glyph = entry[1]
			button.name = "Export" if entry[0] == "Export" else entry[0] + "Workspace"
			button.tooltip_text = PAGE_TITLES.get(route, entry[0])
			if route == "Problems": button.alert = true
			match route:
				"": button.disabled = true
				"locked": button.disabled = true; button.locked = true
				"problems": button.alert = true; button.toggle_mode = true; button.pressed.connect(func(): problems_requested.emit())
				_:
					button.toggle_mode = true
					button.pressed.connect(func(): route_requested.emit(route))
					# Export waits for a project to export.
					if entry[0] == "Export": button.disabled = true
			%Entries.add_child(button)
			_buttons[entry[0]] = {"button": button, "route": route}
	get_viewport().size_changed.connect(_fit)
	_fit()


## Marks the workspace whose page is showing; pages off the rail mark none.
func show_route(route: String) -> void:
	for entry in _buttons.values():
		if entry.route not in ["problems", "locked", ""]: entry.button.set_pressed_no_signal(entry.route == route)


## The dock's state is shown by the dock; the rail's Problems stands for the page.
func show_problems(_opened: bool) -> void:
	pass


## `counts` maps a workspace name to its record count; a missing name shows none.
func show_counts(counts: Dictionary) -> void:
	for name in _buttons: _buttons[name].button.count = int(counts.get(name, -1))


# Names are dropped when the window is too short to show every workspace with one.
func _fit() -> void:
	var compact: bool = get_viewport_rect().size.y < 920.0
	for entry in _buttons.values(): entry.button.compact = compact
	for heading in _captions: heading.visible = not compact
