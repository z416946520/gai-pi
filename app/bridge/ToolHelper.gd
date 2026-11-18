class_name ToolHelper
extends Object

## Tool classification shared by the copied effects.
##
## pi's built-in tools plus extension tools: anything that touches files, anywhere that
## reaches the network. Effects use this to pick colors and shapes for a tool call.

static func is_file_tool(tool_name: String) -> bool:
	return ToolVisualDisplay.FILE_TOOLS.has(tool_name)


static func is_web_tool(tool_name: String) -> bool:
	return tool_name.begins_with("web_") or tool_name.begins_with("browser_") or tool_name == "fetch" or tool_name == "search"


static func is_explorer_tool(tool_name: String) -> bool:
	return ToolVisualDisplay.EXPLORER_TOOLS.has(tool_name)
