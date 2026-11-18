class_name ChatEntry
extends RefCounted

const KIND_SYSTEM := "system"
const KIND_SKILL := "skill"
const KIND_MEMORY := "memory"
const KIND_AGENT_PROMPT := "agent_prompt"
const KIND_USER := "user"
const KIND_AGENT := "agent"
const KIND_THINKING := "thinking"
const KIND_TOOL := "tool"
const KIND_WEB_TOOL := "web_tool"
const KIND_FILE_TOOL := "file_tool"
const KIND_EXPLORER_TOOL := "explorer_tool"
const KIND_GIT_DIFF := "git_diff"
const KIND_RESULT := "result"
const KIND_WEB := "web"
const KIND_ERROR := "error"
const KIND_COMPACTION := "compaction"
const KIND_CHECKPOINT := "checkpoint"

const TITLE_SYSTEM := "System"
const TITLE_SKILL := "Skills"
const TITLE_MEMORY := "Memory"
const TITLE_AGENT_PROMPT := "AGENTS.md"
const TITLE_USER := "You"
const TITLE_AGENT := "Agent"
const TITLE_THINKING := "Thinking"
const TITLE_RESULT := "Result"
const TITLE_GIT_DIFF := "Git Diff"
const TITLE_ERROR := "Error"
const TITLE_COMPACTION := "Context Summary"
const TITLE_CHECKPOINT := "Checkpoint"

const DETAIL_CHECKPOINT := "checkpoint"
const DETAIL_GIT_DIFF_PATCH := "git_diff_patch"

var kind: String = ""
var title: String = ""
var body: String = ""
var details: Dictionary[String, String] = {}

## pi identifiers this entry mirrors: message index for transcript blocks, tool call id for tools.
var id: String = ""
var tool_name: String = ""
var tool_call_id: String = ""
var is_error: bool = false
## True while a tool call or assistant block is still receiving data.
var running: bool = false
## Unix milliseconds when the source message was produced; 0 for shell-generated entries.
var timestamp: int = 0


## Context entries are seeded into the LLM history (system, skills, memory, AGENTS.md, compaction summary) instead of a chat turn.
static func is_context_kind(entry_kind: String) -> bool:
	return entry_kind == KIND_SYSTEM or entry_kind == KIND_SKILL or entry_kind == KIND_MEMORY or entry_kind == KIND_AGENT_PROMPT or entry_kind == KIND_COMPACTION


func _init(
	_kind: String = "",
	_title: String = "",
	_body: String = "",
	_details: Dictionary[String, String] = {}
) -> void:
	kind = _kind
	title = _title
	body = _body
	details = _details
	pass


func open_full_view() -> void:
	pass


# ---------------------------------------------------------------------------
# Deep clone
# ---------------------------------------------------------------------------

func deep_clone() -> ChatEntry:
	var cloned_details: Dictionary[String, String] = {}
	cloned_details.assign(details)
	var cloned := ChatEntry.new(kind, title, body, cloned_details)
	cloned.id = id
	cloned.tool_name = tool_name
	cloned.tool_call_id = tool_call_id
	cloned.is_error = is_error
	cloned.running = running
	cloned.timestamp = timestamp
	return cloned
