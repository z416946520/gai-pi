class_name VLMServer
extends Object

## Stub for gai's local MiniCPM-V server. gai-pi does not ship a local vision model; image
## reading is delegated to the pi model provider instead.

static func is_running() -> bool:
	return false


static func server_url() -> String:
	return StringUtils.EMPTY
