extends VBoxContainer
## A record list: a title with its count, a filter, scope chips and rows in
## columns. The owner supplies rows; the list reports what the author picks.
signal row_selected(id: Variant)
signal row_activated(id: Variant)
signal filter_changed(text: String)
signal scope_changed(id: Variant)
signal add_requested
## With `multi`, the rows chosen now, as their ids.
signal selection_changed(ids: Array)
const IconButton = preload("res://src/widgets/icon_button.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

@export var title := "":
	set(value): title = value; _title.text = value
@export var filter_placeholder := "Filter":
	set(value): filter_placeholder = value; _filter.placeholder_text = value
## Hide rows that do not contain the filter text, without asking the owner.
@export var filter_locally := true
@export var can_add := false:
	set(value): can_add = value; _add.visible = value
## Rows can be chosen several at a time (Ctrl or Shift); `selection_changed` reports them.
@export var multi := false:
	set(value):
		multi = value
		_tree.select_mode = Tree.SELECT_MULTI if value else Tree.SELECT_ROW

var _title := Label.new()
var _count := Label.new()
var _add := IconButton.new()
var _filter := LineEdit.new()
var _scopes := HFlowContainer.new()
var _tree := Tree.new()
var _columns: Array = []
var _rows: Array = []
var _scope_group := ButtonGroup.new()


func _init() -> void:
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	add_child(head)
	_title.theme_type_variation = &"CaptionMuted"
	_title.uppercase = true
	head.add_child(_title)
	_count.theme_type_variation = &"Kbd"
	_count.visible = false
	head.add_child(_count)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_add.glyph = "plus"
	_add.visible = false
	_add.custom_minimum_size = Vector2(22, 22)
	_add.pressed.connect(func(): add_requested.emit())
	head.add_child(_add)
	_filter.placeholder_text = filter_placeholder
	_filter.clear_button_enabled = true
	_filter.text_changed.connect(func(text): _fill(); filter_changed.emit(text))
	add_child(_filter)
	_scopes.add_theme_constant_override("h_separation", 6)
	_scopes.add_theme_constant_override("v_separation", 6)
	_scopes.visible = false
	add_child(_scopes)
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(func():
		row_selected.emit(selected_id())
		if multi: selection_changed.emit(selected_ids()))
	_tree.multi_selected.connect(func(item, _column, chosen):
		# A row is chosen whole: every cell of it follows the one clicked.
		_tree.set_block_signals(true)
		for cell in range(_tree.columns):
			if chosen: item.select(cell)
			else: item.deselect(cell)
		_tree.set_block_signals(false)
		selection_changed.emit(selected_ids()))
	_tree.item_activated.connect(func(): row_activated.emit(selected_id()))
	add_child(_tree)


## Empties the filter without asking the owner to refill the rows.
func clear_filter() -> void:
	_filter.text = ""


func filter_text() -> String:
	return _filter.text.strip_edges()


func set_count(count: int) -> void:
	_count.text = str(count)
	_count.visible = true


## Each column is {title, width, mono, right}; a width of 0 takes the spare room.
func set_columns(columns: Array) -> void:
	_columns = columns
	_tree.columns = maxi(1, columns.size())
	_tree.column_titles_visible = columns.any(func(column): return not str(column.get("title", "")).is_empty())
	for index in range(columns.size()):
		var column: Dictionary = columns[index]
		var width := int(column.get("width", 0))
		_tree.set_column_title(index, str(column.get("title", "")).to_upper())
		_tree.set_column_title_alignment(index, HORIZONTAL_ALIGNMENT_RIGHT if column.get("right", false) else HORIZONTAL_ALIGNMENT_LEFT)
		_tree.set_column_expand(index, width == 0)
		if width > 0: _tree.set_column_custom_minimum_width(index, width)
	_fill()


## Each scope is {id, label, count}; the first is chosen. `picks` are further choices, {id, label}, offered in a menu after
## the chips (any map of the scenario): choosing one reports its id like a chip.
func set_scopes(scopes: Array, picks := [], pick_label := "Another…") -> void:
	for chip in _scopes.get_children(): _scopes.remove_child(chip); chip.queue_free()
	_scopes.visible = not scopes.is_empty()
	for index in range(scopes.size()):
		var scope: Dictionary = scopes[index]
		var chip := Button.new()
		chip.theme_type_variation = &"Chip"
		chip.toggle_mode = true
		chip.button_group = _scope_group
		chip.text = str(scope.label) + ("  %d" % int(scope.count) if scope.has("count") else "")
		chip.button_pressed = index == 0
		chip.pressed.connect(func(): scope_changed.emit(scope.id))
		_scopes.add_child(chip)
	if picks.is_empty() or scopes.is_empty(): return
	var menu := MenuButton.new()
	menu.theme_type_variation = &"Chip"
	menu.text = pick_label
	menu.flat = false
	var popup := menu.get_popup()
	for index in range(picks.size()): popup.add_item(str(picks[index].label), index)
	popup.id_pressed.connect(func(index): scope_changed.emit(picks[index].id))
	_scopes.add_child(menu)


## Marks the chip at `index` as the chosen scope without reporting it.
func press_scope(index: int) -> void:
	var chips: Array = _scopes.get_children().filter(func(child): return child is Button and child.toggle_mode)
	for number in range(chips.size()): chips[number].set_pressed_no_signal(number == index)


## Each row is {id, cells, dirty}; a dirty row carries the unapplied mark.
func set_rows(rows: Array) -> void:
	_rows = rows
	_fill()


func selected_id() -> Variant:
	var item := _tree.get_selected()
	return item.get_metadata(0) if item != null else null


## The ids of every chosen row.
func selected_ids() -> Array:
	var found: Array = []
	var root := _tree.get_root()
	if root == null: return found
	for item in root.get_children():
		if item.is_selected(0): found.append(item.get_metadata(0))
	return found


## Marks the rows with these ids without reporting a selection.
func select_many(ids: Array) -> void:
	var root := _tree.get_root()
	if root == null: return
	_tree.set_block_signals(true)
	for item in root.get_children():
		if item.get_metadata(0) in ids:
			for cell in range(_tree.columns): item.select(cell)
	_tree.set_block_signals(false)


## Marks the row with `id` without reporting a selection.
func select(id: Variant) -> void:
	var root := _tree.get_root()
	if root == null: return
	for item in root.get_children():
		if typeof(item.get_metadata(0)) == typeof(id) and item.get_metadata(0) == id:
			_tree.set_block_signals(true)
			item.select(0)
			_tree.set_block_signals(false)
			_tree.scroll_to_item(item)


func _fill() -> void:
	var chosen: Variant = selected_id()
	_tree.clear()
	var root := _tree.create_item()
	var needle := _filter.text.strip_edges().to_lower()
	for row in _rows:
		var cells: Array = row.get("cells", [])
		if filter_locally and not needle.is_empty() and not " ".join(cells.map(func(cell): return str(cell))).to_lower().contains(needle): continue
		var item := _tree.create_item(root)
		item.set_metadata(0, row.get("id"))
		for index in range(mini(cells.size(), _tree.columns)):
			var column: Dictionary = _columns[index] if index < _columns.size() else {}
			item.set_text(index, str(cells[index]))
			item.set_text_alignment(index, HORIZONTAL_ALIGNMENT_RIGHT if column.get("right", false) else HORIZONTAL_ALIGNMENT_LEFT)
			if column.get("mono", false):
				item.set_custom_font(index, get_theme_font("mono", "EditorTokens"))
				item.set_custom_font_size(index, Tokens.SMALL_SIZE)
				item.set_custom_color(index, Tokens.DIM)
		if row.get("dirty", false):
			item.set_suffix(_tree.columns - 1, " ●")
	if chosen != null: select(chosen)
