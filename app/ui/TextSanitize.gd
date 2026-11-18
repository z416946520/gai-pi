class_name TextSanitize
extends Object

## Helpers for text that arrives from extensions or other processes.
##
## Extension status lines and widgets are written for a terminal: they carry ANSI escapes,
## carriage returns, and box glyphs. The desktop UI shows them as plain text.

const CSI_PATTERN := "\\x1b\\[[0-9;?]*[ -/]*[@-~]"
const OSC_PATTERN := "\\x1b\\][^\\x07\\x1b]*(\\x07|\\x1b\\\\)"


static func strip_ansi(text: String) -> String:
	var csi := RegEx.new()
	csi.compile(CSI_PATTERN)
	var cleaned := csi.sub(text, StringUtils.EMPTY, true)
	var osc := RegEx.new()
	if osc.compile(OSC_PATTERN) == OK:
		cleaned = osc.sub(cleaned, StringUtils.EMPTY, true)
	return cleaned.replace("\r", StringUtils.EMPTY)


## Joins multi-line terminal output into one bounded line for a status chip.
static func single_line(text: String, max_length: int = 48) -> String:
	var cleaned := strip_ansi(text).replace("\n", " ").replace("\t", " ").strip_edges()
	while cleaned.contains("  "):
		cleaned = cleaned.replace("  ", " ")
	if cleaned.length() > max_length:
		cleaned = cleaned.left(max_length - 1) + "…"
	return cleaned


## Keeps at most [param max_lines] non-empty widget lines, each bounded.
static func widget_lines(lines: Array, max_lines: int = 4, max_length: int = 120) -> PackedStringArray:
	var result := PackedStringArray()
	for value in lines:
		var line := strip_ansi(str(value)).strip_edges()
		if line.is_empty():
			continue
		if line.length() > max_length:
			line = line.left(max_length - 1) + "…"
		result.append(line)
		if result.size() >= max_lines:
			break
	return result
