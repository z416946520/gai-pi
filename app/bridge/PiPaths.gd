class_name PiPaths
extends Object

## Resolves everything the shell needs to launch pi: the Node.js runtime, the pi CLI bundle,
## the config directory, and the session directory.
##
## Resolution order is explicit override, environment, then the npm global layout. Nothing is
## installed by the app; it drives the pi the user already has.

const BUNDLE_RELATIVE := "node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js"
const ENV_NODE := "GAI_PI_NODE"
const ENV_CLI := "GAI_PI_CLI"
const ENV_CONFIG_DIR := "PI_CODING_AGENT_DIR"
const ENV_SESSION_DIR := "PI_CODING_AGENT_SESSION_DIR"

static var node_bin: String = StringUtils.EMPTY
static var cli_js: String = StringUtils.EMPTY
static var error_message: String = StringUtils.EMPTY


## Resolves the runtime pair; returns false and fills [member error_message] when unavailable.
static func resolve(force: bool = false) -> bool:
	if not force and is_resolved():
		return true
	node_bin = StringUtils.EMPTY
	cli_js = StringUtils.EMPTY
	error_message = StringUtils.EMPTY

	cli_js = _first_existing([
		AppSetting.get_string(AppSetting.KEY_PI_CLI),
		OS.get_environment(ENV_CLI),
	])
	if cli_js.is_empty():
		for root in _npm_roots():
			var candidate := root.path_join(BUNDLE_RELATIVE)
			if FileAccess.file_exists(candidate):
				cli_js = candidate
				break
	if cli_js.is_empty():
		error_message = "pi CLI bundle not found; install it with: npm i -g @earendil-works/pi-coding-agent"
		return false

	node_bin = _first_existing([
		AppSetting.get_string(AppSetting.KEY_PI_NODE),
		OS.get_environment(ENV_NODE),
		_which("node"),
		_which("node.exe"),
	])
	if node_bin.is_empty():
		# An npm install next to the launcher usually ships its own node on Windows.
		node_bin = _first_existing([cli_js.get_base_dir().path_join("node.exe")])
	if node_bin.is_empty():
		error_message = "Node.js runtime not found; install Node.js 20+ or set the runtime path in Settings"
		return false
	return true


static func is_resolved() -> bool:
	return not node_bin.is_empty() and not cli_js.is_empty() and FileAccess.file_exists(cli_js)


## pi's config directory: `PI_CODING_AGENT_DIR`, else `~/.pi/agent`.
static func config_dir() -> String:
	var override := OS.get_environment(ENV_CONFIG_DIR).strip_edges()
	if not override.is_empty():
		return override.simplify_path()
	return OS.get_environment("HOME").path_join(".pi/agent").simplify_path()


## Where pi keeps session JSONL files.
static func sessions_dir() -> String:
	var override := OS.get_environment(ENV_SESSION_DIR).strip_edges()
	if not override.is_empty():
		return override.simplify_path()
	return config_dir().path_join("sessions")


## Directory pi uses for one working directory, mirroring pi's own encoding:
## strip the leading separator, then replace `/`, `\` and `:` with `-`, wrapped in `--`.
static func session_folder(workspace: String) -> String:
	var normalized := workspace.replace("\\", "/").simplify_path()
	if normalized.begins_with("/"):
		normalized = normalized.substr(1)
	var encoded := normalized.replace("/", "-").replace(":", "-")
	return sessions_dir().path_join("--" + encoded + "--")


static func _npm_roots() -> PackedStringArray:
	var roots := PackedStringArray()
	var prefix := OS.get_environment("npm_config_prefix").strip_edges()
	if not prefix.is_empty():
		roots.append(prefix)
	if OSUtils.is_windows():
		var appdata := OS.get_environment("APPDATA").strip_edges()
		if not appdata.is_empty():
			roots.append(appdata.path_join("npm"))
		var program_files := OS.get_environment("ProgramFiles").strip_edges()
		if not program_files.is_empty():
			roots.append(program_files.path_join("nodejs"))
	else:
		roots.append("/usr/local")
		roots.append("/usr")
		var home := OS.get_environment("HOME").strip_edges()
		if not home.is_empty():
			roots.append(home.path_join(".npm-global"))
		roots.append(home.path_join(".nvm/versions/node/current"))
	return roots


static func _first_existing(candidates: Array[String]) -> String:
	for candidate in candidates:
		var path := candidate.strip_edges()
		if path.is_empty():
			continue
		if FileAccess.file_exists(path):
			return path
	return StringUtils.EMPTY


## Finds an executable on PATH without shelling out.
static func _which(binary: String) -> String:
	var path_var := OS.get_environment("PATH")
	var separator := ";" if OSUtils.is_windows() else ":"
	var extensions := PackedStringArray([StringUtils.EMPTY])
	if OSUtils.is_windows() and binary.get_extension().is_empty():
		extensions.append_array(PackedStringArray([".exe", ".cmd", ".bat"]))
	for folder in path_var.split(separator, false):
		for extension in extensions:
			var candidate := folder.path_join(binary + extension)
			if FileAccess.file_exists(candidate):
				return candidate
	return StringUtils.EMPTY
