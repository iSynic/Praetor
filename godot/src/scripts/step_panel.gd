extends VBoxContainer
## The form of the chosen step: what operation it is and how it is evidenced,
## the operand in the form that suits the operation, the moves a step allows,
## and the bytes it owns in the program's row.
signal choose_action_requested
signal choose_message_requested
signal choose_record_requested(kind: String)
signal helper_requested
signal operand_edited(value: int)
signal open_link_requested
signal move_requested(delta: int)
signal duplicate_requested
signal clear_requested
signal extra_word_edited(record: int, index: int, value: int)
signal extra_independent_requested
signal extra_uses_requested(record: int)
signal details_toggled(shown: bool)
const Capability = preload("res://src/scripts/capability.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

const KIND_COLOURS := {"key": "6fb3e8", "placement": "6fb3e8", "chance": "e5a53c", "opcodes": "6fb3e8", "operands": "7fc0b4", "selector": "e5a53c", "dialogue": "6fb3e8", "text": "d9b85c", "preserved": "5e6c7b"}

var shell: Control
var _title := Label.new()
var _heading := Label.new()
var _badges := HBoxContainer.new()
var _form := VBoxContainer.new()
var _choose := Button.new()
var _helper := Button.new()
var _move_up := Button.new()
var _move_down := Button.new()
var _duplicate := Button.new()
var _clear := Button.new()
var details_button := Button.new()
var _details := PanelContainer.new()
var _hex := RichTextLabel.new()
var _legend := RichTextLabel.new()
var _owns := Label.new()
var _copy := Button.new()
var _operand: SpinBox
var _link := Button.new()
var _hex_row := ""
var _loading := false


func _init() -> void:
	add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	add_child(head)
	_title.theme_type_variation = &"Dim"
	_title.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_title)
	_heading.theme_type_variation = &"Heading"
	_heading.add_theme_font_size_override("font_size", 20)
	head.add_child(_heading)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	_choose.text = "Choose action…"
	_choose.pressed.connect(func(): choose_action_requested.emit())
	head.add_child(_choose)
	_helper.text = "Code helper  F1"
	_helper.pressed.connect(func(): helper_requested.emit())
	head.add_child(_helper)
	_badges.add_theme_constant_override("separation", 6)
	add_child(_badges)
	add_child(HSeparator.new())
	_form.add_theme_constant_override("separation", 8)
	_form.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_form)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	add_child(buttons)
	for entry in [[_move_up, "Move up", func(): move_requested.emit(-1)], [_move_down, "Move down", func(): move_requested.emit(1)], [_duplicate, "Duplicate", func(): duplicate_requested.emit()], [_clear, "Clear step", func(): clear_requested.emit()]]:
		entry[0].text = entry[1]
		entry[0].pressed.connect(entry[2])
		buttons.add_child(entry[0])
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	details_button.text = "Technical details"
	details_button.theme_type_variation = &"GhostButton"
	details_button.toggle_mode = true
	details_button.toggled.connect(func(on): _details.visible = on; details_toggled.emit(on))
	buttons.add_child(details_button)
	_details.theme_type_variation = &"Card"
	_details.visible = false
	add_child(_details)
	var detail_column := VBoxContainer.new()
	detail_column.add_theme_constant_override("separation", 8)
	_details.add_child(detail_column)
	var detail_head := HBoxContainer.new()
	var detail_title := Label.new()
	detail_title.theme_type_variation = &"Heading"
	detail_title.text = "Technical details"
	detail_head.add_child(detail_title)
	_owns.theme_type_variation = &"MonoDim"
	_owns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_owns.clip_text = true
	detail_head.add_child(_owns)
	_copy.text = "Copy row as hex"
	_copy.pressed.connect(func(): DisplayServer.clipboard_set(_hex_row))
	detail_head.add_child(_copy)
	detail_column.add_child(detail_head)
	var detail_row := HBoxContainer.new()
	detail_row.add_theme_constant_override("separation", 20)
	detail_column.add_child(detail_row)
	_hex.bbcode_enabled = true
	_hex.fit_content = false
	_hex.custom_minimum_size = Vector2(420, 96)
	_hex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_row.add_child(_hex)
	_legend.bbcode_enabled = true
	_legend.fit_content = false
	_legend.custom_minimum_size = Vector2(300, 96)
	detail_row.add_child(_legend)
	_link.text = "Open ↗"


