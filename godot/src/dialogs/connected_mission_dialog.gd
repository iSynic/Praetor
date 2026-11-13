extends "res://src/widgets/modal_overlay.gd"
## The panel of the connected mission recipe. The recipe itself, its fields and
## the request live in mission_recipe.gd; this is only the window it is shown in.


## Shown the way the former window was, so callers and checks keep their names.
func popup_centered(_size := Vector2i.ZERO) -> void:
	open()
