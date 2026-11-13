extends RefCounted
## Play from here: the open project is exported into a scratch copy of the
## installation and its commands are replayed through the runtime found in the
## editor's folder, so the installation itself is never written. The session is
## a list of commands and what each one did; the runtime keeps the state in a
## save the next command starts from.
signal changed

const SELECTED := [0, 1, 2, 3, 4, 5]
const MAX_STEPS := 200

var shell: Control
var active := false
var running := false
var title := ""
var map := 0
var position := Vector2i(-1, -1)
var message: Dictionary = {}
var queue: Array = []
## One entry per command the runtime was given: {command, events, text, error}.
var log: Array = []
var scratch := ""
var installation := ""
var _save := ""
var _runs := 0
var _target_map := 0
var _target := Vector2i(-1, -1)
var _block := ""


func _init(owner_shell: Control) -> void:
	shell = owner_shell


## What stops Play, or "" when it can run.
func unavailable() -> String:
	if shell.summary.is_empty(): return "Open a project to play it"
	if not shell.folder_play_note.is_empty(): return shell.folder_play_note
	if shell.summary.get("native") == null: return "Play needs a scenario made from a template; its name is the mission's name"
	return ""


func tool_path() -> String:
	return shell.folder.path_join("centurions-tools.exe")


## The commands that enter the mission and walk to `cell` one step at a time.
## The runtime decides whether a step is allowed.
static func route(from: Vector2i, to: Vector2i) -> Array:
	var moves: Array = []
	var step := Vector2i(signi(to.x - from.x), 0)
	for _count in range(mini(absi(to.x - from.x), MAX_STEPS)): moves.append({"Move": {"dx": step.x, "dy": 0}})
	step = Vector2i(0, signi(to.y - from.y))
	for _count in range(mini(absi(to.y - from.y), MAX_STEPS)): moves.append({"Move": {"dx": 0, "dy": step.y}})
	return moves


## Exports the project and plays from the stage start to `cell` of `on_map`.
func start(on_map: int, cell: Vector2i) -> bool:
	var reason := unavailable()
	if not reason.is_empty():
		shell.status(reason, "dim")
		return false
	if running: return false
	running = true
	active = true
	changed.emit()
	shell.status("Preparing a scratch copy of the installation…", "info")
	await shell.get_tree().process_frame
	var name := str(shell.summary.native.name)
	title = name
	if not _prepare(name):
		running = false
		active = false
		changed.emit()
		return false
	var exported: Dictionary = await shell.request_backend({"op": "export", "expected_revision": shell.bridge.revision, "destination": installation.path_join("Scenarios").path_join(name).path_join("0")})
	if not exported.get("ok", false):
		running = false
		active = false
		changed.emit()
		return false
	var opening: Dictionary = shell.summary.get("opening", {})
	var begin := Vector2i(int(opening.get("x", 0)), int(opening.get("y", 0)))
	var moves: Array = route(begin, cell) if on_map == int(opening.get("map", 0)) and cell.x >= 0 else []
	queue = ["ImportStarters", {"SelectStarters": {"indices": SELECTED}}, {"EnterMission": {"name": name}}] + moves
	log = []
	_save = ""
	_runs = 0
	_block = ""
	message = {}
	position = begin
	map = int(opening.get("map", 0))
	_target_map = on_map
	_target = cell
	running = false
	await _run(queue.duplicate())
	return true


## Sends Continue, then goes on with what is left of the route.
func continue_play() -> void:
	if not active or running: return
	await _run(["Continue"] + queue, true)


## Runs the next command alone.
func step() -> void:
	if not active or running or queue.is_empty(): return
	await _run([queue[0]], false, true)


func restart() -> void:
	if running: return
	await start(_target_map, _target)


func stop() -> void:
	active = false
	queue = []
	message = {}
	changed.emit()


## The commands the runtime was given and accepted, as the replay tool reads them.
func commands() -> Array:
	return log.filter(func(entry): return entry.error.is_empty()).map(func(entry): return entry.command)


## Makes the scratch folder: a copy of the installation without its programs,
## made once, and an empty place for the scenario of this run.
func _prepare(name: String) -> bool:
	scratch = shell.default_output_parent().path_join("play")
	installation = scratch.path_join("installation")
	if not DirAccess.dir_exists_absolute(installation):
		DirAccess.make_dir_recursive_absolute(installation)
		if not _copy(shell.folder, installation):
			shell.status("The scratch copy could not be made in %s" % scratch, "err")
			return false
	var level := installation.path_join("Scenarios").path_join(name)
	if DirAccess.dir_exists_absolute(level): _remove(level)
	DirAccess.make_dir_recursive_absolute(level)
	return true


