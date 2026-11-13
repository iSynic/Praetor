extends RefCounted
## Coupled header/map activation operations; dispatch stamps remain untouched.
var shell: Control
var selected := Vector2i(-1,-1)
var target: Dictionary = {}
var loading := false
var return_button: Button
var choice_button: Button
var bar: Control

func _init(owner_shell: Control) -> void:
	shell = owner_shell
	# The slot, chance and follow controls are the Maps toolbar's; clicks arrive from the Maps page.
	bar = HFlowContainer.new(); shell.programs.after_box.add_child(bar)
	bar.name = "TriggerTargetRow"
	var label := Label.new(); label.text = "Walking return · level 0"; bar.add_child(label)
	for entry in [["ReturnMap","Map ",19],["ReturnX","X ",89],["ReturnY","Y ",89]]: spin(bar,entry[0],entry[1],entry[2],0)
	return_button = Button.new(); return_button.text = "Return destination draft"; bar.add_child(return_button); return_button.pressed.connect(draft_target)
	choice_button = Button.new(); choice_button.text = "Choice labels / prompt"; bar.add_child(choice_button); choice_button.pressed.connect(func(): shell.guard(func(): await shell.record_ui.open_record("choice",shell._program_id)))
	for key in ["Map","X","Y"]: shell.ui("Return"+key).value_changed.connect(func(_value): if not loading: draft_target())

func spin(parent: Node, name: String, prefix: String, maximum: int, value: int) -> void:
	var control := SpinBox.new(); control.name = name; control.prefix = prefix; control.max_value = maximum; control.value = value; control.custom_minimum_size.x = 125; parent.add_child(control); shell.name_node(name,control)

func button(parent: Node, text: String, callback: Callable) -> void:
	var control := Button.new(); control.text = text; parent.add_child(control); control.pressed.connect(callback)

func refresh() -> void:
	loading = true
	var p: Dictionary = shell._program
	var walking: bool = p.get("family") == "walking"
	for key in ["Map","X","Y"]: shell.ui("Return"+key).editable = walking
	return_button.disabled = not walking; choice_button.disabled = p.get("family") != "menu"
	# Each family shows only the linked edits that apply to it.
	for child in bar.get_children(): child.visible = walking
	choice_button.visible = p.get("family") == "menu"
	if p.get("family") == "walking":
		target = shell.drafts.get("walking_target:%d" % shell._program_id,p.destination)
		for key in ["Map","X","Y"]: shell.ui("Return"+key).value = target[key.to_lower()]
	loading = false

func draft_target() -> void:
	if shell._program.get("family") != "walking": shell.status("Return destination applies to walking triggers only"); return
	var edit := {"kind":"walking_target","id":shell._program_id,"map":int(shell.ui("ReturnMap").value),"x":int(shell.ui("ReturnX").value),"y":int(shell.ui("ReturnY").value),"level":0}
	shell.drafts["walking_target:%d" % shell._program_id] = edit; shell._invalidate_receipt(); shell._update_buttons(); shell.status("Return destination drafted · Apply edits")

func create() -> void:
	if selected.x < 0: shell.status("Select a map cell first"); return
	var response: Dictionary = await shell.request_backend({"op":"create_trigger","expected_revision":shell.bridge.revision,"map":shell._map_id,"x":selected.x,"y":selected.y})
	if response.get("ok",false):
		shell.ui("PlacementSlot").value = int(response.result.id)%100
		await shell._set_summary(response.result.summary)
		shell.status("Created active trigger %d; open its steps to add behavior" % int(response.result.id))

## Places, disables or removes a walking trigger. `target` names the trigger; without it the slot chosen in the toolbar is used.
func place(cell: Vector2i, remove := false, disable := false, target := -1) -> void:
	if shell.summary.is_empty(): return
	var trigger_id: int = target if target >= 0 else shell._map_id*100+int(shell.ui("PlacementSlot").value)
	if disable:
		var found := false
		for trigger in shell.ui("MapCanvas").triggers:
			if int(trigger.id) == trigger_id: cell = Vector2i(int(trigger.x),int(trigger.y)); found = true
		if not found: shell.status("This slot is unplaced; use Remove or choose a placed slot"); return
	var response: Dictionary = await shell.request_backend({"op":"place_trigger","expected_revision":shell.bridge.revision,"id":trigger_id,"x":maxi(0,cell.x),"y":maxi(0,cell.y),"chance":0 if disable else int(shell.ui("PlacementChance").value),"remove":remove,"follow":shell.ui("PlacementFollow").button_pressed})
	if response.get("ok",false):
		await shell._set_summary(response.result.summary)
		shell.status("Trigger %d %s · header and activation updated atomically" % [trigger_id,"removed" if remove else ("disabled" if disable else "placed")])
