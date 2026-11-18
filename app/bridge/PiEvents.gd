class_name PiEvents
extends RefCounted

## Application-wide notification bus for the desktop shell.
##
## Signal names and payloads follow the contract gai's visual effects were written against,
## so the copied effects drive off pi events without modification. Session ids are the
## shell's local integer ids; pi's UUIDs stay inside the bridge.

static var events := Events.new()


class Events:
	# Agent run lifecycle, from pi's agent_start/agent_end/agent_settled.
	signal agent_start(session_id: int)
	signal agent_end(session_id: int, error_message: String)
	signal turn_start(session_id: int)
	signal turn_end(session_id: int)

	# Streaming assistant text. chunk is a delta, stream_kind is "content" or "reasoning".
	signal message_update(session_id: int, chunk: String, stream_kind: String)
	signal message_complete(session_id: int, usage: OpenAiUsage)

	# Tool lifecycle.
	signal tool_execution_start(session_id: int, tool_call_id: String, tool_name: String, args: Dictionary)
	signal tool_execution_end(session_id: int, tool_call_id: String, tool_name: String, agent_tool_result: AgentToolResult)

	# Transcript entries, emitted for the UI only.
	signal chat_entry_add(session_id: int, entry: ChatEntry)
	signal chat_entry_update(session_id: int, entry: ChatEntry, stream_kind: String)

	# Session/protocol state.
	signal session_ready(session_id: int)
	signal session_title_changed(session_id: int, title: String)
	signal usage_changed(session_id: int, usage: OpenAiUsage)
	signal queue_changed(session_id: int, steering: Array, follow_up: Array)
	signal thinking_level_changed(level: String)
	signal model_changed(label: String)
	signal host_error(message: String)
	signal workspace_changed(path: String)

	pass
