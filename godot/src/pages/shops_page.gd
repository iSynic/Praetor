extends HBoxContainer
## Shops: what each shop of the scenario sells and at what price. A shop holds a
## thousand slots of an item id and a quantity, and one price percent of the
## standard prices. Every change is a draft that waits for Apply.
const Card = preload("res://src/widgets/card.gd")
const PageHeader = preload("res://src/widgets/page_header.gd")
const RecordList = preload("res://src/widgets/record_list.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

var shell: Control
var shop_id := 0
var list := RecordList.new()
var header := PageHeader.new()
var price := SpinBox.new()
var new_item := SpinBox.new()
var _stock_card := Card.new()
var _rows := VBoxContainer.new()
var _count := Label.new()
var _saved: Dictionary = {}
var _view: Dictionary = {}
var _loading := false


func _init() -> void:
	list.title = "Shops"
	list.filter_placeholder = "Filter shops"
	list.custom_minimum_size.x = 270
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.set_columns([{"title": "Shop", "width": 0}])
	list.row_selected.connect(func(row): if row != null and not _loading: shell.guard(show_shop.bind(int(row))))
	add_child(list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 10)
	scroll.add_child(centre)
	header.mark(Tokens.FAMILY.reward)
	centre.add_child(header)
	var prices := Card.new()
	prices.title = "Prices"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.theme_type_variation = &"Dim"
	label.text = "Percent of the standard prices (selling is capped at 100; below 0 the buyer is paid and the seller charged)"
	row.add_child(label)
	price.min_value = -32768
	price.max_value = 32767
	price.custom_minimum_size.x = 110
	price.value_changed.connect(func(_value): if not _loading: _price_changed())
	row.add_child(price)
	prices.add_row(row)
	centre.add_child(prices)
	_stock_card.title = "Stock"
	_count.theme_type_variation = &"Dim"
	_stock_card.right.add_child(_count)
	new_item.min_value = 1
	new_item.max_value = 999
	new_item.value = 1
	new_item.custom_minimum_size.x = 90
	new_item.tooltip_text = "The item the Add item buttons stock"
	_stock_card.right.add_child(new_item)
	_rows.add_theme_constant_override("separation", 4)
	_stock_card.add_row(_rows)
	centre.add_child(_stock_card)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 260
	side.add_theme_constant_override("separation", 10)
	add_child(side)
	var facts := Card.new()
	facts.title = "Record"
	for line in ["Data SD · 3,002 bytes a shop", "1,000 slots of an item id and a quantity", "A slot is stocked when its quantity is not zero; the game never reads the item id of an empty slot", "Item ids are 1 to 999; the stock items come from the installation", "The game shows each category in slot order and takes a sale into the category in view"]:
		var text := Label.new()
		text.theme_type_variation = &"Muted"
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.text = line
		facts.add_row(text)
	side.add_child(facts)


func setup(owner_shell: Control) -> void:
	shell = owner_shell


func shop_count() -> int:
	for table in shell.summary.get("tables", []):
		if table.file == "Data SD": return int(table.complete_records)
	return 0


func refresh() -> void:
	if shell.summary.is_empty(): return
	await shell.ensure_item_names()
	_loading = true
	var rows: Array = []
	for index in range(shop_count()): rows.append({"id": index, "cells": ["Shop %d" % index], "dirty": _has_draft(index)})
	list.set_rows(rows)
	list.set_count(rows.size())
	_loading = false
	shop_id = clampi(shop_id, 0, maxi(0, shop_count() - 1))
	await show_shop(shop_id)


func _has_draft(shop: int) -> bool:
	for draft in shell.drafts.values():
		if str(draft.get("kind", "")).begins_with("shop_") and int(draft.shop) == shop: return true
	return false


func show_shop(id: int) -> void:
	shop_id = id
	var response: Dictionary = await shell.request_backend({"op": "shop", "id": id})
	if not response.get("ok", false): return
	_saved = response.result
	_view = _with_drafts(_saved)
	_loading = true
	list.select(id)
	price.value = int(_view.price_percent)
	_loading = false
	_fill()


## The shop as saved with the unapplied edits of it put over it.
func _with_drafts(saved: Dictionary) -> Dictionary:
	var stock: Dictionary = {}
	for entry in saved.stock: stock[int(entry.slot)] = {"item": int(entry.item), "quantity": int(entry.quantity)}
	var percent := int(saved.price_percent)
	for draft in shell.drafts.values():
		if not str(draft.get("kind", "")).begins_with("shop_") or int(draft.shop) != shop_id: continue
		if draft.kind == "shop_price": percent = int(draft.percent)
		else: stock[int(draft.slot)] = {"item": int(draft.item), "quantity": int(draft.quantity)}
	return {"id": shop_id, "price_percent": percent, "stock": stock}


func _fill() -> void:
	for child in _rows.get_children(): _rows.remove_child(child); child.queue_free()
	var slots: Array = _view.stock.keys()
	slots.sort()
	var shown := 0
	# The game keeps a shop's stock in five lists of 200 slots, one for each category.
	for family in range(5):
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		var title := Label.new()
		title.theme_type_variation = &"CaptionMuted"
		title.uppercase = true
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var add := Button.new()
		add.text = "Add item"
		add.theme_type_variation = &"GhostButton"
		add.pressed.connect(func(): add_item(family))
		head.add_child(add)
		_rows.add_child(head)
		var count := 0
		for slot in slots:
			if int(slot) < family * 200 or int(slot) >= family * 200 + 200: continue
			var entry: Dictionary = _view.stock[slot]
			if int(entry.quantity) == 0: continue
			count += 1
			_rows.add_child(_row(int(slot), entry))
		shown += count
		title.text = "Category %d  ·  %d of 200" % [family + 1, count]
	_count.text = "%d of %d slots" % [shown, int(_saved.slots)]
	header.title.text = "Shop %d" % shop_id
	header.sub.text = "Data SD · record %d · %d slots in use" % [shop_id, shown]
	header.show_badges([["unapplied", &"BadgeWarn"]] if _has_draft(shop_id) else [])


func _row(slot: int, entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var number := Label.new()
	number.theme_type_variation = &"MonoDim"
	number.text = "slot %d" % slot
	number.custom_minimum_size.x = 70
	row.add_child(number)
	var item := SpinBox.new()
	item.min_value = mini(1, int(entry.item))
	item.max_value = 999
	item.custom_minimum_size.x = 110
	item.set_value_no_signal(int(entry.item))
	row.add_child(item)
	shell.references.attach(row, item, "item")
	var times := Label.new()
	times.theme_type_variation = &"Dim"
	times.text = "×"
	row.add_child(times)
	var quantity := SpinBox.new()
	quantity.min_value = mini(1, int(entry.quantity))
	quantity.max_value = 255
	quantity.custom_minimum_size.x = 90
	quantity.set_value_no_signal(int(entry.quantity))
	row.add_child(quantity)
	item.value_changed.connect(func(_value): stock_edit(slot, int(item.value), int(quantity.value)))
	quantity.value_changed.connect(func(_value): stock_edit(slot, int(item.value), int(quantity.value)))
	var clear := Button.new()
	clear.text = "Clear"
	clear.theme_type_variation = &"GhostButton"
	clear.pressed.connect(func(): stock_edit(slot, 0, 0); _fill())
	row.add_child(clear)
	return row


## A slot's new item and quantity, as a draft, or none when it is as saved.
func stock_edit(slot: int, item: int, quantity: int) -> void:
	if shell.summary.is_empty(): return
	var key := "shop_stock:%d:%d" % [shop_id, slot]
	var saved := {"item": 0, "quantity": 0}
	for entry in _saved.stock:
		if int(entry.slot) == slot: saved = {"item": int(entry.item), "quantity": int(entry.quantity)}
	if saved.item == item and saved.quantity == quantity: shell.drafts.erase(key)
	else: shell.drafts[key] = {"kind": "shop_stock", "shop": shop_id, "slot": slot, "item": item, "quantity": quantity}
	_view.stock[slot] = {"item": item, "quantity": quantity}
	_changed()


func _price_changed() -> void:
	var key := "shop_price:%d" % shop_id
	if int(price.value) == int(_saved.price_percent): shell.drafts.erase(key)
	else: shell.drafts[key] = {"kind": "shop_price", "shop": shop_id, "percent": int(price.value)}
	_changed()


## Stocks the chosen item in a category the way the game takes a sale in: one
## more where the category already holds it, else in its first empty slot.
func add_item(family: int) -> void:
	if shell.summary.is_empty(): return
	var id := int(new_item.value)
	for slot in range(family * 200, family * 200 + 200):
		var entry: Dictionary = _view.stock.get(slot, {"item": 0, "quantity": 0})
		if int(entry.quantity) != 0 and int(entry.item) == id:
			stock_edit(slot, id, mini(255, int(entry.quantity) + 1))
			_fill()
			return
	for slot in range(family * 200, family * 200 + 200):
		var entry: Dictionary = _view.stock.get(slot, {"item": 0, "quantity": 0})
		if int(entry.quantity) == 0:
			stock_edit(slot, id, 1)
			_fill()
			return
	shell.status("This category's 200 slots are all in use", "warn")


func _changed() -> void:
	shell._invalidate_receipt()
	shell._update_buttons()
	header.show_badges([["unapplied", &"BadgeWarn"]] if _has_draft(shop_id) else [])
