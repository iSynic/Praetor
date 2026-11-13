extends HBoxContainer
## Record workspaces: the monsters and rewards with their lists and forms, and
## the forms of the other families that Author records opens.
const RecordEditor = preload("res://src/record_editor.gd")
var editor: RefCounted


func setup(owner_shell: Control) -> void:
	editor = RecordEditor.new(owner_shell, self)
