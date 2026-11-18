class_name CheckpointManager
extends RefCounted

## Per-turn workspace snapshots in a shadow Git repository.
##
## pi has no checkpoint concept, and using the user's own repository would put commits in it.
## This keeps a separate object store under `user://checkpoints/<workspace>/`, points Git at
## the workspace with `--work-tree`, and never writes to the project's `.git`.
##
## Two commits bracket each turn, so "revert this turn" is a hard reset to the opening commit
## and the file list comes from a diff between the pair.

signal ready
signal failed(message: String)
signal turn_started(turn_index: int, commit: String)
signal turn_ended(turn_index: int, start_commit: String, files: Array[String])
signal turn_reverted(turn_index: int, ok: bool)

const MAX_LISTED_FILES := 12
## Generated or vendored trees are excluded so a snapshot stays fast and small.
const EXCLUDES := [
	".git/",
	".godot/",
	".dependency/",
	".verify/",
	"node_modules/",
	"build/",
	"dist/",
	"target/",
	"*.tmp",
]

var workspace: String = StringUtils.EMPTY
var enabled: bool = false
var git_bin: String = StringUtils.EMPTY

var _repo_dir: String = StringUtils.EMPTY
var _git_dir: String = StringUtils.EMPTY
var _queue: Array[Callable] = []
var _busy: bool = false
var _turns: int = 0


## Prepares the shadow repository. Returns false when Git is unavailable.
func setup(workspace_path: String) -> bool:
	workspace = workspace_path
	git_bin = PiPaths.which("git")
	if git_bin.is_empty():
		failed.emit(T.t("gai_pi.checkpoint.git_missing"))
		return false
	_repo_dir = ProjectSettings.globalize_path("user://checkpoints/%s-%d" % [
		workspace.get_file().validate_filename(), workspace.hash(),
	])
	_git_dir = _repo_dir.path_join(".git")
	DirAccess.make_dir_recursive_absolute(_repo_dir)
	if not FileAccess.file_exists(_git_dir.path_join("HEAD")):
		var output: Array = []
		var code := OS.execute(git_bin, PackedStringArray(["init", "--quiet", _repo_dir]), output, true)
		if code != 0:
			failed.emit(T.t("gai_pi.checkpoint.init_failed"))
			return false
		_write_excludes()
	enabled = true
	ready.emit()
	# Baseline so the first turn diffs against a real commit.
	enqueue_commit("baseline", func(_ok: bool, _commit: String) -> void: pass)
	return true


func _write_excludes() -> void:
	var info_dir := _git_dir.path_join("info")
	DirAccess.make_dir_recursive_absolute(info_dir)
	var file := FileAccess.open(info_dir.path_join("exclude"), FileAccess.WRITE)
	if file == null:
		return
	file.store_string("\n".join(EXCLUDES) + "\n")
	file.close()


# ---------------------------------------------------------------------------
# Public operations (all asynchronous)
# ---------------------------------------------------------------------------

## Commits the current workspace and reports the opening commit for this turn.
func begin_turn(callback: Callable) -> void:
	if not enabled:
		callback.call(-1, StringUtils.EMPTY)
		return
	_turns += 1
	var turn := _turns
	enqueue_commit("turn %d start" % turn, func(ok: bool, commit: String) -> void:
		if ok:
			if OS.get_environment("GAI_PI_TIMING") == "1":
				print("[ckpt] open turn=", turn, " commit=", commit.substr(0, 8))
			turn_started.emit(turn, commit)
			callback.call(turn, commit)
		else:
			callback.call(-1, StringUtils.EMPTY)
	)


## Commits the closing state and lists files that differ from [param start_commit].
func end_turn(turn: int, start_commit: String, callback: Callable) -> void:
	if not enabled or start_commit.is_empty():
		var empty: Array[String] = []
		callback.call(empty)
		return
	enqueue_commit("turn %d end" % turn, func(ok: bool, end_commit: String) -> void:
		if not ok:
			callback.call([])
			return
		run_git(PackedStringArray(["--no-pager", "diff", "--name-only", start_commit, end_commit]), func(code: int, output: String) -> void:
			if OS.get_environment("GAI_PI_TIMING") == "1":
				print("[ckpt] close turn=", turn, " end=", end_commit.substr(0, 8), " code=", code, " files=", JSON.stringify(output.strip_edges()))
			var files := PackedStringArray()
			if code == 0:
				for line in output.split("\n"):
					var path := line.strip_edges()
					if not path.is_empty():
						files.append(path)
			var list: Array[String] = []
			list.assign(files)
			turn_ended.emit(turn, start_commit, list)
			callback.call(list)
		)
	)


