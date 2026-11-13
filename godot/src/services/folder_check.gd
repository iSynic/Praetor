extends RefCounted
## What the editor finds in its own folder: the classic New Centurions 1.3.2
## installation, its original data, the Newer Centurions release, the replay
## tool and the artwork cache. Nothing is chosen; it is looked for beside the
## editor, and what is missing is reported.
const Bridge = preload("res://src/native_bridge.gd")

## The installation folder, or "". The editor's own folder comes first, then
## the folder above it (the package sits inside the installation's parent),
## then the folder named for development, then the one remembered from an
## earlier launch.
static func find(remembered: String) -> String:
	var own := Bridge.application_folder()
	for candidate in [own, own.get_base_dir(), OS.get_environment("CENTURIONS_INSTALLATION"), remembered]:
		if not str(candidate).is_empty() and holds_original_data(str(candidate)): return str(candidate).simplify_path()
	return ""


static func holds_original_data(folder: String) -> bool:
	return FileAccess.file_exists(folder.path_join("Data Files/Cargo Pod.rsrc")) and DirAccess.dir_exists_absolute(folder.path_join("Scenarios"))


## The artwork cache sits beside the editor, where the adapter keeps it.
static func cache_folder() -> String:
	Bridge.use_user_folders()
	var configured := OS.get_environment("CENTURIONS_CACHE_DIR")
	if not configured.is_empty(): return configured
	return Bridge.adapter_path().get_base_dir().get_base_dir().path_join("centurions-artwork-cache")


## One entry per check: {label, note, state, found}. `state` is "good", "warn",
## "err" or "idle"; `note` is what the row shows at its right.
static func report(folder: String) -> Array:
	var has_folder := not folder.is_empty()
	var classic := has_folder and FileAccess.file_exists(folder.path_join("New Centurions"))
	var data := has_folder and holds_original_data(folder)
	var newer := has_folder and FileAccess.file_exists(folder.path_join(Bridge.program("The New Centurions")))
	var tool := has_folder and FileAccess.file_exists(folder.path_join(Bridge.program("centurions-tools")))
	var cache := DirAccess.dir_exists_absolute(cache_folder())
	return [
		{"label": "New Centurions 1.3.2", "note": "New Centurions" if classic else "New Centurions · not used by the editor", "state": "good" if classic else "idle", "found": classic},
		{"label": "Original data", "note": "Data Files · Scenarios" if data else "Data Files · Scenarios · not found", "state": "good" if data else "err", "found": data},
		{"label": "Newer Centurions", "note": Bridge.program("The New Centurions") if newer else Bridge.program("The New Centurions") + " · needed for Play", "state": "good" if newer else "idle", "found": newer},
		{"label": "Replay tool", "note": Bridge.program("centurions-tools") if tool else Bridge.program("centurions-tools") + " · needed for Play", "state": "good" if tool else "idle", "found": tool},
		{"label": "Artwork cache", "note": "centurions-artwork-cache" if cache else "centurions-artwork-cache · made when artwork first loads", "state": "good" if cache else "idle", "found": cache},
	]


## The names of what is missing, in the order of the checklist.
static func missing(report_rows: Array) -> Array:
	return report_rows.filter(func(row): return not row.found and row.state != "idle").map(func(row): return str(row.label))


## The sentence under the checklist when Play from here cannot run.
static func play_note(report_rows: Array) -> String:
	for row in report_rows:
		if row.label == "Replay tool" and not row.found: return "Play from here is unavailable until %s is in this folder." % Bridge.program("centurions-tools")
		if row.label == "Newer Centurions" and not row.found: return "Play from here is unavailable until %s is in this folder." % Bridge.program("The New Centurions")
	return ""


## The status bar's segment for the folder: "This folder · all found" or what is missing.
static func summary(report_rows: Array, folder: String) -> String:
	if folder.is_empty(): return "This folder · original data not found"
	var names := missing(report_rows)
	if not names.is_empty(): return "This folder · " + ", ".join(names.map(func(name): return str(name).substr(0, 1).to_lower() + str(name).substr(1))) + " not found"
	return "This folder · original data found" + (" · Play unavailable" if not play_note(report_rows).is_empty() else "")
