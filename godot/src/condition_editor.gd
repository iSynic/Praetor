extends RefCounted
## Typed Centurions fields only; drafts and revision validation belong to the shell/backend.
var shell: Control
var window: Window
var rows: VBoxContainer
var loading := false
var controls: Array = []

func _init(owner_shell: Control) -> void:
	shell = owner_shell
	window = Window.new(); window.name = "ConditionsWindow"; window.title = "Centurions trigger / encounter conditions"; window.size = Vector2i(820,620); window.min_size = Vector2i(650,480); window.visible = false; window.transient = true; window.exclusive = true
	shell.add_child(window); window.close_requested.connect(window.hide)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); margin.add_theme_constant_override("margin_left",16); margin.add_theme_constant_override("margin_right",16); margin.add_theme_constant_override("margin_top",16); margin.add_theme_constant_override("margin_bottom",16); window.add_child(margin)
	var body := VBoxContainer.new(); body.add_theme_constant_override("separation",10); margin.add_child(body)
	var info := Label.new(); info.text = "Selectors: 0 disables; 1–4 dispatch program branches 0–3. Physical actions must match an exact nonempty set.\nThe password and action labels are text of the encounter. Choice labels are edited in Author records."; info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; body.add_child(info)
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_child(scroll)
	rows = VBoxContainer.new(); rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL; rows.add_theme_constant_override("separation",6); scroll.add_child(rows)
	var footer := HBoxContainer.new(); body.add_child(footer)
	var note := Label.new(); note.text = "Changes are drafts until applied. Unknown bytes are retained."; note.size_flags_horizontal = Control.SIZE_EXPAND_FILL; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; footer.add_child(note)
	var apply := Button.new(); apply.text = "Apply edits"; footer.add_child(apply)
	apply.pressed.connect(func():
		apply.disabled = true
		if await shell.apply_draft(): refresh(); note.text = "Applied. Unknown bytes retained."
		else: note.text = shell.ui("Status").text
		apply.disabled = false)
	var close := Button.new(); close.text = "Close"; footer.add_child(close); close.pressed.connect(window.hide)

func open() -> void:
	if shell._program.is_empty(): return
	await shell.ensure_item_names()
	await shell.references.ensure()
	refresh(); window.popup_centered()

func add_field(label: String, operation: Dictionary, minimum: int, maximum: int, value: int, editable: bool) -> void:
	var row := HBoxContainer.new(); rows.add_child(row)
	var text := Label.new(); text.text = label; text.size_flags_horizontal = Control.SIZE_EXPAND_FILL; text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; row.add_child(text)
	var control := SpinBox.new(); control.min_value = mini(minimum,value); control.max_value = maxi(maximum,value); control.value = value; control.editable = editable; control.custom_minimum_size.x = 140; row.add_child(control)
	var kind: String = {"spell_criterion": "spell", "item_criterion": "item"}.get(str(operation.get("field", "")), "")
	if not kind.is_empty(): shell.references.attach(row, control, kind)
	if not editable: text.text += " (read-only)"
	var key := JSON.stringify(operation)
	var current: Dictionary = shell.drafts.get(key,{})
	if not current.is_empty(): control.value = current.get("value",current.get("chance",value))
	controls.append(control)
	control.value_changed.connect(func(new_value):
		if loading or not editable: return
		if int(new_value) == value: shell.drafts.erase(key)
		else:
			var edit := operation.duplicate(true); edit["chance" if operation.kind == "walking_chance" else "value"] = int(new_value); shell.drafts[key] = edit
		shell._invalidate_receipt(); shell._update_buttons())

## A label of a typed encounter: a draft of its text, none when it reads as saved.
func add_label(label: String, id: int, index: int, saved: String) -> void:
	var row := HBoxContainer.new(); rows.add_child(row)
	var text := Label.new(); text.text = label; text.size_flags_horizontal = Control.SIZE_EXPAND_FILL; text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; row.add_child(text)
	var line := LineEdit.new(); line.custom_minimum_size.x = 280; line.text = saved; row.add_child(line)
	var key := "typed_label:%d:%d" % [id, index]
	if shell.drafts.has(key): line.text = str(shell.drafts[key].text)
	line.text_changed.connect(func(new_text):
		if loading: return
		if new_text == saved: shell.drafts.erase(key)
		else: shell.drafts[key] = {"kind": "typed_label", "id": id, "index": index, "text": new_text}
		shell._invalidate_receipt(); shell._update_buttons())


func refresh() -> void:
	loading = true; controls.clear()
	for child in rows.get_children(): rows.remove_child(child); child.queue_free()
	var p: Dictionary = shell._program
	var data: Dictionary = p.get("conditions",{})
	if p.family == "walking": add_field("Walking chance (0 disables; 1–100 percent)",{"kind":"walking_chance","id":int(p.id)},0,100,int(data.chance),data.get("chance_authorable",false))
	for field in data.get("fields",[]): add_field(field.label,{"kind":"encounter_condition","family":p.family,"id":int(p.id),"field":field.field,"index":int(field.index)},int(field.minimum),int(field.maximum),int(field.value),field.authorable)
	if p.family == "typed":
		var names: Array = p.get("labels", [])
		for index in range(names.size()): add_label("Password label · 39 bytes" if index == 8 else "Action %d label · 39 bytes" % (index + 1), int(p.id), index, str(names[index]))
	if p.family in ["story","walking"]:
		var label := Label.new(); label.text = "Walking return coordinates are editable above the program. Only level 0 is authorable; dispatch stamp is retained. Placement and activation are coupled in Maps."; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; rows.add_child(label)
	loading = false