func setup(owner_shell: Control) -> void:
	shell = owner_shell


func _clear_form() -> void:
	# The link button is kept and moved from form to form, so it must leave before the form is freed.
	if _link.get_parent() != null: _link.get_parent().remove_child(_link)
	for child in _form.get_children(): _form.remove_child(child); child.queue_free()
	_operand = null


func _caption(text: String) -> void:
	var label := Label.new()
	label.theme_type_variation = &"CaptionMuted"
	label.text = text
	_form.add_child(label)


func _badge(text: String, variation: StringName) -> void:
	var label := Label.new()
	label.theme_type_variation = variation
	label.text = text
	_badges.add_child(label)


## Shows the step. `ctx` holds {family, branch, slot, opcode, operand, authorable, summary, message, has_free, count}.
func show_step(ctx: Dictionary) -> void:
	_loading = true
	_clear_form()
	for child in _badges.get_children(): _badges.remove_child(child); child.queue_free()
	var opcode := int(ctx.opcode)
	var authorable: bool = ctx.authorable
	_title.text = "Step %d" % (int(ctx.slot) + 1) if ctx.get("branch_label", "").is_empty() else "%s · step %d" % [ctx.branch_label, int(ctx.slot) + 1]
	_heading.text = Capability.name_of(opcode, authorable)
	_choose.disabled = not authorable
	_move_up.disabled = not authorable or int(ctx.slot) == 0
	_move_down.disabled = not authorable or int(ctx.slot) >= int(ctx.count) - 1
	_duplicate.disabled = not authorable or not ctx.get("has_free", false) or opcode == 0
	_clear.disabled = not authorable or opcode == 0
	_badge("opcode %d" % opcode, &"Badge")
	var row := Capability.row(opcode)
	if not row.is_empty():
		_badge(str(row.status), &"BadgeGood" if row.status == "native-verified" else &"Badge")
		_badge(str(row.editor), &"BadgeWarn" if row.editor == "warn" else &"BadgeGood")
	if authorable: _badge("step form", &"BadgeAccent")
	var note := Label.new()
	note.theme_type_variation = &"Muted"
	note.add_theme_font_size_override("font_size", 12)
	note.text = "Every operand is checked against the 1.3.2 engine." if authorable else "The editor keeps this step as recorded; it plays as it did."
	_badges.add_child(note)
	if not authorable:
		_caption("PRESERVED")
		_words("Opcode %d%s is not one of the operations the editor has a form for. Its operand, %d, is kept as recorded." % [opcode, (" (%s)" % row.operation) if not row.is_empty() else "", int(ctx.operand)])
		return
	if Capability.form(opcode).is_empty():
		_caption("DOES NOTHING")
		_words("The game skips the number %d and goes on to the next step. The step is kept as recorded; choose an action to replace it." % opcode)
		_loading = false
		return
	match opcode:
		1: _message_form(ctx)
		0, 24: _operand_form(ctx, "OPERAND", false)
		100: _operand_form(ctx, "OPERAND", true)
		110: _stage_form(ctx)
		_: _operand_form(ctx, (str(Capability.form(opcode)[1])).to_upper(), true)
	if not ctx.get("extra", {}).is_empty(): _extra_form(ctx)
	_loading = false


## The Extra Codes row the step names, and the row after it when the code reads that too.
func _extra_form(ctx: Dictionary) -> void:
	var entry := Capability.code(int(ctx.opcode))
	if int(ctx.opcode) == 128: _animation_preview(ctx.extra_words)
	_extra_block(ctx.extra, ctx.extra_words, entry.get("extra", []), entry.get("ecodes", []), ctx, false)
	if ctx.get("extra_companion", {}).is_empty() or entry.get("companion") == null: return
	_extra_block(ctx.extra_companion, ctx.extra_companion_words, entry.companion, entry.get("companion_labels", []), ctx, true)


