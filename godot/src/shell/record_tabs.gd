extends PanelContainer
## The row of open records above the page. A tab with unapplied edits carries
## a mark.
signal tab_selected(index: int)
signal list_requested
signal side_requested
const Glyph = preload("res://src/widgets/glyph.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

var _mark: Texture2D = Glyph.dot_texture(Tokens.WARN, 7)
var _shown := ""
var _records := Button.new()
var _records_label := "Records"


func _ready() -> void:
	_records.theme_type_variation = &"GhostButton"
	_records.visible = false
	_records.tooltip_text = "The records of this page"
	_records.pressed.connect(func(): list_requested.emit())
	$Row.add_child(_records)
	$Row.move_child(_records, 0)
	%SplitView.tooltip_text = "The inspector of this page"
	%SplitView.pressed.connect(func(): side_requested.emit())


## In the compact layout the list and the inspector are drawers; these open them.
func set_compact(on: bool, has_list: bool, has_side: bool, list_open: bool, side_open: bool) -> void:
	_records.visible = on and has_list
	_records.text = ("%s ‹" if list_open else "%s ›") % _records_label
	%SplitView.disabled = not (on and has_side)
	%SplitView.set_pressed_no_signal(side_open)
	%SplitView.toggle_mode = true


## What the Records button says: the record in view.
func set_record(label: String) -> void:
	_records_label = label
	_records.text = ("%s ‹" if _records.text.ends_with("‹") else "%s ›") % label


## Each tab is {title, dirty}; `current` is the one showing.
func show_tabs(tabs: Array, current: int) -> void:
	var state := JSON.stringify([tabs, current])
	if state == _shown: return
	_shown = state
	for tab in %Tabs.get_children(): %Tabs.remove_child(tab); tab.queue_free()
	for index in range(tabs.size()):
		var button := Button.new()
		button.theme_type_variation = &"RecordTab"
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.text = str(tabs[index].title)
		button.icon = _mark if tabs[index].get("dirty", false) else null
		button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.set_pressed_no_signal(index == current)
		button.pressed.connect(func(): button.set_pressed_no_signal(true); tab_selected.emit(index))
		%Tabs.add_child(button)
