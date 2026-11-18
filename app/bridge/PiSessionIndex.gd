class_name PiSessionIndex
extends Object

## Builds the sidebar list from pi's own session files.
##
## pi has no "list sessions" RPC command; the picker in the TUI reads the same JSONL files.
## Only the head and tail of each file are parsed: the header carries id/cwd/timestamp, the
## tail carries the latest name and message preview.

const HEAD_BYTES := 65536
const TAIL_BYTES := 32768
const PREVIEW_LENGTH := 60
## Sessions above this size are read from their tail only; the display window is far smaller.
const MAX_BRANCH_BYTES := 24 * 1024 * 1024
## Written as a constant because the file format is line-oriented JSONL.
const NEWLINE := "\n"

## Per-file metadata cache keyed by path; a file is re-read only when mtime or size changes.
class CachedMeta:
	var modified: int
	var size: int
	var meta: Dictionary

	func _init(file_modified: int, file_size: int, file_meta: Dictionary) -> void:
		modified = file_modified
		size = file_size
		meta = file_meta


static var _cache: Dictionary[String, CachedMeta] = {}


static func list_for_workspace(workspace: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var folder := PiPaths.session_folder(workspace)
	var dir := DirAccess.open(folder)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".jsonl"):
			var path := folder.path_join(file_name)
			var meta := cached_meta(path)
			if not meta.is_empty():
				result.append(meta.duplicate(true))
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("modified", 0)) > int(right.get("modified", 0))
	)
	return result


## Cached variant of [method read_meta]; stat is cheap, parsing 96 KB per session is not.
static func cached_meta(path: String) -> Dictionary:
	var modified := int(FileAccess.get_modified_time(path))
	var probe := FileAccess.open(path, FileAccess.READ)
	if probe == null:
		return {}
	var size := probe.get_length()
	probe.close()
	var cached: CachedMeta = _cache.get(path)
	if cached != null and cached.modified == modified and cached.size == size:
		return cached.meta
	var meta := read_meta(path)
	if meta.is_empty():
		return {}
	_cache[path] = CachedMeta.new(modified, size, meta)
	return meta


## Drops cache entries for files that no longer exist.
static func prune_cache() -> void:
	for path: String in _cache.keys():
		if not FileAccess.file_exists(path):
			_cache.erase(path)


static func invalidate(path: String) -> void:
	_cache.erase(path)