## The five words of one row, and the steps that read it.
func _extra_block(extra: Dictionary, words: Array, kinds: Array, labels: Array, ctx: Dictionary, companion: bool) -> void:
	_caption(("EXTRA CODES · ROW %d · READ AS THE SECOND ROW" if companion else "EXTRA CODES · ROW %d") % int(extra.record))
	for index in range(5):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var label := Label.new()
		label.theme_type_variation = &"Dim"
		label.text = "%d  %s" % [index + 1, str(labels[index]) if index < labels.size() and labels[index] != null else "Not used"]
		label.custom_minimum_size.x = 280
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_child(label)
		var kind: Dictionary = kinds[index] if index < kinds.size() else {}
		if str(kind.get("kind", "")) == "soft": kind = kind.inner
		if str(kind.get("kind", "")) == "ignored": label.text += " (the game does not read it)"
		var record := int(extra.record)
		if str(kind.get("kind", "")) == "enum":
			var choice := OptionButton.new()
			for value in kind.values: choice.add_item(str(int(value)), int(value))
			var at := choice.get_item_index(int(words[index]))
			if at < 0:
				choice.add_item("%d (not authorable)" % int(words[index]), int(words[index]))
				at = choice.item_count - 1
			choice.select(at)
			choice.item_selected.connect(func(position): if not _loading: extra_word_edited.emit(record, index, choice.get_item_id(position)))
			line.add_child(choice)
		else:
			var spin := SpinBox.new()
			var limits: Array = Capability.kind_limits(kind)
			spin.min_value = mini(int(limits[0]), int(words[index]))
			spin.max_value = maxi(int(limits[1]), int(words[index]))
			spin.value = int(words[index])
			spin.editable = str(kind.get("kind", "")) != "unused"
			spin.custom_minimum_size.x = 110
			spin.value_changed.connect(func(number): if not _loading: extra_word_edited.emit(record, index, int(number)))
			line.add_child(spin)
			var reference := _reference_kind(kind)
			if not reference.is_empty(): shell.references.attach(line, spin, reference)
		_form.add_child(line)
	var callers: Array = extra.callers
	var shared := callers.size() > 1
	var uses := Label.new()
	uses.theme_type_variation = &"Warn" if shared else &"Dim"
	uses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	uses.text = "Named by %d step%s; a change here reaches each of them." % [callers.size(), "" if callers.size() == 1 else "s"]
	_form.add_child(uses)
	for caller in callers.slice(0, 6):
		var where := Label.new()
		where.theme_type_variation = &"MonoDim"
		where.text = "%s %d · step %d · %s" % [str(caller.family).capitalize(), int(caller.id), int(caller.slot) + 1, str(caller.name)]
		_form.add_child(where)
	var uses_button := Button.new()
	uses_button.text = "Find uses"
	uses_button.theme_type_variation = &"GhostButton"
	var uses_record := int(extra.record)
	uses_button.pressed.connect(func(): extra_uses_requested.emit(uses_record))
	_form.add_child(uses_button)
	if shared and not companion:
		var own := Button.new()
		own.text = "Make this step independent" if not ctx.get("extra_independent", false) else "Gets its own row on Apply"
		own.disabled = ctx.get("extra_independent", false)
		own.pressed.connect(func(): extra_independent_requested.emit())
		_form.add_child(own)


## The kind of reference a value of this kind of word is, or "" when it is only a number.
func _reference_kind(kind: Dictionary) -> String:
	if str(kind.get("kind", "")) == "soft": kind = kind.inner
	match str(kind.get("kind", "")):
		"sound": return "sound"
		"spell": return "spell"
		"record": return "monster" if str(kind.get("file", "")) == "Data MD" else ""
	return ""


## The picture the number names, shown small under the field and updated as the number changes.
func _picture_preview(spin: SpinBox) -> void:
	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2(0, 150)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var note := Label.new()
	note.theme_type_variation = &"Dim"
	var show := func(value: int) -> void:
		picture.texture = null
		note.text = ""
		var texture: Texture2D = await shell.references.picture(value)
		if not is_instance_valid(picture) or int(spin.value) != value: return
		picture.texture = texture
		picture.visible = texture != null
		note.text = "" if texture != null else "No resource file holds picture %d, and the game stops on a missing picture." % value
	spin.value_changed.connect(func(value): show.call(int(value)))
	var choose := Button.new()
	choose.text = "Choose a picture…"
	choose.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	choose.pressed.connect(func(): shell.resource_picker.show_for("picture", int(spin.value), "", func(id): if is_instance_valid(spin): spin.value = id))
	_form.add_child(choose)
	_form.add_child(picture)
	_form.add_child(note)
	show.call(int(spin.value))