## Restores the workspace to the opening commit of a turn, deleting files the turn created.
func revert_turn(turn: int, start_commit: String, callback: Callable) -> void:
	if not enabled or start_commit.is_empty():
		callback.call(false)
		return
	# Stage current state first: files created after the opening commit are then removed by
	# the hard reset instead of lingering as untracked.
	_enqueue(func(done: Callable) -> void:
		run_git(PackedStringArray(["add", "-A"]), func(_code: int, _output: String) -> void:
			run_git(PackedStringArray(["reset", "--hard", start_commit]), func(code: int, _out: String) -> void:
				var ok := code == 0
				turn_reverted.emit(turn, ok)
				callback.call(ok)
				done.call()
			)
		)
	)


# ---------------------------------------------------------------------------
# Git plumbing
# ---------------------------------------------------------------------------

func enqueue_commit(message: String, callback: Callable) -> void:
	_enqueue(func(done: Callable) -> void:
		run_git(PackedStringArray(["add", "-A"]), func(code: int, output: String) -> void:
			if code != 0:
				if OS.get_environment("GAI_PI_TIMING") == "1":
					print("[ckpt] add failed: ", output.strip_edges())
				callback.call(false, StringUtils.EMPTY)
				done.call()
				return
			run_git(PackedStringArray(["commit", "--allow-empty", "--quiet", "-m", message]), func(commit_code: int, out: String) -> void:
				if commit_code != 0:
					if OS.get_environment("GAI_PI_TIMING") == "1":
						print("[ckpt] commit failed: ", out.strip_edges())
					callback.call(false, StringUtils.EMPTY)
					done.call()
					return
				run_git(PackedStringArray(["rev-parse", "HEAD"]), func(_rev_code: int, output: String) -> void:
					callback.call(true, output.strip_edges())
					done.call()
				)
			)
		)
	)


## Runs one git command against the shadow repo; never blocks the frame.
func run_git(arguments: PackedStringArray, callback: Callable) -> void:
	var full := PackedStringArray([
		"--git-dir=" + _git_dir,
		"--work-tree=" + workspace,
		"-c", "user.name=gai-pi",
		"-c", "user.email=gai-pi@localhost",
		"-c", "core.autocrlf=false",
		"-c", "core.quotepath=false",
	])
	full.append_array(arguments)
	AsyncProcess.run(git_bin, full, func(code: int, output: String) -> void:
		callback.call(code, output)
	)


func _enqueue(operation: Callable) -> void:
	_queue.append(operation)
	_pump()


func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var operation: Callable = _queue.pop_front()
	operation.call(func() -> void:
		_busy = false
		_pump()
	)


# ---------------------------------------------------------------------------
# Turn records (shell-only metadata that pi never persists)
# ---------------------------------------------------------------------------

func _records_path() -> String:
	return _repo_dir.path_join("turns.json")


func load_turn_records(session_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if session_id.is_empty():
		return result
	var all := _read_records()
	for record_value in all:
		var record := PiSession.as_dictionary(record_value)
		if str(record.get("session", StringUtils.EMPTY)) == session_id:
			result.append(record)
	return result


## Adds or replaces the record for one turn.
func save_turn_record(session_id: String, turn: int, commit: String, summary: String, timestamp: int, reverted: bool = false) -> void:
	if session_id.is_empty() or commit.is_empty():
		return
	var all := _read_records()
	var updated: Array = []
	for record_value in all:
		var record := PiSession.as_dictionary(record_value)
		if str(record.get("session", StringUtils.EMPTY)) == session_id and int(record.get("turn", -1)) == turn:
			continue
		updated.append(record)
	updated.append({
		"session": session_id,
		"turn": turn,
		"commit": commit,
		"summary": summary,
		"timestamp": timestamp,
		"reverted": reverted,
	})
	_write_records(updated)


func set_turn_summary(session_id: String, turn: int, summary: String, reverted: bool = false) -> void:
	for record_value in _read_records():
		var record := PiSession.as_dictionary(record_value)
		if str(record.get("session", StringUtils.EMPTY)) == session_id and int(record.get("turn", -1)) == turn:
			save_turn_record(session_id, turn, str(record.get("commit", "")), summary, int(record.get("timestamp", 0)), reverted)
			return


func _read_records() -> Array:
	if _repo_dir.is_empty():
		return []
	var file := FileAccess.open(_records_path(), FileAccess.READ)
	if file == null:
		return []
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		return []
	return parsed as Array


func _write_records(records: Array) -> void:
	var file := FileAccess.open(_records_path(), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(records, "  "))
	file.close()


func format_file_list(files: Array) -> String:
	if files.is_empty():
		return T.t("gai_pi.checkpoint.no_changes")
	var lines := PackedStringArray()
	for index in mini(files.size(), MAX_LISTED_FILES):
		lines.append(str(files[index]))
	if files.size() > MAX_LISTED_FILES:
		lines.append(T.t("gai_pi.checkpoint.more_files", [files.size() - MAX_LISTED_FILES]))
	return "\n".join(lines)
