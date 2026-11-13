extends PanelContainer
## The status bar: the last status line with a dot for how it went, the state
## of the folder the editor runs from, then what is unapplied and unsaved.
const StatusLevel = preload("res://src/services/status_level.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

signal problems_requested
var _folder := ""
var _chip := Button.new()


func _ready() -> void:
	_chip.theme_type_variation = &"Chip"
	_chip.visible = false
	_chip.pressed.connect(func(): problems_requested.emit())
	%Pending.get_parent().add_child(_chip)
	%Pending.get_parent().move_child(_chip, %Pending.get_index())


## In the compact layout the dock is folded here as a count of the findings.
func set_compact(on: bool) -> void:
	_chip.visible = on


func show_problem_count(count: int) -> void:
	_chip.text = "%d problems ▴" % count if count != 1 else "1 problem ▴"
var _context := ""


## `level` is "good", "warn", "err", "info" or "dim"; without one it is read
## from the line.
func show_message(message: String, level := "") -> void:
	%Status.text = message
	%Status.tooltip_text = message
	var chosen := level if not level.is_empty() else StatusLevel.of(message)
	%StatusMark.color = {"good": Tokens.GOOD, "warn": Tokens.WARN, "err": Tokens.ERR, "info": Tokens.INFO, "dim": Tokens.DIM}.get(chosen, Tokens.GOOD)


## What the folder check found, as the segment after the status line.
func show_folder(text: String) -> void:
	_folder = text
	_show_segment()


## The segment says where the author is in a workspace (the cell under the
## cursor on a map) in place of the folder while it has something to say.
func show_context(text: String) -> void:
	_context = text
	_show_segment()


func _show_segment() -> void:
	var text := _context if not _context.is_empty() else _folder
	%Folder.text = text
	%Folder.tooltip_text = text


## `pending` counts unapplied edits; `unsaved` holds while the checkpoint is
## behind the applied edits.
func show_state(pending: int, unsaved: bool) -> void:
	%Pending.visible = pending > 0
	%Pending.text = "1 unapplied edit" if pending == 1 else "%d unapplied edits" % pending
	%UnsavedMark.visible = unsaved
	%Unsaved.visible = unsaved
