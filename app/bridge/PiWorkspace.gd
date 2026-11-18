class_name PiWorkspace
extends RefCounted

## One `pi --mode rpc` host bound to a working directory.
##
## pi fixes a session's working directory at creation, so the shell launches pi through a
## generated launcher script that `cd`s first: Godot cannot set a child's cwd directly.
## Sessions inside the workspace are switched with `switch_session`, which keeps process
## startup cost at one per window.

signal ready
signal failed(message: String)
signal session_loaded(session: PiSession)
signal state_changed
signal streaming_changed(streaming: bool)
signal prompt_done(disposition: String)
signal dialog_requested(data: Dictionary)
signal notification(message: String, level: String)

const LAUNCHER_CMD := "launch.cmd"
const LAUNCHER_SH := "launch.sh"
const STATE_TIMEOUT_MS := 90000
const PROMPT_TIMEOUT_MS := 60000
const COMPACT_TIMEOUT_MS := 600000
## pi normally answers get_state within a couple of seconds; this bounds a broken install.
const BOOT_TIMEOUT_MS := 45000

var workspace: String = StringUtils.EMPTY
var client: PiClient = null
var session: PiSession = null
var is_ready: bool = false
var is_streaming: bool = false
var model_label: String = StringUtils.EMPTY
var thinking_level: String = StringUtils.EMPTY
## Optional ownership of shell checkpoints, used to re-inject them when a session is replayed.
var checkpoints: CheckpointManager = null

var _launcher_path: String = StringUtils.EMPTY
var _next_local_id: int = 1
var _state_requested_at: int = 0
var _needs_entries: bool = true
var _last_command_error: String = StringUtils.EMPTY
var _boot_started_at: int = 0
var _switch_started_at: int = 0
var _entries_started_at: int = 0


func _init(workspace_path: String) -> void:
	workspace = workspace_path


func start() -> bool:
	if client != null:
		return is_ready
	if not PiPaths.resolve():
		failed.emit(localized_start_error())
		return false
	if not _write_launcher():
		failed.emit(T.t("gai_pi.bridge.launcher_failed"))
		return false
	client = PiClient.new()
	client.event.connect(on_event)
	client.ui_request.connect(on_ui_request)
	client.closed.connect(on_closed)
	var binary := "cmd.exe" if OSUtils.is_windows() else "/bin/sh"
	var arguments := PackedStringArray(["/c", _launcher_path]) if OSUtils.is_windows() else PackedStringArray([_launcher_path])
	if not client.start(binary, arguments):
		failed.emit(T.t("gai_pi.bridge.start_failed"))
		client = null
		return false
	# pi buffers stdin while it boots, so the first probe can go out immediately.
	_boot_started_at = Time.get_ticks_msec()
	request_state()
	return true


func poll() -> void:
	if client == null:
		return
	client.poll()
	if is_ready:
		return
	var now := Time.get_ticks_msec()
	if now - _boot_started_at > BOOT_TIMEOUT_MS:
		var detail := client.stderr_tail(400) if client != null else StringUtils.EMPTY
		stop()
		failed.emit(T.t("gai_pi.bridge.no_answer") if detail.is_empty() else T.t("gai_pi.bridge.did_not_start", [detail]))
		return
	if now - _state_requested_at > 3000:
		request_state()


func stop() -> void:
	if session != null and session.running:
		RuntimeManager.end(session.local_id)
		session.running = false
	if client != null:
		client.stop()
	client = null
	is_ready = false


func session_list() -> Array[Dictionary]:
	return PiSessionIndex.list_for_workspace(workspace)


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

func request_state() -> void:
	if client == null or not client.is_running():
		return
	_state_requested_at = Time.get_ticks_msec()
	client.request("get_state", {}, on_state, STATE_TIMEOUT_MS)


func new_session() -> void:
	if not ensure_client():
		return
	var on_result := func(result: Dictionary) -> void:
		if not bool(result.get("success", false)):
			report_error(str(result.get("error", T.t("gai_pi.bridge.new_session_failed"))))
			return
		_needs_entries = true
		request_state()
	client.request("new_session", {}, on_result)


func switch_session(session_path: String) -> void:
	if not ensure_client() or session_path.is_empty():
		return
	_switch_started_at = Time.get_ticks_msec()
	var on_result := func(result: Dictionary) -> void:
		if not bool(result.get("success", false)):
			report_error(str(result.get("error", T.t("gai_pi.bridge.switch_failed"))))
			return
		timing("switch_session", _switch_started_at)
		var data := PiSession.as_dictionary(result.get("data", {}))
		if bool(data.get("cancelled", false)):
			report_error(T.t("gai_pi.bridge.switch_cancelled"))
			return
		load_session_file(session_path)
		request_state()
	client.request("switch_session", {"sessionPath": session_path}, on_result)


