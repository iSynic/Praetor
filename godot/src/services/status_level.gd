extends RefCounted
## How serious a status line is, which colours the dot before it. The lines
## are the editor's own text; the level comes from what happened.

## "good" (done), "warn" (waiting on the author), "err" (did not happen),
## "info" (under way) or "dim" (nothing to report yet).
static func of(message: String) -> String:
	for start in ["Starting"]:
		if message.begins_with(start): return "info"
	for start in ["No receipt matched"]:
		if message.begins_with(start): return "dim"
	for start in ["Receipt does not match", "Adapter", "Could not", "Reopen the project before", "Cannot", "Operation failed"]:
		if message.begins_with(start): return "err"
	for fragment in ["disconnected", "interrupted", "could not be confirmed", "invalid reply", "stale revision", "already exists", "rejected"]:
		if fragment in message: return "err"
	for start in ["Wait for", "Select a map cell", "This slot is unplaced", "Return destination applies", "Reopened saved", "Edits are pending", "Return destination drafted", "Drop clearing drafted", "Choose "]:
		if message.begins_with(start): return "warn"
	if message.ends_with("Apply edits"): return "warn"
	return "good"
