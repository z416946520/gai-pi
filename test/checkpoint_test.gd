extends SceneTree

## Headless check of the shadow-repo checkpoints: snapshot, diff list, revert.

var manager: CheckpointManager = null
var ws_root := ""
var started := 0
var phase := "begin"


func _initialize() -> void:
	started = Time.get_ticks_msec()
	ws_root = ProjectSettings.globalize_path("user://checkpoint_test/ws")
	_rm_tree(ws_root)
	DirAccess.make_dir_recursive_absolute(ws_root)
	_write(ws_root.path_join("a.txt"), "original\n")
	_write(ws_root.path_join("keep.txt"), "keep\n")

	manager = CheckpointManager.new()
	manager.failed.connect(func(message: String) -> void:
		print("[ckpt] FAIL ", message)
		quit(1)
	)
	if not manager.setup(ws_root):
		print("[ckpt] FAIL setup (git missing?)")
		quit(1)
		return
	manager.begin_turn(func(turn: int, commit: String) -> void:
		print("[ckpt] begin turn=", turn, " commit=", commit.substr(0, 8))
		if turn < 0 or commit.is_empty():
			print("[ckpt] FAIL begin")
			quit(1)
			return
		phase = "end"
		_write(ws_root.path_join("a.txt"), "changed by the turn\n")
		_write(ws_root.path_join("b.txt"), "created by the turn\n")
		manager.end_turn(turn, commit, func(files: Array) -> void:
			print("[ckpt] files=", files)
			if not (files.has("a.txt") and files.has("b.txt")):
				print("[ckpt] FAIL diff list")
				quit(1)
				return
			manager.file_diff(commit, "a.txt", func(diff: String) -> void:
				print("[ckpt] diff has change=", diff.contains("+changed by the turn"))
				if not diff.contains("+changed by the turn"):
					print("[ckpt] FAIL file_diff")
					quit(1)
			)
			phase = "revert"
			manager.revert_turn(turn, commit, func(ok: bool) -> void:
				print("[ckpt] revert ok=", ok)
				if not ok:
					quit(1)
					return
				phase = "done"
			)
		)
	)


func _process(_delta: float) -> bool:
	AsyncProcess.poll_all()
	if phase == "done":
		var a := _read(ws_root.path_join("a.txt"))
		var a_exists := FileAccess.file_exists(ws_root.path_join("a.txt"))
		var b_exists := FileAccess.file_exists(ws_root.path_join("b.txt"))
		var keep := _read(ws_root.path_join("keep.txt"))
		print("[ckpt] a=", JSON.stringify(a), " exists=", a_exists, " b_exists=", b_exists, " keep=", JSON.stringify(keep))
		if a == "original\n" and a_exists and not b_exists and keep == "keep\n":
			print("[ckpt] PASS")
			quit(0)
		else:
			print("[ckpt] FAIL state after revert")
			quit(1)
		return true
	if Time.get_ticks_msec() - started > 60000:
		print("[ckpt] FAIL timeout phase=", phase)
		quit(1)
		return true
	return false


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _rm_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if dir.current_is_dir():
			_rm_tree(path.path_join(name))
		else:
			DirAccess.remove_absolute(path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