## Plays the eight frames of the animation the row names, as the game draws them, one after another.
func _animation_preview(words: Array) -> void:
	var number := int(words[0])
	var ticks := maxi(int(words[4]), 1)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var frame := TextureRect.new()
	frame.custom_minimum_size = Vector2(64, 64)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	line.add_child(frame)
	var play := Button.new()
	play.text = "▶ Preview"
	line.add_child(play)
	var note := Label.new()
	note.theme_type_variation = &"Dim"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(note)
	_form.add_child(line)
	var frames: Array = await shell.references.animation_frames(number)
	if not is_instance_valid(frame): return
	var held := frames.filter(func(texture): return texture != null).size()
	note.text = "Animation %d: %d of its 8 icons (%d to %d) are in the scenario or the game." % [number, held, 12000 + 8 * number, 12007 + 8 * number]
	for texture in frames:
		if texture != null: frame.texture = texture; break
	play.disabled = held == 0
	play.pressed.connect(func():
		for texture in frames:
			if not is_instance_valid(frame): return
			if texture != null: frame.texture = texture
			await frame.get_tree().create_timer(maxf(float(ticks) / 60.0, 0.05)).timeout)


func _words(text: String) -> void:
	var label := Label.new()
	label.theme_type_variation = &"Muted"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	_form.add_child(label)


func _spin(value: int, editable: bool, opcode := 0) -> SpinBox:
	var spin := SpinBox.new()
	var limits: Array = Capability.limits(opcode) if opcode != 0 else [-32768, 32767]
	spin.min_value = mini(int(limits[0]), value)
	spin.max_value = maxi(int(limits[1]), value)
	spin.value = value
	spin.editable = editable
	spin.custom_minimum_size.x = 110
	spin.value_changed.connect(func(number): if not _loading: operand_edited.emit(int(number)))
	_operand = spin
	return spin


func _operand_form(ctx: Dictionary, caption: String, editable: bool) -> void:
	_caption(caption)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_spin(int(ctx.operand), editable and int(ctx.opcode) not in [0, 24], int(ctx.opcode)))
	var reference := _reference_kind(Capability.code(int(ctx.opcode)).get("id", {}))
	if not reference.is_empty(): shell.references.attach(row, _operand, reference)
	var target := Capability.target(int(ctx.opcode), int(ctx.operand))
	if not target.is_empty() and int(ctx.opcode) != 110:
		if _link.get_parent() != null: _link.get_parent().remove_child(_link)
		_link.text = "Open ↗"
		row.add_child(_link)
		if not _link.pressed.is_connected(_open_link): _link.pressed.connect(_open_link)
	if int(ctx.opcode) == 10 and editable:
		var choose := Button.new()
		choose.text = "Choose reward…"
		choose.pressed.connect(func(): choose_record_requested.emit("reward"))
		row.add_child(choose)
	if int(ctx.opcode) == 62 and editable:
		var choose_text := Button.new()
		choose_text.text = "Choose text…"
		choose_text.pressed.connect(func(): choose_record_requested.emit("text"))
		row.add_child(choose_text)
	_form.add_child(row)
	if int(ctx.opcode) == 27: _picture_preview(_operand)
	_words(Capability.takes(int(ctx.opcode)))


func _open_link() -> void:
	open_link_requested.emit()


func _message_form(ctx: Dictionary) -> void:
	_caption("MESSAGE")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_spin(int(ctx.operand), true))
	var pick := Button.new()
	pick.text = str(ctx.message.get("text", "")).replace("\n", " ").left(90) if not ctx.message.is_empty() else "Choose message…"
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.clip_text = true
	pick.pressed.connect(func(): choose_message_requested.emit())
	row.add_child(pick)
	if _link.get_parent() != null: _link.get_parent().remove_child(_link)
	_link.text = "Open message ↗"
	row.add_child(_link)
	if not _link.pressed.is_connected(_open_link): _link.pressed.connect(_open_link)
	_form.add_child(row)
	var help := Label.new()
	help.theme_type_variation = &"Dim"
	help.add_theme_font_size_override("font_size", 12)
	help.text = "Signed message id · 0–%d · message table SD2" % (int(ctx.summary.get("messages", 1348)) - 1)
	_form.add_child(help)
	var text_head := HBoxContainer.new()
	var caption := Label.new()
	caption.theme_type_variation = &"CaptionMuted"
	caption.text = "TEXT"
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_head.add_child(caption)
	var shown_bytes := Label.new()
	shown_bytes.theme_type_variation = &"MonoDim"
	shown_bytes.text = "%d / %d bytes · Mac Roman" % [int(ctx.message.get("bytes", 0)), Capability.MESSAGE_LIMIT] if not ctx.message.is_empty() else ""
	text_head.add_child(shown_bytes)
	_form.add_child(text_head)
	var body := PanelContainer.new()
	body.theme_type_variation = &"Detail"
	var shown_text := Label.new()
	shown_text.theme_type_variation = &"Mono"
	shown_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shown_text.text = str(ctx.message.get("text", ""))
	body.add_child(shown_text)
	_form.add_child(body)
	var edit := Label.new()
	edit.theme_type_variation = &"Dim"
	edit.add_theme_font_size_override("font_size", 12)
	edit.text = "The text is edited in Messages."
	_form.add_child(edit)


