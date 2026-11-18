class_name AsyncProcess
extends RefCounted

## One-shot child process that never blocks the main thread.
##
## Godot's `OS.execute` blocks until the child exits, which would freeze the window on a
## `git add -A`. This drives `OS.execute_with_pipe` from the frame loop instead, the same way
## [PiProcess] drives pi.

var pid: int = -1
var output: String = StringUtils.EMPTY
var error_output: String = StringUtils.EMPTY
var exit_code: int = -1

var _stdio: FileAccess = null
var _stderr: FileAccess = null
var _decoder: Utf8StreamDecoder = null
var _stderr_decoder: Utf8StreamDecoder = null
var _callback: Callable = Callable()

static var _active: Array[AsyncProcess] = []


## Starts [param binary] and calls [param on_done] with `(exit_code, output)` on the main thread.
static func run(binary: String, arguments: PackedStringArray, on_done: Callable) -> void:
	var process := AsyncProcess.new()
	process._callback = on_done
	if not process.start(binary, arguments):
		if on_done.is_valid():
			on_done.call(-1, StringUtils.EMPTY)
		return
	_active.append(process)


static func poll_all() -> void:
	for process in _active.duplicate():
		process.poll()
		if not process.is_alive():
			_active.erase(process)


static func stop_all() -> void:
	for process in _active:
		process.stop()
	_active.clear()


func start(binary: String, arguments: PackedStringArray) -> bool:
	var info := OS.execute_with_pipe(binary, arguments, false)
	if info.is_empty():
		return false
	pid = int(info.get("pid", -1))
	_stdio = info.get("stdio") as FileAccess
	_stderr = info.get("stderr") as FileAccess
	_decoder = Utf8StreamDecoder.new()
	_stderr_decoder = Utf8StreamDecoder.new()
	return pid > 0 and _stdio != null


func is_alive() -> bool:
	return pid > 0 and OS.is_process_running(pid)


func poll() -> void:
	if _stdio == null:
		return
	while true:
		var chunk := _stdio.get_buffer(65536)
		if chunk.is_empty():
			break
		output += _decoder.push(chunk)
	if _stderr != null and _stderr.is_open():
		while true:
			var chunk := _stderr.get_buffer(8192)
			if chunk.is_empty():
				break
			error_output += _stderr_decoder.push(chunk)
	if is_alive():
		return
	exit_code = OS.get_process_exit_code(pid)
	_stdio.close()
	_stdio = null
	if _stderr != null and _stderr.is_open():
		_stderr.close()
	_stderr = null
	if _callback.is_valid():
		var callback := _callback
		_callback = Callable()
		# Callers only need one text stream; stderr is appended so failures stay diagnosable.
		var combined := output
		if not error_output.strip_edges().is_empty():
			combined += ("
" if not combined.is_empty() else "") + error_output
		callback.call(exit_code, combined)


func stop() -> void:
	if _stdio != null and _stdio.is_open():
		_stdio.close()
	_stdio = null
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	pid = -1
