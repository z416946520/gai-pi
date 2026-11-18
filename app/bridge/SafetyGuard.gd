class_name SafetyGuard
extends Object

## Best-effort tool guard used when safety mode is on.
##
## pi executes tools inside its own process, so the shell cannot veto a call before it runs.
## What it can do: inspect the announced call, and abort the run when a file tool points
## outside the workspace or a shell command matches a destructive pattern.

const FILE_TOOLS := ["read", "write", "edit", "delete", "read_image"]
const SHELL_TOOLS := ["bash", "powershell"]
const PATH_KEYS := ["path", "file_path", "filePath", "target"]

const DANGEROUS_PATTERNS := [
	"rm -rf ~", "rm -fr ~", "mkfs", "format c:", "format /", "dd if=", "of=/dev/",
	"shutdown", "reboot", "halt", ":(){", "chmod -R 777 /", "> /dev/sda",
	"del /f /s /q c:\\",
]


## Returns "" when the call is acceptable, otherwise a short reason key.
## [param workspace] must be an absolute, normalized path.
static func inspect(tool_name: String, args: Dictionary, workspace: String) -> String:
	if FILE_TOOLS.has(tool_name):
		var raw := _path_arg(args)
		if raw.is_empty():
			return StringUtils.EMPTY
		return "" if is_inside(raw, workspace) else "outside_workspace"
	if SHELL_TOOLS.has(tool_name):
		var command := str(args.get("command", StringUtils.EMPTY)).to_lower()
		for pattern in DANGEROUS_PATTERNS:
			if command.contains(pattern):
				return "dangerous_command"
		if _wipes_root(command):
			return "dangerous_command"
		if _pipes_download_to_shell(command):
			return "dangerous_command"
	return StringUtils.EMPTY


static func is_inside(path: String, workspace: String) -> bool:
	var root := workspace.replace("\\", "/").simplify_path().trim_suffix("/")
	var target := path.replace("\\", "/").simplify_path()
	if target.begins_with("./"):
		target = target.substr(2)
	if not target.is_absolute_path():
		target = root.path_join(target).simplify_path()
	if target == root:
		return true
	return target.begins_with(root + "/")


## `rm -rf /` and `/ *` wipe the disk; `rm -rf /tmp/x` is destructive but not that.
static func _wipes_root(command: String) -> bool:
	for flag in [" -rf /", " -fr /", " -rf /*", " -fr /*"]:
		var at := command.find(flag)
		if at < 0:
			continue
		var after := command.substr(at + flag.length(), 1)
		if after.is_empty() or after == " " or after == "*" or after == "-":
			return true
	return false


static func _pipes_download_to_shell(command: String) -> bool:
	if not (command.contains("curl") or command.contains("wget")):
		return false
	for marker in ["| sh", "|sh", "| bash", "|bash"]:
		if command.contains(marker):
			return true
	return false


static func _path_arg(args: Dictionary) -> String:
	for key in PATH_KEYS:
		var value := str(args.get(key, StringUtils.EMPTY)).strip_edges()
		if not value.is_empty():
			return value
	return StringUtils.EMPTY