static func read_meta(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var size := file.get_length()
	var head := _read_head(file, size)
	var tail := _read_tail(file, size)
	file.close()

	var meta := {
		"path": path,
		"id": path.get_file().get_basename().get_slice("_", -1),
		"title": StringUtils.EMPTY,
		"preview": StringUtils.EMPTY,
		"modified": int(FileAccess.get_modified_time(path)),
		"cwd": StringUtils.EMPTY,
		"first_user": StringUtils.EMPTY,
	}
	var first_user := StringUtils.EMPTY
	for line in head:
		var entry: Dictionary = _parse(line)
		if entry.is_empty():
			continue
		match str(entry.get("type", StringUtils.EMPTY)):
			"session":
				meta["cwd"] = str(entry.get("cwd", StringUtils.EMPTY))
				var header_id := str(entry.get("id", StringUtils.EMPTY))
				if not header_id.is_empty():
					meta["id"] = header_id
			"message":
				var message: Dictionary = PiSession.as_dictionary(entry.get("message", {}))
				if str(message.get("role", StringUtils.EMPTY)) == "user" and first_user.is_empty():
					first_user = _clean_text(PiSession.content_text(message.get("content", StringUtils.EMPTY)))
			"session_info":
				var name := str(entry.get("name", StringUtils.EMPTY))
				if not name.is_empty():
					meta["title"] = name
			_:
				pass

	var last_text := StringUtils.EMPTY
	var first_in_tail := StringUtils.EMPTY
	for line in tail:
		var entry: Dictionary = _parse(line)
		if entry.is_empty():
			continue
		match str(entry.get("type", StringUtils.EMPTY)):
			"message":
				var message: Dictionary = PiSession.as_dictionary(entry.get("message", {}))
				if str(message.get("role", StringUtils.EMPTY)) == "user":
					var text := _clean_text(PiSession.content_text(message.get("content", StringUtils.EMPTY)))
					if not text.is_empty():
						last_text = text
						if first_in_tail.is_empty():
							first_in_tail = text
			"session_info":
				var name := str(entry.get("name", StringUtils.EMPTY))
				if not name.is_empty():
					meta["title"] = name
			_:
				pass

	if first_user.is_empty():
		first_user = first_in_tail
	meta["first_user"] = first_user
	meta["preview"] = last_text
	if str(meta["title"]).is_empty():
		# The shell supplies a translated placeholder when both stay empty.
		meta["title"] = first_user if not first_user.is_empty() else last_text
	return meta


## Rebuilds the active branch (leaf to root) straight from the session file.
##
## This is the display path used when switching sessions: pi's `get_entries` serializes the
## whole session tree over the RPC pipe, which costs seconds on long sessions, while the file
## already holds the same entries and is local.
static func load_branch_entries(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	var size := file.get_length()
	var text := StringUtils.EMPTY
	if size > MAX_BRANCH_BYTES:
		var start := size - MAX_BRANCH_BYTES
		file.seek(start)
		text = file.get_buffer(size - start).get_string_from_utf8()
		# The first line of a tail read is almost certainly partial.
		var first_break := text.find(NEWLINE)
		text = text.substr(first_break + 1) if first_break >= 0 else StringUtils.EMPTY
	else:
		text = file.get_as_text()
	file.close()

	var ordered: Array[Dictionary] = []
	var by_id: Dictionary[String, Dictionary] = {}
	for line in text.split(NEWLINE):
		var entry := _parse(line)
		if entry.is_empty():
			continue
		if str(entry.get("type", StringUtils.EMPTY)) == "session":
			continue
		ordered.append(entry)
		var entry_id := str(entry.get("id", StringUtils.EMPTY))
		if not entry_id.is_empty():
			by_id[entry_id] = entry
	if ordered.is_empty():
		return result

	# Linear sessions (v1 files, or entries without ids) keep append order.
	if by_id.is_empty():
		return ordered

	var leaf_id := str(ordered[ordered.size() - 1].get("id", StringUtils.EMPTY))
	if leaf_id.is_empty():
		return ordered
	var chain: Array[Dictionary] = []
	var visited: Dictionary[String, bool] = {}
	var cursor := leaf_id
	while not cursor.is_empty() and by_id.has(cursor) and not visited.has(cursor):
		visited[cursor] = true
		var entry: Dictionary = by_id[cursor]
		chain.append(entry)
		var parent: Variant = entry.get("parentId")
		cursor = str(parent) if parent != null else StringUtils.EMPTY
	if chain.is_empty():
		return ordered
	chain.reverse()
	return chain


static func id_from_path(path: String) -> String:
	var stem := path.get_file().get_basename()
	var parts := stem.split("_")
	return parts[parts.size() - 1] if parts.size() > 0 else StringUtils.EMPTY


static func path_for_id(workspace: String, session_id: String) -> String:
	if session_id.is_empty():
		return StringUtils.EMPTY
	var folder := PiPaths.session_folder(workspace)
	var dir := DirAccess.open(folder)
	if dir == null:
		return StringUtils.EMPTY
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".jsonl") and file_name.contains(session_id):
			dir.list_dir_end()
			return folder.path_join(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	return StringUtils.EMPTY


static func _read_head(file: FileAccess, size: int) -> PackedStringArray:
	file.seek(0)
	var raw := file.get_buffer(mini(size, HEAD_BYTES))
	var lines := raw.get_string_from_utf8().split("\n")
	# The last line of a truncated read is usually partial; drop it.
	if size > HEAD_BYTES and lines.size() > 0:
		lines.remove_at(lines.size() - 1)
	return lines


static func _read_tail(file: FileAccess, size: int) -> PackedStringArray:
	if size == 0:
		return PackedStringArray()
	var start := maxi(0, size - TAIL_BYTES)
	file.seek(start)
	var raw := file.get_buffer(size - start)
	var lines := raw.get_string_from_utf8().split("\n")
	if start > 0 and lines.size() > 0:
		lines.remove_at(0)
	return lines


static func _parse(line: String) -> Dictionary:
	var text := line.strip_edges()
	if text.is_empty() or not text.begins_with("{"):
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


static func _clean_text(text: String) -> String:
	var cleaned := text.replace("\r", " ").replace("\n", " ").strip_edges()
	# Slash commands and injected context make poor sidebar titles.
	if cleaned.begins_with("/") and cleaned.length() < 40:
		return StringUtils.EMPTY
	if cleaned.length() > PREVIEW_LENGTH:
		cleaned = cleaned.left(PREVIEW_LENGTH - 1) + "…"
	return cleaned