## Sends a user message. [param behavior] is "", "steer", or "followUp".
func prompt(text: String, behavior: String = StringUtils.EMPTY) -> void:
	if not ensure_client() or session == null:
		return
	if text.strip_edges().is_empty():
		return
	session.last_user_text = text
	session.add_user_entry(text)
	var params := {"message": text}
	if not behavior.is_empty():
		params["streamingBehavior"] = behavior
	var on_result := func(result: Dictionary) -> void:
		if not bool(result.get("success", false)):
			var message := str(result.get("error", T.t("gai_pi.bridge.prompt_rejected")))
			report_error(message)
			session.add_error_entry(message)
			return
		var data := PiSession.as_dictionary(result.get("data", {}))
		prompt_done.emit(str(data.get("disposition", "started")))
	client.request("prompt", params, on_result, PROMPT_TIMEOUT_MS)


func abort() -> void:
	if not ensure_client() or session == null:
		return
	var on_result := func(result: Dictionary) -> void:
		if not bool(result.get("success", false)):
			report_error(str(result.get("error", T.t("gai_pi.bridge.abort_failed"))))
	client.request("abort", {}, on_result)


func compact() -> void:
	if not ensure_client():
		return
	var on_result := func(result: Dictionary) -> void:
		if not bool(result.get("success", false)):
			report_error(str(result.get("error", T.t("gai_pi.bridge.compact_failed"))))
	client.request("compact", {}, on_result, COMPACT_TIMEOUT_MS)


func set_model(model_id: String) -> void:
	if not ensure_client():
		return
	var on_result := func(result: Dictionary) -> void:
		if not bool(result.get("success", false)):
			report_error(str(result.get("error", T.t("gai_pi.bridge.model_failed"))))
			return
		request_state()
	client.request("set_model", {"model": model_id}, on_result)


func set_thinking_level(level: String) -> void:
	if not ensure_client():
		return
	var on_result := func(result: Dictionary) -> void:
		if not bool(result.get("success", false)):
			report_error(str(result.get("error", T.t("gai_pi.bridge.thinking_failed"))))
			return
		thinking_level = level
		state_changed.emit()
	client.request("set_thinking_level", {"level": level}, on_result)


func get_models(callback: Callable) -> void:
	if not ensure_client():
		return
	client.request("get_available_models", {}, callback)


func set_session_name(name: String) -> void:
	if not ensure_client():
		return
	var on_result := func(_result: Dictionary) -> void:
		if session != null:
			session.title = name
			session.title_changed.emit(name)
	client.request("set_session_name", {"name": name}, on_result)


# ---------------------------------------------------------------------------
# Responses and events
# ---------------------------------------------------------------------------

func on_state(result: Dictionary) -> void:
	if not bool(result.get("success", false)):
		# pi is still booting; poll() retries.
		return
	var data := PiSession.as_dictionary(result.get("data", {}))
	var model: Dictionary = PiSession.as_dictionary(data.get("model", {}))
	model_label = str(model.get("name", model.get("id", StringUtils.EMPTY)))
	thinking_level = str(data.get("thinkingLevel", StringUtils.EMPTY))
	is_streaming = bool(data.get("isStreaming", false))

	var first_time := session == null
	if first_time:
		session = PiSession.new()
		session.workspace_root = workspace
		session.local_id = _next_local_id
		_next_local_id += 1
		session.running = is_streaming
		session.title_changed.connect(func(title: String) -> void:
			PiEvents.events.session_title_changed.emit(session.local_id, title)
		)
		session.usage_changed.connect(func(usage: OpenAiUsage) -> void:
			PiEvents.events.usage_changed.emit(session.local_id, usage)
		)
		session.state_changed.connect(func() -> void: state_changed.emit())
	session.pi_id = str(data.get("sessionId", session.pi_id))
	if session.path.is_empty():
		session.path = PiSessionIndex.path_for_id(workspace, session.pi_id)

	is_ready = true
	state_changed.emit()
	if first_time:
		ready.emit()
	if _needs_entries:
		_needs_entries = false
		load_entries()


## Checkpoint metadata for a session, or an empty list when checkpoints are off.
func checkpoint_records(session_id: String) -> Array[Dictionary]:
	if checkpoints == null:
		return []
	return checkpoints.load_turn_records(session_id)