func _stage_form(ctx: Dictionary) -> void:
	_caption("STAGE")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_spin(int(ctx.operand), true))
	var stage := absi(int(ctx.operand)) - 1
	var stages: Array = ctx.summary.get("stages", [])
	var name := Label.new()
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.text = "Stage %d · %s" % [stage, str(stages[stage].name)] if stage >= 0 and stage < stages.size() and stages[stage].active else "Stage %d" % stage
	row.add_child(name)
	if _link.get_parent() != null: _link.get_parent().remove_child(_link)
	_link.text = "Open stage ↗"
	row.add_child(_link)
	if not _link.pressed.is_connected(_open_link): _link.pressed.connect(_open_link)
	_form.add_child(row)
	_words("Stored one-based: operand %d. Stage transitions name stages by signed one-based number; a negative operand skips the confirmation." % int(ctx.operand))
	if stage >= 0 and stage < stages.size() and stages[stage].active:
		var card := PanelContainer.new()
		card.theme_type_variation = &"Detail"
		var text := Label.new()
		text.theme_type_variation = &"Mono"
		text.text = "Arrives at Map %d · cell %d, %d" % [int(stages[stage].map), int(stages[stage].x), int(stages[stage].y)]
		card.add_child(text)
		_form.add_child(card)


## The bytes of the program's row, with the span each belongs to and the step's own bytes marked.
func show_bytes(info: Dictionary, family: String, branch: int, slot: int, opcode: int, operand: int) -> void:
	_hex.add_theme_font_override("normal_font", get_theme_font("mono", "EditorTokens"))
	_hex.add_theme_font_size_override("normal_font_size", 12)
	_legend.add_theme_font_size_override("normal_font_size", 12)
	var bytes: Array = info.bytes
	var offsets := Capability.offsets(family, branch, slot)
	var owned := {}
	for index in range(int(offsets[1])): owned[int(offsets[0]) + index] = true
	for index in range(2): owned[int(offsets[2]) + index] = true
	var kind_at: Dictionary = {}
	for span in info.spans:
		for index in range(int(span.from), int(span.to) + 1): kind_at[index] = span.kind
	var hex := PackedStringArray()
	var text := ""
	for index in range(bytes.size()):
		if index % 14 == 0: text += ("\n" if index > 0 else "") + "[color=#5e6c7b]%03d[/color]  " % index
		var cell := "%02x" % int(bytes[index])
		var colour: String = KIND_COLOURS.get(kind_at.get(index, "preserved"), "5e6c7b")
		if owned.has(index): cell = "[bgcolor=#1b3a35][color=#%s]%s[/color][/bgcolor]" % ["3ccfab", cell]
		else: cell = "[color=#%s]%s[/color]" % [colour, cell]
		text += cell + " "
		hex.append("%02x" % int(bytes[index]))
	_hex.text = text
	_hex_row = " ".join(hex)
	var legend := ""
	for span in info.spans:
		var colour: String = KIND_COLOURS.get(span.kind, "5e6c7b")
		legend += "[color=#%s]■[/color]  [color=#93a0ae]%d–%d[/color]  %s\n" % [colour, int(span.from), int(span.to), str(span.label)]
	_legend.text = legend
	var width := int(offsets[1])
	var op_bits := "i16" if width == 2 else "i8"
	_owns.text = "%s · %s · record %d · %d-byte row   Step %d owns opcode %s at %d = 0x%04x · operand i16 at %d = 0x%04x · %d" % [str(info.family), str(info.path), int(info.id), int(info.stride), slot + 1, op_bits, int(offsets[0]), opcode & (0xffff if width == 2 else 0xff), int(offsets[2]), operand & 0xffff, operand]


## The link button moves between forms; if no form holds it, it is freed with the panel.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_link) and _link.get_parent() == null: _link.free()
