extends PanelContainer
## The bar under a form: apply or discard its unapplied edits.
signal apply_requested
signal discard_requested


func _ready() -> void:
	%Apply.pressed.connect(func(): apply_requested.emit())
	%DiscardDrafts.pressed.connect(func(): discard_requested.emit())


## `pending` counts unapplied edits; `blocked` holds while the adapter is busy
## or the project must be reopened.
func show_pending(pending: int, blocked: bool) -> void:
	%Apply.disabled = pending == 0 or blocked
	%DiscardDrafts.disabled = pending == 0 or blocked
	%ApplySummary.text = "No unapplied edits" if pending == 0 else ("1 unapplied edit" if pending == 1 else "%d unapplied edits" % pending)


func set_note(text: String) -> void:
	%ApplyNote.text = text
