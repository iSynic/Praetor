extends VBoxContainer
## Inspection: one story row's eight steps and the geometry of every native
## table, read only.
var shell: Control


func setup(owner_shell: Control) -> void:
	shell = owner_shell
	%ViewStory.pressed.connect(show_story)
	%StoryData.set_column_title(0,"Slot")
	%StoryData.set_column_title(1,"Native opcode")
	%StoryData.set_column_title(2,"Operand · unresolved")


func show_story() -> void:
	if shell.summary.is_empty(): return
	var response: Dictionary = await shell.request_backend({"op":"story","id":int(%StoryID.value)})
	if not response.get("ok",false): return
	%StoryData.clear()
	var root: TreeItem = %StoryData.create_item()
	for action in response.result.actions:
		var row: TreeItem = %StoryData.create_item(root)
		for column in range(3): row.set_text(column,str(int([action.slot,action.opcode,action.operand][column])))


func show_geometry(summary: Dictionary) -> void:
	var geometry := "Native table geometry\n\n"
	for table in summary.get("tables",[]):
		geometry += "%s · %d bytes/record · %d complete rows · %d trailing bytes retained\n" % [table.file,int(table.stride),int(table.complete_records),int(table.trailing_bytes)]
	%Geometry.text = geometry
