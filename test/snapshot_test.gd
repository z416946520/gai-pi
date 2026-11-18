extends SceneTree

## Headless check of edit/write undo snapshots (no model call involved).

func _initialize() -> void:
	var root := ProjectSettings.globalize_path("user://snapshot_test")
	DirAccess.make_dir_recursive_absolute(root)
	DirAccess.remove_absolute(root.path_join("a.txt"))
	DirAccess.remove_absolute(root.path_join("b.txt"))
	var a := root.path_join("a.txt")
	var b := root.path_join("b.txt")
	_write(a, "one\n")

	var session := PiSession.new()
	session.local_id = 1
	session.workspace_root = root

	session.on_tool_start({"toolName": "edit", "toolCallId": "t1", "args": {"path": "a.txt"}})
	_write(a, "two\n")
	var error := session.restore_snapshot("t1")
	print("[snap] edit restore error='", error, "' content=", JSON.stringify(_read(a)))
	if error != "" or _read(a) != "one\n":
		print("[snap] FAIL edit restore")
		quit(1)
		return

	session.on_tool_start({"toolName": "write", "toolCallId": "t2", "args": {"path": "b.txt"}})
	_write(b, "created\n")
	error = session.restore_snapshot("t2")
	print("[snap] write restore error='", error, "' exists=", FileAccess.file_exists(b))
	if error != "" or FileAccess.file_exists(b):
		print("[snap] FAIL write restore")
		quit(1)
		return

	# A non-file tool must not capture anything.
	session.on_tool_start({"toolName": "bash", "toolCallId": "t3", "args": {"command": "ls"}})
	if session.restore_snapshot("t3") == "":
		print("[snap] FAIL bash should not be restorable")
		quit(1)
		return
	print("[snap] PASS")
	quit(0)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()
