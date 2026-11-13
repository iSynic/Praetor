extends Node
## Persistent redirected-I/O transport adapted from Providence's bridge pattern.
## Canonical state and revisions are owned by the Rust adapter.
signal transport_failed(message: String)
## The adapter took a request or answered the last one.
signal busy_changed(busy: bool)

var revision := 0
var busy := false:
	set(value):
		if busy == value: return
		busy = value
		busy_changed.emit(value)
var requires_reopen := false
var _process: Dictionary = {}
var _next_id := 0
var _worker: Thread
var _reader = preload("res://src/native_json_line_reader.gd").new()
var _launches := 0

## The requests and replies this editor is written for. An adapter that reports another number is out of date.
const ADAPTER_INTERFACE := 16


static func adapter_path() -> String:
	var configured := OS.get_environment("CENTURIONS_ADAPTER")
	if not configured.is_empty(): return configured
	var beside := OS.get_executable_path().get_base_dir().path_join("centurions-adapter.exe")
	if FileAccess.file_exists(beside): return beside
	return ProjectSettings.globalize_path("res://../target/release/centurions-adapter.exe").simplify_path()


## The adapter to launch. Run from the Godot editor, a copy is launched so that building the adapter again never
## fails because the running editor holds the file, and the next start picks up the new build.
func _launch_path() -> String:
	var path := adapter_path()
	if not OS.has_feature("editor") or not OS.get_environment("CENTURIONS_ADAPTER").is_empty() or not FileAccess.file_exists(path): return path
	var folder := "user://adapter"
	DirAccess.make_dir_recursive_absolute(folder)
	for old in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder.path_join(old))
	_launches += 1
	var copy := folder.path_join("centurions-adapter-%d-%d.exe" % [OS.get_process_id(), _launches])
	if DirAccess.copy_absolute(path, copy) != OK: return path
	return ProjectSettings.globalize_path(copy)


func start() -> Dictionary:
	stop()
	revision = 0
	_reader = preload("res://src/native_json_line_reader.gd").new()
	_process = OS.execute_with_pipe(_launch_path(), PackedStringArray(), true)
	if not _process.has("stdio"):
		return _failure("Could not launch the Centurions adapter. Build it or set CENTURIONS_ADAPTER.")
	requires_reopen = false
	var described: Dictionary = await request({"op":"describe"})
	if described.get("ok", false) and int(described.result.get("interface", 0)) != ADAPTER_INTERFACE:
		stop()
		return _failure("The adapter is older or newer than this editor. Build it again with: cargo build --release")
	return described


func stop() -> void:
	if _process.has("pid") and OS.is_process_running(int(_process.pid)):
		OS.kill(int(_process.pid))
	if _worker != null and _worker.is_started(): _worker.wait_to_finish()
	_worker = null
	_process.clear()
	busy = false


func _exit_tree() -> void:
	stop()


func _failure(message: String) -> Dictionary:
	requires_reopen = true
	transport_failed.emit(message)
	return {"ok":false,"outcome_unknown":true,"error":{"message":message}}


func request(operation: Dictionary) -> Dictionary:
	if busy: return {"ok":false,"error":{"message":"Wait for the current operation."}}
	if _process.is_empty(): return _failure("Adapter is disconnected. Reopen the project; drafts are kept.")
	if requires_reopen and operation.op != "open": return _failure("Reopen the project before continuing; drafts are kept.")
	busy = true
	_next_id += 1
	var request_id := _next_id
	var envelope := {"protocol":1,"id":request_id,"operation":operation}
	_worker = Thread.new()
	var stream: FileAccess = _process.stdio
	var pid := int(_process.pid)
	_worker.start(func() -> String:
		stream.store_string(JSON.stringify(envelope)+"\n")
		stream.flush()
		return _reader.read(stream, func(): return OS.is_process_running(pid)))
	var started := Time.get_ticks_msec()
	var timed_out := false
	while _worker != null and _worker.is_alive():
		if Time.get_ticks_msec()-started > 30000 and not timed_out:
			timed_out = true
			OS.kill(pid)
		await get_tree().process_frame
	if _worker == null: return {"ok":false,"error":{"message":"The adapter was stopped."}}
	var line: String = _worker.wait_to_finish()
	_worker = null
	busy = false
	if timed_out or line.is_empty():
		return _failure("Adapter disconnected. Reopen the project; drafts are kept.")
	var parser := JSON.new()
	if parser.parse(line) != OK:
		return _failure("Adapter returned an invalid reply. Reopen the project; drafts are kept.")
	var response: Variant = parser.data
	if not response is Dictionary or response.get("id") != request_id or response.get("protocol") != 1:
		return _failure("Adapter reply could not be confirmed. Reopen the project; drafts are kept.")
	if response.has("revision"): revision = int(response.revision)
	if response.get("outcome_unknown", false): return _failure("Adapter interrupted. Reopen the project; drafts are kept.")
	return response
