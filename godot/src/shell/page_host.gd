extends Container
## Shows one page at a time and gives it the whole content area.

@export var padding := 16
var current_tab := 0:
	set(value):
		current_tab = value
		for index in range(get_child_count()): get_child(index).visible = index == value
		queue_sort()


func _ready() -> void:
	current_tab = current_tab


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var area := Rect2(Vector2(padding, padding), size - Vector2(padding, padding) * 2.0)
		for child in get_children():
			if child is Control: fit_child_in_rect(child, area)


func _get_minimum_size() -> Vector2:
	var smallest := Vector2.ZERO
	if current_tab < get_child_count() and get_child(current_tab) is Control:
		smallest = get_child(current_tab).get_combined_minimum_size()
	return smallest + Vector2(padding, padding) * 2.0
