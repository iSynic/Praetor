extends SceneTree
## Drives the record workspaces on the real renderer: Messages with its byte
## count and preview, Stages, the Battles grid with placing and erasing, the
## Monsters and Rewards forms, the locked Items and Shops, Author records, the
## record pickers and the Connected mission panel. Needs CENTURIONS_PROJECT to
## be an imported level, CENTURIONS_INSTALLATION and CENTURIONS_CAPTURE_OUT.
var shell: Control
var out := ""
var failures: Array = []


func _initialize() -> void:
	call_deferred("run")


func settle() -> void:
	while shell.bridge.busy: await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func snapshot(name: String) -> void:
	await settle()
	var image := root.get_texture().get_image()
	if image == null or image.save_png(out.path_join(name + ".png")) != OK: failures.append(name)


func expect(passed: bool, message: String) -> void:
	if not passed: failures.append(message)


func inside(dialog: Control, label: String, size: Vector2i) -> void:
	if not Rect2(Vector2.ZERO, Vector2(size)).encloses(dialog.panel_rect()): failures.append("%s exceeds the %s window: %s" % [label, str(size), str(dialog.panel_rect())])


func run() -> void:
	create_timer(170).timeout.connect(func(): push_error("Records capture timed out"); quit(99))
	root.gui_embed_subwindows = true
	out = OS.get_environment("CENTURIONS_CAPTURE_OUT")
	if out.is_empty(): push_error("CENTURIONS_CAPTURE_OUT required"); quit(1); return
	shell = load("res://src/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await shell.startup_completed
	for size in [Vector2i(1600, 900), Vector2i(1200, 720)]:
		root.size = size
		await session(size)
	shell.bridge.stop()
	if failures.is_empty(): print("CENTURIONS_RECORD_CAPTURES_PASSED")
	else: push_error("Record capture failures: " + str(failures))
	quit(0 if failures.is_empty() else 1)


func session(size: Vector2i) -> void:
	var tag := "%dx%d" % [size.x, size.y]
	# Messages: the byte count and the in-game preview follow the text.
	await shell._show_route(shell.ROUTES.find("Messages"))
	await shell.messages.select_message(0)
	await shell.messages.check_text()
	expect(shell.ui("MessageBytes").text.contains("/ 255"), "The message must show its byte count against the limit")
	await snapshot(tag + "-messages")
	await shell._show_route(shell.ROUTES.find("Stages"))
	await snapshot(tag + "-stages")
	# Battles: a placement is one draft, and putting the cell back leaves none.
	await shell.combat.open_battle(1)
	var combat: Control = shell.combat
	expect(combat.population.cells.size() == 676, "A battle must show its 26 × 26 population")
	var cell := Vector2i(0, 0)
	var before: int = int(combat.population.cells[0])
	combat.select_tool("place")
	combat._brush.value = 17
	combat._put(cell, 17)
	expect(shell.drafts.has("battle_population:1"), "Placing a monster must draft the population")
	combat._put(cell, before)
	expect(not shell.drafts.has("battle_population:1"), "Restoring the cell must leave no draft")
	combat._put(cell, 17)
	await snapshot(tag + "-battles-placed")
	# A battle's distance is a draft of its own, and putting it back leaves none.
	var distance: SpinBox = null
	for node in combat._battle.get_children():
		for child in node.get_children():
			if child is SpinBox and child.max_value == 127 and child.min_value == -128: distance = child
	expect(distance != null, "A battle must offer its starting distance")
	if distance != null:
		var saved_distance: int = int(distance.value)
		distance.value = saved_distance + 1
		expect(shell.drafts.has("battle_setting:1:distance:0"), "A changed distance must be a draft")
		distance.value = saved_distance
		expect(not shell.drafts.has("battle_setting:1:distance:0"), "The saved distance must leave no draft")
	await shell._discard_continue()
	combat.select_tool("select")
	# Monsters and Rewards.
	await shell._show_named_route("Records:monster")
	await shell.record_ui.select_id(1)
	expect(shell.record_ui.list._tree.get_root().get_child_count() > 100, "The monster list must hold every row")
	await snapshot(tag + "-monsters")
	var spins: Dictionary = shell.record_ui._monster_spins
	expect(spins.has("armor:0") and spins.has("save:5") and spins.has("attack_maximum:4") and spins.has("spell9") and spins.has("run_percent"), "The monster form must list the definition's fields")
	var armor: int = int(spins["armor:0"].value)
	spins["armor:0"].value = armor + 3
	spins["run_percent"].value = 25
	expect(shell.drafts.has("monster_field:1:armor:0") and shell.drafts.has("monster_retreat_threshold:1"), "Each changed field is a draft")
	spins["armor:0"].value = armor
	expect(not shell.drafts.has("monster_field:1:armor:0"), "A field put back leaves no draft")
	spins["armor:0"].value = armor + 3
	expect(await shell.apply_draft(), "A monster field edit must apply")
	await shell.record_ui.refresh()
	expect(int(shell.record_ui._monster_spins["armor:0"].value) == armor + 3 and int(shell.record_ui._monster_spins["run_percent"].value) == 25, "Applied fields are saved")
	await shell._history("undo")
	await shell.record_ui.refresh()
	expect(int(shell.record_ui._monster_spins["armor:0"].value) == armor, "Undo takes the field back")
	# The description is a draft of its own, saved in Data DES, and a duplicate takes its own copy of the imported seed's.
	var words: TextEdit = shell.record_ui._monster_description
	var original := words.text
	words.text = "A description written in the editor."
	words.text_changed.emit()
	expect(shell.drafts.has("monster_description:1"), "A changed description is a draft")
	words.text = original
	words.text_changed.emit()
	expect(not shell.drafts.has("monster_description:1"), "The saved description leaves no draft")
	words.text = "A description written in the editor."
	words.text_changed.emit()
	expect(await shell.apply_draft(), "A description must apply")
	await shell.record_ui.refresh()
	expect(shell.record_ui._monster_description.text == "A description written in the editor.", "The applied description is shown")
	await shell.record_ui.duplicate()
	await shell.record_ui.refresh()
	expect(int(shell.record_ui.id.value) >= 136 and shell.record_ui._monster_description.text == original, "A duplicate takes a copy of the imported seed's description, as its other fields")
	await snapshot(tag + "-monster-description")
	await shell._history("undo")
	await shell._history("undo")
	await shell.record_ui.select_id(1)
	expect(shell.record_ui._monster_description.text == original, "Undo takes the description back")
	# The vault: it holds the game's own monsters as stock; a changed monster of the scenario can be added, kept apart from
	# the stock, and copied back as a new monster with its description. Only added monsters can be removed.
	var vault = shell.record_ui.vault
	await vault.load_entries()
	var added_keys: Array = vault.entries.filter(func(entry): return not entry.stock).map(func(entry): return entry.key)
	if not added_keys.is_empty(): await shell.request_backend({"op": "vault_remove", "keys": added_keys})
	await vault.load_entries()
	var stock_count: int = vault.entries.size()
	expect(stock_count > 100 and vault.entries.all(func(entry): return entry.stock), "The vault starts with the game's own monsters as stock")
	await vault.add_current()
	expect(vault.entries.size() == stock_count, "A monster the game already has is not added")
	words = shell.record_ui._monster_description
	words.text = "A description written in the editor."
	words.text_changed.emit()
	expect(await shell.apply_draft(), "A changed monster applies")
	await vault.add_current()
	expect(vault.entries.size() == stock_count + 1 and not vault.entries[stock_count].stock and str(vault.entries[stock_count].name) == "Zevon Zealot", "A changed monster is added after the stock")
	await vault.add_all()
	var before_count: int = shell.record_ui.count
	await vault.set_scope("vault")
	var stock_key := str(vault.entries[1].key)
	vault.select([stock_key])
	await shell.record_ui.refresh()
	await snapshot(tag + "-monster-vault")
	expect(shell.record_ui.list.selected_ids() == [stock_key], "A chosen vault monster is selected in the list")
	expect(vault._remove.disabled, "A stock monster cannot be removed")
	var refused: Dictionary = await shell.request_backend({"op": "vault_remove", "keys": [stock_key]})
	expect(not refused.get("ok", false), "The adapter refuses to remove a stock monster")
	var added_key := str(vault.entries[stock_count].key)
	vault.select([added_key])
	await shell.record_ui.refresh()
	expect(not vault._remove.disabled, "An added monster can be removed")
	await vault.copy_to_scenario([stock_key, added_key])
	await shell.record_ui.refresh()
	expect(not vault.active and shell.record_ui.count == before_count + 2 and int(shell.record_ui.id.value) == before_count, "Copying adds the monsters after the last and shows the first")
	await shell._history("undo")
	await shell.record_ui.refresh()
	expect(shell.record_ui.count == before_count, "Undo takes both copies back in one step")
	await shell._history("undo")
	await vault.load_entries()
	await shell.request_backend({"op": "vault_remove", "keys": [added_key]})
	await vault.load_entries()
	expect(vault.entries.size() == stock_count, "Removing takes an added monster out of the vault")
	await shell._show_named_route("Records:reward")
	await shell.record_ui.select_id(0)
	await snapshot(tag + "-rewards")
	var reward_spins: Dictionary = shell.record_ui._reward_spins
	expect(reward_spins.has("item:0") and reward_spins.has("level:19"), "A reward must list its twenty items and levels")
	if reward_spins.has("item:0"):
		var saved_item: int = int(reward_spins["item:0"].value)
		reward_spins["item:0"].value = saved_item + 1
		expect(shell.drafts.has("reward_item:%d:0" % int(shell.record_ui.id.value)), "A changed reward item must be a draft")
		reward_spins["item:0"].value = saved_item
		expect(not shell.drafts.has("reward_item:%d:0" % int(shell.record_ui.id.value)), "The saved item must leave no draft")
	# Items and Shops are locked views.
	await shell._show_route(shell.ROUTES.find("Items"))
	var items: Control = shell.items_page
	expect(shell.item_name(800) == "Rations" and shell.item_name(0) == "Sold Out" and shell.item_name(1) == "Wackmaster .30", "Items are named from the scenario's STR# 801 and the installation's Data ID: " + str([shell.item_name(800), shell.item_name(0), shell.item_name(1)]))
	expect(items.header.title.text == "Item 800 · Rations", "The item's name heads its page")
	expect(items.spins.has("price:0") and items.spins.has("elemental_damage:6") and items.spins.has("armor:0"), "The item form must list the definition's fields")
	var weight: int = int(items.spins["weight:0"].value)
	items.spins["weight:0"].value = weight + 2
	expect(shell.drafts.has("item_field:0:weight:0"), "A changed item field is a draft")
	items.description.text = "Mmm! Changed."
	items._description_changed()
	items.name_field.text = "Ration Pack"
	items._name_changed()
	expect(shell.drafts.has("item_name:0"), "A changed name is a draft")
	expect(shell.drafts.has("item_description:0"), "A changed description is a draft")
	expect(await shell.apply_draft(), "An item edit must apply")
	await items.show_item(0)
	expect(int(items.spins["weight:0"].value) == weight + 2 and items.description.text == "Mmm! Changed.", "Applied item edits are saved")
	expect(shell.item_name(800) == "Ration Pack" and items.name_field.text == "Ration Pack", "An applied name is saved and listed")
	await snapshot(tag + "-items")
	await shell._history("undo")
	await items.show_item(0)
	expect(int(items.spins["weight:0"].value) == weight, "Undo takes the item edit back")
	expect(items.name_field.text == "Rations", "Undo takes the name back")
	await shell._show_route(shell.ROUTES.find("Shops"))
	expect(shell.shops_page.shop_count() > 0, "The scenario must hold shops")
	shell.shops_page.new_item.value = 999
	shell.shops_page.add_item(4)
	expect(shell.drafts.keys().any(func(key): return str(key).begins_with("shop_stock:")), "Adding an item drafts the slot")
	var stocked: int = shell.shops_page._saved.stock.size()
	expect(await shell.apply_draft(), "A shop edit must apply")
	await shell.shops_page.show_shop(shell.shops_page.shop_id)
	expect(shell.shops_page._saved.stock.size() == stocked + 1, "An applied slot is saved")
	await snapshot(tag + "-shops")
	await shell._history("undo")
	await shell.shops_page.show_shop(shell.shops_page.shop_id)
	expect(shell.shops_page._saved.stock.size() == stocked, "Undo takes the slot away")
	await snapshot(tag + "-shops-locked")
	# Author records, both modes.
	await shell.author_dialog.show_for("monster")
	await settle()
	inside(shell.author_dialog, "author-open", size)
	await snapshot(tag + "-author-open")
	shell.author_dialog._clone_button.button_pressed = true
	shell.author_dialog._set_mode(true)
	await shell.author_dialog._load()
	await settle()
	inside(shell.author_dialog, "author-clone", size)
	await snapshot(tag + "-author-clone")
	shell.author_dialog.close()
	shell.author_dialog._set_mode(false)
	# The pickers.
	await shell.picker_dialog.show_for("battle", 1, "Extra 58 · battle")
	await settle()
	inside(shell.picker_dialog, "pick-battle", size)
	await snapshot(tag + "-pick-battle")
	shell.picker_dialog.close()
	await shell.picker_dialog.show_for("reward", 0, "Story 78 · step 7")
	await settle()
	inside(shell.picker_dialog, "pick-reward", size)
	await snapshot(tag + "-pick-reward")
	shell.picker_dialog.close()
	# The connected mission panel.
	shell.mission_ui.window.popup_centered()
	await shell.mission_ui._refresh()
	await settle()
	await settle()
	inside(shell.mission_ui.window, "connected-mission", size)
	await snapshot(tag + "-connected-mission")
	expect(shell.mission_ui._adds.get_child_count() == 8, "The panel must list what the recipe adds")
	shell.mission_ui.window.close()