func _copy(from: String, to: String) -> bool:
	var directory := DirAccess.open(from)
	if directory == null: return false
	for entry in directory.get_files():
		if entry.get_extension().to_lower() == "exe": continue
		if DirAccess.copy_absolute(from.path_join(entry), to.path_join(entry)) != OK: return false
	for entry in directory.get_directories():
		DirAccess.make_dir_recursive_absolute(to.path_join(entry))
		if not _copy(from.path_join(entry), to.path_join(entry)): return false
	return true


## Removes a folder of the scratch copy; nothing outside the scratch folder is touched.
func _remove(path: String) -> void:
	if not path.begins_with(scratch): return
	var directory := DirAccess.open(path)
	if directory == null: return
	for entry in directory.get_files(): directory.remove(entry)
	for entry in directory.get_directories(): _remove(path.path_join(entry))
	DirAccess.remove_absolute(path)


## Gives the commands to the runtime and records what each one did.
func _run(commands_to_run: Array, has_continue := false, single := false) -> void:
	running = true
	changed.emit()
	_runs += 1
	var folder := scratch.path_join("run-%d" % _runs)
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("commands.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(commands_to_run))
	file.close()
	var next := folder.path_join("after.save.json")
	var arguments := PackedStringArray(["replay", installation, path, "--trace", "--save", next])
	if not _save.is_empty(): arguments.append_array(["--from", _save])
	var output: Array = []
	var thread := Thread.new()
	thread.start(func(): return OS.execute(tool_path(), arguments, output, true))
	while thread.is_alive(): await shell.get_tree().process_frame
	thread.wait_to_finish()
	var accepted := 0
	var failure := ""
	for line in str(output[0] if not output.is_empty() else "").split("\n"):
		var text := line.strip_edges()
		if text.begins_with("["):
			var events: Variant = JSON.parse_string(text)
			if events is Array and accepted < commands_to_run.size():
				_record(commands_to_run[accepted], events, "")
				accepted += 1
		elif text.begins_with("Error:"): failure = text.trim_prefix("Error:").strip_edges()
	if FileAccess.file_exists(next): _save = next
	var prefix := 1 if has_continue else 0
	for _count in range(maxi(0, accepted - prefix)):
		if not queue.is_empty(): queue.pop_front()
	if failure.is_empty() or accepted >= commands_to_run.size():
		_block = ""
	elif has_continue and accepted == 0:
		# Nothing was waiting for Continue, so the step that was held is blocked.
		var reason := _block if not _block.is_empty() else failure
		queue = []
		message = {}
		_block = ""
		shell.status("Stopped: %s" % reason, "warn")
	else:
		_record(commands_to_run[accepted], [], failure)
		_block = failure
		shell.status("The runtime did not accept %s: %s" % [_name_of(commands_to_run[accepted]), failure], "warn")
	running = false
	if failure.is_empty(): shell.status("Played %d commands · at %d, %d" % [log.size(), position.x, position.y], "good")
	changed.emit()


func _record(command: Variant, events: Array, error: String) -> void:
	var parts: Array = []
	for event in events:
		parts.append(_describe(event))
		var name := _event_name(event)
		var fields: Variant = event[name] if event is Dictionary else null
		if name in ["Moved", "MissionEntered"] and fields is Dictionary:
			position = Vector2i(int(fields.x), int(fields.y))
		if name == "Message" and fields is Dictionary: message = {"id": int(fields.id), "text": str(fields.text)}
	if error.is_empty() and command is Dictionary and command.has("Move") and not events.any(func(event): return _event_name(event) == "Moved"):
		position += Vector2i(int(command.Move.dx), int(command.Move.dy))
	if str(command) == "Continue" and error.is_empty() and not events.any(func(event): return _event_name(event) == "Message"): message = {}
	log.append({"index": log.size() + 1, "command": command, "events": events, "text": " · ".join(parts), "error": error})


static func _event_name(event: Variant) -> String:
	if event is Dictionary and not event.is_empty(): return str(event.keys()[0])
	return str(event)


static func _describe(event: Variant) -> String:
	var name := _event_name(event)
	if not event is Dictionary: return name
	var fields: Variant = event[name]
	if fields is Dictionary:
		var values: Array = []
		for key in fields: values.append(_plain(fields[key]).left(40))
		return "%s %s" % [name, ", ".join(values)]
	return "%s %s" % [name, _plain(fields)]


## A number the runtime wrote as 87 reads as 87, not 87.0.
static func _plain(value: Variant) -> String:
	if value is float and value == floorf(value): return str(int(value))
	return str(value)


## A command as the log says it.
static func _name_of(command: Variant) -> String:
	if command is Dictionary and not command.is_empty():
		var name: String = str(command.keys()[0])
		var fields: Variant = command[name]
		if fields is Dictionary:
			var values: Array = []
			for key in fields: values.append(_plain(fields[key]) if not fields[key] is Array else str(fields[key].map(func(item): return int(item))))
			return "%s %s" % [name, ", ".join(values)]
		return name
	return str(command)


static func name_of_command(command: Variant) -> String:
	return _name_of(command)
