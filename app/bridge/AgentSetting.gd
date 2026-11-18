class_name AgentSetting
extends Object

## Compatibility shim for copied effects that read limits from gai's settings.
## pi owns its own iteration limit, so the shell only needs a sane display value.

const DEFAULT_MAX_TURNS := 60


static func get_max_turns() -> int:
	return DEFAULT_MAX_TURNS
