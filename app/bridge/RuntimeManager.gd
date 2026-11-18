class_name RuntimeManager
extends Object

## Which shell sessions have an agent run in flight.
##
## The copied visual effects read [member runtimes] directly to keep the shared overlay alive
## until the last run stops. Values are [PiSession] instances.

static var runtimes: Dictionary[int, PiSession] = {}


static func is_running(session_id: int) -> bool:
	return runtimes.has(session_id)


static func begin(session_id: int, session: PiSession) -> void:
	runtimes[session_id] = session


static func end(session_id: int) -> void:
	runtimes.erase(session_id)


static func is_active() -> bool:
	return not runtimes.is_empty()
