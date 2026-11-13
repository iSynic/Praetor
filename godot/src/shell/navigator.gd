extends RefCounted
## Takes the author to a record: the page that edits it, with it chosen. Go to,
## Find uses, View flow and the Problems list all arrive here.
const FAMILY_OF := {"walking": "walking", "story": "story", "choice": "menu", "typed": "typed"}
const NOUNS := {"monster": "Monster", "battle": "Battle", "message": "Message", "reward": "Reward", "walking": "W", "story": "Story", "choice": "Choice", "typed": "Typed", "stage": "Stage", "battle_extra": "Battle extra"}
const WORKSPACES := {"monster": "Monsters", "battle": "Battles", "message": "Messages", "reward": "Rewards", "walking": "Triggers", "story": "Stories", "choice": "Encounters", "typed": "Encounters", "stage": "Stages", "battle_extra": "Battle extras"}

var shell: Control


func _init(owner_shell: Control) -> void:
	shell = owner_shell


## Shows the record `kind` `id`; for a program, `slot` chooses one of its steps.
func go(kind: String, id: int, slot := -1, branch := 0) -> void:
	if shell.summary.is_empty(): return
	match kind:
		"monster", "reward", "battle_extra": await shell.record_ui.open_record(kind, id)
		"battle": await shell.combat.open_battle(id)
		"message":
			await shell._show_route(shell.ROUTES.find("Messages"))
			await shell.messages.load_message(id)
		"text":
			shell.texts_page.text_id = id
			await shell._show_route(shell.ROUTES.find("Texts"))
		"item":
			shell.items_page.index = id - 800
			await shell._show_route(shell.ROUTES.find("Items"))
		"shop":
			shell.shops_page.shop_id = id
			await shell._show_route(shell.ROUTES.find("Shops"))
		"stage":
			shell.stages.stage_id = id
			await shell._show_route(shell.ROUTES.find("Stages"))
		"walking", "story", "choice", "typed":
			await shell._choose_program(FAMILY_OF[kind], id, branch)
			await shell._show_route(shell.ROUTES.find("Programs"))
			if slot >= 0: await shell.programs.select_step(branch, slot)
		"file": await shell._show_route(shell.ROUTES.find("Inspection"))


## Shows a cell of the open map.
func go_to_cell(cell: Vector2i) -> void:
	await shell._show_route(shell.ROUTES.find("Maps"))
	var canvas: Control = shell.ui("MapCanvas")
	if canvas.floor_values.size() > cell.x * 90 + cell.y: shell._map_cell_selected(cell, int(canvas.floor_values[cell.x * 90 + cell.y]))


## Where a finding or a use points: {kind, id, slot, branch, file}.
func go_where(place: Dictionary) -> void:
	var kind := str(place.get("kind", ""))
	if kind == "record":
		var by_file := {"Data ED3": "story", "Data ED": "choice", "Data ED2": "typed", "Data MD": "monster", "Data BD": "battle", "Data TD": "reward", "Data SD2": "message", "Data EDCD": "battle_extra", "Data Mission": "stage"}
		kind = by_file.get(str(place.get("file", "")), "file")
	if kind == "region":
		await shell._select_map(int(place.map))
		await shell._show_route(shell.ROUTES.find("Maps"))
		shell.maps.select_region(int(place.slot))
		return
	if kind == "calendar":
		shell.calendar_page.slot = int(place.get("id", 0))
		await shell._show_route(shell.ROUTES.find("Calendar"))
		return
	if kind == "cell":
		await shell._select_map(int(place.map))
		await go_to_cell(Vector2i(int(place.x), int(place.y)))
		return
	if kind in ["file", "records", ""]:
		await go("file", 0)
	else:
		await go(kind, int(place.get("id", 0)), int(place.get("slot", -1)) if place.get("slot") != null else -1, int(place.get("branch", 0)))
