extends GridContainer
## What a project holds, as a grid of counted tiles.
const StatTile = preload("res://src/widgets/stat_tile.gd")

# [key in the project's contents, name shown].
const TILES := [["maps", "Maps"], ["stages", "Stages"], ["walking_tables", "Walking triggers"], ["stories", "Stories"],
	["messages", "Messages"], ["choices", "Choices"], ["typed", "Typed"], ["battles", "Battles"], ["calendar", "Calendar entries"],
	["monsters", "Monsters"], ["rewards", "Rewards"]]


func _init() -> void:
	add_theme_constant_override("h_separation", 6)
	add_theme_constant_override("v_separation", 6)


## `contents` is the summary's counts; an empty one leaves the grid empty.
func show_contents(contents: Dictionary) -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	if contents.is_empty(): return
	for tile in TILES:
		var count := int(contents.get(tile[0], 0))
		var value := str(count)
		if tile[0] == "stages": value = "%d · %d in use" % [count, int(contents.get("stages_in_use", 0))]
		elif tile[0] == "walking_tables": value = "%d tables" % count
		var widget := StatTile.new()
		widget.value = value
		widget.caption = tile[1]
		widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(widget)
