extends SceneTree

## Headless verification of the pi bridge: launch, state, entries, prompt, stream, settle.
##
##   godot --headless --path . --script test/bridge_smoke.gd
##
## Set GAI_PI_SMOKE_PROMPT=0 to stop after the session loads (no model call).

var host: PiWorkspace = null
var started := 0
var phase := "starting"
var text := ""
var prompt_sent_at := 0
var saw_delta := false
var switch_target := ""


func _initialize() -> void:
	started = Time.get_ticks_msec()
	print("[smoke] config dir: ", PiPaths.config_dir())
	print("[smoke] sessions dir: ", PiPaths.sessions_dir())
	print("[smoke] node: ", PiPaths.node_bin, " cli: ", PiPaths.cli_js)
	if not PiPaths.resolve():
		print("[smoke] FAIL ", PiPaths.error_message)
		quit(1)
		return
	host = PiWorkspace.new(ProjectSettings.globalize_path("res://"))
	host.ready.connect(on_ready)
	host.failed.connect(on_failed)
	host.session_loaded.connect(on_loaded)
	if not host.start():
		quit(1)


func on_ready() -> void:
	phase = "ready"
	print("[smoke] PASS ready model=", host.model_label, " thinking=", host.thinking_level, " session=", host.session.pi_id if host.session != null else "?")
	if OS.get_environment("GAI_PI_SMOKE_SWITCH") == "1":
		try_switch()
		return
	if OS.get_environment("GAI_PI_SMOKE_PROMPT") == "0":
		finish(0)
		return
	if host.session != null:
		host.session.entry_added.connect(on_entry_added)
		host.session.run_finished.connect(on_run_finished)
	phase = "prompting"
	prompt_sent_at = Time.get_ticks_msec()
	host.prompt("Reply with exactly: gai-pi bridge ok")
	print("[smoke] prompt sent")


func on_loaded(session: PiSession) -> void:
	print("[smoke] entries loaded: ", session.entries.size(), " path=", session.path)
	if phase == "switching":
		# The initial load can land after the switch was sent; only trust the target's rebuild.
		if not switch_target.is_empty() and session.path != switch_target:
			print("[smoke] ignoring stale rebuild path=", session.path)
			return
		if session.entries.is_empty():
			print("[smoke] FAIL switch produced no entries")
			finish(1)
			return
		print("[smoke] PASS switch rebuilt ", session.entries.size(), " entries")
		finish(0)


## Verifies the sidebar path: list sessions from disk, switch to another one, rebuild entries.
func try_switch() -> void:
	var candidates := PiSessionIndex.list_for_workspace(host.workspace)
	print("[smoke] sessions on disk: ", candidates.size())
	var target := ""
	for meta in candidates:
		var path := str(meta.get("path", ""))
		if path == host.session.path:
			continue
		if str(meta.get("title", "")) == "New session":
			continue
		target = path
		print("[smoke] switching to ", path.get_file(), " title=", meta.get("title", ""))
		break
	if target.is_empty():
		print("[smoke] FAIL no other session with messages to switch to")
		finish(1)
		return
	phase = "switching"
	switch_target = target
	host.switch_session(target)


func on_entry_added(entry: ChatEntry) -> void:
	if entry.kind == ChatEntry.KIND_AGENT:
		text = entry.body


func on_stream_delta(chunk: String, kind: String) -> void:
	if kind == "content":
		saw_delta = true


func on_run_finished(error_message: String) -> void:
	if not error_message.is_empty():
		print("[smoke] FAIL run finished with error: ", error_message)
		finish(1)
		return
	print("[smoke] PASS settled assistant=", JSON.stringify(latest_agent_text()))
	finish(0)


func latest_agent_text() -> String:
	if host.session == null:
		return ""
	for index in range(host.session.entries.size() - 1, -1, -1):
		var entry: ChatEntry = host.session.entries[index]
		if entry.kind == ChatEntry.KIND_AGENT and not entry.body.is_empty():
			return entry.body
	return ""


func on_failed(message: String) -> void:
	print("[smoke] FAIL ", message)
	if host != null and host.client != null:
		print("[smoke] stderr: ", host.client.stderr_tail(800))
	finish(1)


func _process(_delta: float) -> bool:
	if host != null:
		host.poll()
	if host != null and host.session != null and phase == "prompting" and not saw_delta:
		if not host.session.running and Time.get_ticks_msec() - prompt_sent_at > 2000 and latest_agent_text().is_empty():
			print("[smoke] waiting for agent…")
	var elapsed := Time.get_ticks_msec() - started
	if elapsed > 180000:
		print("[smoke] FAIL timeout phase=", phase)
		finish(1)
		return true
	return false


func finish(code: int) -> void:
	if host != null:
		host.stop()
	quit(code)
