class_name PiProcess
extends RefCounted

## One long-lived `pi --mode rpc` child process with strict JSONL framing.
##
## stdout carries protocol records only, stderr is diagnostics. Godot's pipe `FileAccess`
## reports `ERR_FILE_EOF` whenever a non-blocking read finds no bytes, so liveness is decided
## by [method OS.is_process_running] and never by that error code.

signal record(data: Dictionary)
signal stderr_text(text: String)
signal terminated(exit_code: int)

## Records read per poll call; a streaming run can outpace one frame's worth of UI work.
const MAX_RECORDS_PER_POLL := 512

var pid: int = -1
var exit_code: int = -1

var _stdio: FileAccess = null
var _stderr_pipe: FileAccess = null
var _stdout_decoder: Utf8StreamDecoder = null
var _stderr_decoder: Utf8StreamDecoder = null
var _pending_text: String = StringUtils.EMPTY
var _alive: bool = false
var _closed: bool = false


## Launches [param binary] with [param arguments] and starts reading its pipes.
func start(binary: String, arguments: PackedStringArray) -> bool:
	stop()
	var process_info := OS.execute_with_pipe(binary, arguments, false)
	if process_info.is_empty():
		return false
	pid = int(process_info.get("pid", -1))
	_stdio = process_info.get("stdio") as FileAccess
	_stderr_pipe = process_info.get("stderr") as FileAccess
	_stdout_decoder = Utf8StreamDecoder.new()
	_stderr_decoder = Utf8StreamDecoder.new()
	_pending_text = StringUtils.EMPTY
	_alive = pid > 0 and _stdio != null and _stdio.is_open()
	_closed = false
	exit_code = -1
	return _alive


func is_alive() -> bool:
	return _alive and not _closed


func is_running() -> bool:
	if not _alive:
		return false
	return pid > 0 and OS.is_process_running(pid)


## Writes one protocol record. Callers own the framing.
func send_line(line: String) -> bool:
	if not is_alive():
		return false
	_stdio.store_string(line + "\n")
	_stdio.flush()
	return true


## Reads whatever stdout currently holds, emits complete records, and notices process exit.
func poll() -> void:
	if _stdio == null or _closed:
		return
	var started := Time.get_ticks_msec()
	var records := 0
	while true:
		var chunk := _stdio.get_buffer(65536)
		if not chunk.is_empty():
			_pending_text += _stdout_decoder.push(chunk)
			var emitted := _emit_lines()
			records += emitted
		if chunk.is_empty():
			break
		if records >= MAX_RECORDS_PER_POLL or Time.get_ticks_msec() - started > 12:
			# Leave the rest for the next frame instead of stalling the UI thread.
			break
	_drain_stderr()
	if _alive and pid > 0 and not OS.is_process_running(pid):
		# Final read: the pipe can still hold bytes written before exit.
		var tail := _stdio.get_buffer(1 << 20)
		if not tail.is_empty():
			_pending_text += _stdout_decoder.push(tail)
			_emit_lines()
		if not _pending_text.is_empty():
			_emit_line(_pending_text)
			_pending_text = StringUtils.EMPTY
		_alive = false
		_closed = true
		exit_code = OS.get_process_exit_code(pid)
		terminated.emit(exit_code)


## Closes stdin for an orderly shutdown, then kills the child if it lingers.
func stop(kill_after_millis: int = 700) -> void:
	if _stdio != null and _stdio.is_open():
		_stdio.close()
	_stdio = null
	_alive = false
	_closed = true
	if pid > 0 and OS.is_process_running(pid):
		var deadline := Time.get_ticks_msec() + kill_after_millis
		while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
			OS.delay_msec(16)
		if OS.is_process_running(pid):
			OS.kill(pid)
	pid = -1


func _emit_lines() -> int:
	var count := 0
	while true:
		var newline := _pending_text.find("\n")
		if newline < 0:
			break
		var line := _pending_text.substr(0, newline).replace("\r", StringUtils.EMPTY).strip_edges()
		_pending_text = _pending_text.substr(newline + 1)
		if line.is_empty():
			continue
		_emit_line(line)
		count += 1
	return count


func _emit_line(line: String) -> void:
	var parsed: Variant = JSON.parse_string(line)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary[String, Variant] = {}
	data.assign(parsed)
	record.emit(data)


func _drain_stderr() -> void:
	if _stderr_pipe == null or not _stderr_pipe.is_open():
		return
	var text := StringUtils.EMPTY
	while true:
		var chunk := _stderr_pipe.get_buffer(8192)
		if chunk.is_empty():
			break
		text += _stderr_decoder.push(chunk)
	if not text.is_empty():
		stderr_text.emit(text)
