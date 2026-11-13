extends RefCounted
## Compares a written level folder with the bytes the project was imported
## with. The project folder keeps those bytes as blobs named in project.json;
## an export differs only where an edit owns bytes.

## Returns {files, copied, changed: [{name, size, bytes}], bytes, added, unreadable}: `added` names the files the import did not have.
## `bytes` counts the bytes that differ in the changed files.
static func compare(project_folder: String, export_folder: String) -> Dictionary:
	var result := {"files": 0, "copied": 0, "changed": [], "bytes": 0, "added": [], "unreadable": []}
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(project_folder.path_join("project.json")))
	if not manifest is Dictionary or not manifest.get("files") is Dictionary:
		result.unreadable.append("project.json")
		return result
	var written := _names(export_folder, "")
	written.sort()
	for name in written:
		result.files += 1
		var entry: Variant = manifest.files.get(name)
		if entry == null:
			result.added.append(name)
			continue
		var blob: String = project_folder.path_join("blobs").path_join(str(entry.get("sha256", ""))) if entry is Dictionary else ""
		if blob.is_empty() or not FileAccess.file_exists(blob):
			result.unreadable.append(name)
			continue
		var before := FileAccess.get_file_as_bytes(blob)
		var after := FileAccess.get_file_as_bytes(export_folder.path_join(name))
		if before == after:
			result.copied += 1
			continue
		var differing := absi(before.size() - after.size())
		for index in range(mini(before.size(), after.size())):
			if before[index] != after[index]: differing += 1
		result.changed.append({"name": name, "size": after.size(), "bytes": differing})
		result.bytes += differing
	return result


static func _names(root: String, prefix: String) -> Array:
	var names: Array = []
	var folder := DirAccess.open(root.path_join(prefix) if not prefix.is_empty() else root)
	if folder == null: return names
	for file in folder.get_files(): names.append(prefix.path_join(file) if not prefix.is_empty() else file)
	for directory in folder.get_directories(): names.append_array(_names(root, prefix.path_join(directory) if not prefix.is_empty() else directory))
	return names