## Renders a session from its file; the model context still comes from pi.
func load_session_file(session_path: String) -> void:
	if session == null:
		return
	session.path = session_path
	session.pi_id = PiSessionIndex.id_from_path(session_path)
	var started := Time.get_ticks_msec()
	session.rebuild(PiSessionIndex.load_branch_entries(session_path), checkpoint_records(session.pi_id))
	_needs_entries = false
	timing("file_rebuild", started)
	session_loaded.emit(session)


func load_entries() -> void:
	if client == null or session == null:
		return
	_entries_started_at = Time.get_ticks_msec()
	var on_result := func(result: Dictionary) -> void:
		if not bool(result.get("success", false)):
			return
		if session != null and session.running:
			# A run started before the replay arrived: the live transcript is authoritative.
			return
		timing("get_entries", _entries_started_at)
		var data := PiSession.as_dictionary(result.get("data", {}))
		session.rebuild(PiSession.as_array(data.get("entries", [])), checkpoint_records(session.pi_id))
		timing("rebuild", _entries_started_at)
		session_loaded.emit(session)
	client.request("get_entries", {}, on_result, 120000)


## Logs a phase duration when GAI_PI_TIMING=1, used while tuning session switching.
func timing(label: String, started_at: int) -> void:
	if OS.get_environment("GAI_PI_TIMING") == "1":
		print("[timing] ", label, " ", Time.get_ticks_msec() - started_at, "ms")


func on_event(data: Dictionary) -> void:
	var type := str(data.get("type", StringUtils.EMPTY))
	if type == "agent_start":
		is_streaming = true
		streaming_changed.emit(true)
	elif type == "agent_settled":
		is_streaming = false
		streaming_changed.emit(false)
		if session != null and not session.pi_id.is_empty() and session.path.is_empty():
			session.path = PiSessionIndex.path_for_id(workspace, session.pi_id)
			if not session.path.is_empty():
				state_changed.emit()
	if session != null:
		session.handle_event(data)


func on_ui_request(data: Dictionary) -> void:
	var method := str(data.get("method", StringUtils.EMPTY))
	match method:
		"setStatus", "setWidget", "setTitle":
			# Status chips and widgets have no shell surface yet.
			return
		"notify":
			notification.emit(str(data.get("message", StringUtils.EMPTY)), str(data.get("notifyType", "info")))
			return
		_:
			pass
	if str(data.get("id", StringUtils.EMPTY)).is_empty():
		return
	dialog_requested.emit(data)


## Answers one extension dialog with `{"value": ...}`, `{"confirmed": bool}`, or `{"cancelled": true}`.
func answer_dialog(id: String, payload: Dictionary) -> void:
	if client == null:
		return
	client.respond_ui(id, payload)


func on_closed(_exit_code: int) -> void:
	is_ready = false
	if session != null and session.running:
		session.running = false
		RuntimeManager.end(session.local_id)
	var detail := client.stderr_tail(400) if client != null else StringUtils.EMPTY
	failed.emit(T.t("gai_pi.bridge.exited") if detail.is_empty() else T.t("gai_pi.bridge.exited") + ": " + detail)


## Maps a missing runtime to a translated message; raw diagnostics stay in [PiPaths].
func localized_start_error() -> String:
	if PiPaths.error_code == "cli_missing":
		return T.t("gai_pi.bridge.cli_missing")
	return T.t("gai_pi.bridge.node_missing")


func ensure_client() -> bool:
	if client != null and client.is_running():
		return true
	report_error(T.t("gai_pi.bridge.not_running"))
	return false


func report_error(message: String) -> void:
	_last_command_error = message
	PiEvents.events.host_error.emit(message)


func last_error() -> String:
	return _last_command_error


# ---------------------------------------------------------------------------
# Launcher
# ---------------------------------------------------------------------------

func _write_launcher() -> bool:
	var directory := ProjectSettings.globalize_path("user://runtime")
	DirAccess.make_dir_recursive_absolute(directory)
	var windows := OSUtils.is_windows()
	_launcher_path = directory.path_join(LAUNCHER_CMD if windows else LAUNCHER_SH)
	var node := PiPaths.node_bin.replace("\\", "/")
	var cli := PiPaths.cli_js.replace("\\", "/")
	var root := workspace.replace("\\", "/")
	var content := StringUtils.EMPTY
	if windows:
		content = "@echo off\r\nchcp 65001 >nul\r\ncd /d \"%s\"\r\n\"%s\" \"%s\" --mode rpc\r\n" % [
			root.replace("/", "\\"), node.replace("/", "\\"), cli.replace("/", "\\"),
		]
	else:
		content = "#!/bin/sh\ncd \"%s\" || exit 1\nexec \"%s\" \"%s\" --mode rpc\n" % [root, node, cli]
	var file := FileAccess.open(_launcher_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	return true
