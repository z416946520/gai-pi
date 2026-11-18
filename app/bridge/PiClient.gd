class_name PiClient
extends RefCounted

## Command/response layer over [PiProcess]. Owns request ids, timeouts, and the split between
## command responses, session events, and extension UI records.

signal event(data: Dictionary)
signal ui_request(data: Dictionary)
signal command_failed(command: String, message: String)
signal closed(exit_code: int)

const DEFAULT_TIMEOUT_MS := 20000

## Session events that are not command responses nor extension UI.
var process: PiProcess = null
var stderr_log: String = StringUtils.EMPTY

var _next_id: int = 0
var _pending: Dictionary[String, Dictionary] = {}


func start(node_bin: String, arguments: PackedStringArray) -> bool:
	process = PiProcess.new()
	process.record.connect(on_record)
	process.stderr_text.connect(on_stderr)
	process.terminated.connect(on_terminated)
	return process.start(node_bin, arguments)


func is_running() -> bool:
	return process != null and process.is_alive()


## Sends a command and registers [param callback] for its response.
## The callback receives `{"success": bool, "data": Dictionary, "error": String}`.
func request(command: String, params: Dictionary = {}, callback: Callable = Callable(), timeout_ms: int = DEFAULT_TIMEOUT_MS) -> String:
	_next_id += 1
	var id := "c%d" % _next_id
	var payload := {"id": id, "type": command}
	payload.merge(params, true)
	if callback.is_valid():
		_pending[id] = {
			"command": command,
			"callback": callback,
			"deadline": Time.get_ticks_msec() + timeout_ms,
		}
	_send(payload)
	return id


## Fire-and-forget command; the response, if any, is ignored.
func send(command: String, params: Dictionary = {}) -> void:
	var payload := {"type": command}
	payload.merge(params, true)
	_send(payload)


func poll() -> void:
	if process == null:
		return
	process.poll()
	_expire_pending()


func stop() -> void:
	_pending.clear()
	if process != null:
		process.stop()
	process = null


func on_record(data: Dictionary) -> void:
	var type := str(data.get("type", ""))
	if type == "response":
		_resolve(data)
		return
	if type == "extension_ui_request":
		ui_request.emit(data)
		return
	if type == "extension_error":
		stderr_log += "extension error: " + str(data.get("error", "")) + "\n"
		return
	event.emit(data)


## Replies to an extension dialog so pi stops waiting on it.
func answer_ui(id: String, value: Variant) -> void:
	_send({"type": "extension_ui_response", "id": id, "value": value})


func cancel_ui(id: String) -> void:
	_send({"type": "extension_ui_response", "id": id, "cancelled": true})


func _send(payload: Dictionary) -> void:
	if process == null or not process.is_alive():
		return
	process.send_line(JSON.stringify(payload))


func _resolve(data: Dictionary) -> void:
	var id := str(data.get("id", StringUtils.EMPTY))
	if id.is_empty() or not _pending.has(id):
		return
	var pending: Dictionary = _pending[id]
	_pending.erase(id)
	var callback: Callable = pending.get("callback", Callable())
	if not callback.is_valid():
		return
	var success := bool(data.get("success", false))
	var result := {
		"success": success,
		"command": str(data.get("command", pending.get("command", ""))),
		"data": data.get("data", {}),
		"error": str(data.get("error", StringUtils.EMPTY)),
	}
	callback.call(result)


func _expire_pending() -> void:
	if _pending.is_empty():
		return
	var now := Time.get_ticks_msec()
	for id in _pending.keys():
		var pending: Dictionary = _pending[id]
		var deadline := int(pending.get("deadline", 0))
		if now < deadline:
			continue
		_pending.erase(id)
		var callback: Callable = pending.get("callback", Callable())
		if callback.is_valid():
			callback.call({
				"success": false,
				"command": str(pending.get("command", "")),
				"data": {},
				"error": "timeout",
			})


func on_stderr(text: String) -> void:
	stderr_log += text
	if stderr_log.length() > 64 * 1024:
		stderr_log = stderr_log.substr(stderr_log.length() - 32 * 1024)


## Last diagnostics from pi, for surfacing a failed start in the UI.
func stderr_tail(max_length: int) -> String:
	var cleaned := stderr_log.strip_edges()
	if cleaned.length() <= max_length:
		return cleaned
	return cleaned.substr(cleaned.length() - max_length)


func on_terminated(code: int) -> void:
	closed.emit(code)
