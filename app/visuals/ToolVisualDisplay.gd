class_name ToolVisualDisplay
extends Object

## Tool name and glyph display strings for the visual effects.
##
## pi ships a smaller built-in set than the effects were written against, so the mapping
## covers pi's names plus extension tools and falls back to a derived label.

const NAME_READ := "read"
const NAME_WRITE := "write"
const NAME_EDIT := "edit"
const NAME_BASH := "bash"
const NAME_POWERSHELL := "powershell"
const NAME_GREP := "grep"
const NAME_FIND := "find"
const NAME_LS := "ls"

## pi built-in tools plus the names gai's effects were originally written for.
const FILE_TOOLS := ["read", "write", "edit", "delete", "read_image"]
const EXPLORER_TOOLS := ["grep", "find", "glob", "ls", "list_dir"]
const SHELL_TOOLS := ["bash", "powershell"]


static func readable_name(tool_name: String) -> String:
	return tool_name.replace("_", " ").replace("-", " ").strip_edges()


static func title_name(tool_name: String, empty_default: String = "Tool") -> String:
	var readable := readable_name(tool_name)
	return readable.capitalize() if not readable.is_empty() else empty_default


static func upper_name(tool_name: String, empty_default: String = "TOOL") -> String:
	var readable := readable_name(tool_name)
	return readable.to_upper() if not readable.is_empty() else empty_default


static func gate_name(tool_name: String, max_length: int = 7, empty_default: String = "TOOL") -> String:
	var readable := readable_name(tool_name)
	if readable.is_empty():
		return empty_default
	return String(readable.split(" ", false)[0]).left(max_length).to_upper()


static func glyph(tool_name: String) -> String:
	match tool_name:
		NAME_READ:
			return "R"
		NAME_WRITE:
			return "W"
		NAME_EDIT:
			return "E"
		NAME_BASH, NAME_POWERSHELL:
			return ">_"
		NAME_GREP:
			return "?"
		NAME_FIND:
			return "*"
		NAME_LS:
			return "/"
		_:
			return title_name(tool_name).left(2).to_upper()


static func glyph_emoji(tool_name: String) -> String:
	match tool_name:
		NAME_READ:
			return "📚"
		NAME_WRITE:
			return "🖊️"
		NAME_EDIT:
			return "✂️"
		NAME_BASH:
			return "🐚"
		NAME_POWERSHELL:
			return "🪟"
		NAME_GREP:
			return "🕵️"
		NAME_FIND:
			return "⭐"
		NAME_LS:
			return "📂"
		_:
			return "🤖"


## Transcript kind for one tool name; keeps file and explorer bubbles visually distinct.
static func entry_kind(tool_name: String) -> String:
	if FILE_TOOLS.has(tool_name):
		return ChatEntry.KIND_FILE_TOOL
	if EXPLORER_TOOLS.has(tool_name):
		return ChatEntry.KIND_EXPLORER_TOOL
	if tool_name.begins_with("web_") or tool_name.begins_with("browser_"):
		return ChatEntry.KIND_WEB_TOOL
	return ChatEntry.KIND_TOOL


## Short argument line shown in a tool bubble header, without dumping long content.
static func args_summary(tool_name: String, args: Dictionary) -> String:
	var keys := ["path", "file_path", "filePath", "command", "pattern", "query", "url", "description"]
	for key: String in keys:
		var value: Variant = args.get(key)
		if value == null:
			continue
		var text := str(value).strip_edges().replace("\n", " ")
		if text.is_empty():
			continue
		if text.length() > 96:
			text = text.left(93) + "..."
		return text
	return StringUtils.EMPTY
