class_name AppSetting
extends Object

## Desktop preferences persisted in `user://gai-pi.cfg`.
##
## Only values the shell owns live here. Everything about the agent itself (model, thinking
## level, tools, skills, sessions) belongs to pi and is read back over RPC.

const CONFIG_PATH := "user://gai-pi.cfg"
const SECTION := "gai_pi"

const KEY_WORKSPACE := "workspace"
const KEY_VISUAL := "visual"
const KEY_PI_NODE := "pi_node"
const KEY_PI_CLI := "pi_cli"
const KEY_STEERING := "steering"
const KEY_AUTO_SCROLL := "auto_scroll"

static var _config: ConfigFile = null


static func config() -> ConfigFile:
	if _config == null:
		_config = ConfigFile.new()
		_config.load(CONFIG_PATH)
	return _config


static func get_string(key: String, default_value: String = StringUtils.EMPTY) -> String:
	var value: Variant = config().get_value(SECTION, key, default_value)
	return str(value)


static func set_string(key: String, value: String) -> void:
	config().set_value(SECTION, key, value)
	config().save(CONFIG_PATH)


static func get_int(key: String, default_value: int = 0) -> int:
	var value: Variant = config().get_value(SECTION, key, default_value)
	return int(value)


static func set_int(key: String, value: int) -> void:
	config().set_value(SECTION, key, value)
	config().save(CONFIG_PATH)


static func get_bool(key: String, default_value: bool = false) -> bool:
	var value: Variant = config().get_value(SECTION, key, default_value)
	return bool(value)


static func set_bool(key: String, value: bool) -> void:
	config().set_value(SECTION, key, value)
	config().save(CONFIG_PATH)
