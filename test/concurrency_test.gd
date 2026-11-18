extends SceneTree

## Two pi processes for the same workspace running at the same time.

var hosts: Array[PiWorkspace] = []
var ready_count := 0
var finished: Dictionary[int, String] = {}
var started := 0
var prompted := false


func _initialize() -> void:
	started = Time.get_ticks_msec()
	var workspace := ProjectSettings.globalize_path("res://")
	for index in 2:
		var host := PiWorkspace.new(workspace)
		host.local_id = index + 1
		host.ready.connect(on_ready)
		host.session_loaded.connect(func(session: PiSession) -> void:
			print("[conc] host ", host.local_id, " session=", session.pi_id)
		)
		hosts.append(host)
	if not hosts[0].start() or not hosts[1].start():
		print("[conc] FAIL start")
		quit(1)


func on_ready() -> void:
	ready_count += 1
	print("[conc] ready ", ready_count, "/2")
	if ready_count < 2:
		return
	for index in hosts.size():
		var host := hosts[index]
		host.session.run_finished.connect(func(_error: String) -> void: on_finished(host))
		host.prompt("Reply with exactly: concurrent-%d" % (index + 1))
	prompted = true


func on_finished(host: PiWorkspace) -> void:
	if finished.has(host.local_id):
		return
	finished[host.local_id] = latest_text(host)
	print("[conc] host ", host.local_id, " settled text=", JSON.stringify(finished[host.local_id]))


func latest_text(host: PiWorkspace) -> String:
	if host.session == null:
		return StringUtils.EMPTY
	for index in range(host.session.entries.size() - 1, -1, -1):
		var entry: ChatEntry = host.session.entries[index]
		if entry.kind == ChatEntry.KIND_AGENT and not entry.body.is_empty():
			return entry.body
	return StringUtils.EMPTY


func _process(_delta: float) -> bool:
	for host in hosts:
		host.poll()
	if prompted and finished.size() == 2:
		var a := str(finished.get(1, ""))
		var b := str(finished.get(2, ""))
		print("[conc] A=", JSON.stringify(a.left(40)), " B=", JSON.stringify(b.left(40)))
		if a.contains("concurrent-1") and b.contains("concurrent-2"):
			print("[conc] PASS")
			stop_all()
			quit(0)
		else:
			print("[conc] FAIL expected both answers")
			stop_all()
			quit(1)
		return true
	if Time.get_ticks_msec() - started > 180000:
		print("[conc] FAIL timeout ready=", ready_count, " finished=", finished.size())
		stop_all()
		quit(1)
		return true
	return false


func stop_all() -> void:
	for host in hosts:
		host.stop()
