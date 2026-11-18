class_name PiSession
extends RefCounted

## Transcript and run state for one pi session, built from live RPC events or from
## `get_entries` when a session is opened. The UI renders [member entries]; the visual
## effects are driven through [PiEvents].

signal entry_added(entry: ChatEntry)
signal entry_updated(entry: ChatEntry, stream_kind: String)
signal run_started
signal run_finished(error_message: String)
signal usage_changed(usage: OpenAiUsage)
signal title_changed(title: String)
signal queued_changed(steering: Array, follow_up: Array)
signal state_changed

var local_id: int = 0
var pi_id: String = StringUtils.EMPTY
var path: String = StringUtils.EMPTY
var title: String = StringUtils.EMPTY
var running: bool = false
var entries: Array[ChatEntry] = []
var usage: OpenAiUsage = OpenAiUsage.new()
var steering_queue: Array[String] = []
var follow_up_queue: Array[String] = []
var last_user_text: String = StringUtils.EMPTY

var _agent_entry: ChatEntry = null
var _thinking_entry: ChatEntry = null
var _tool_entries: Dictionary[String, ChatEntry] = {}
var _message_index: int = 0


# ---------------------------------------------------------------------------
# Live events
# ---------------------------------------------------------------------------

func handle_event(data: Dictionary) -> void:
	var type := str(data.get("type", StringUtils.EMPTY))
	match type:
		"agent_start":
			on_agent_start()
		"agent_end":
			on_agent_end(data)
		"agent_settled":
			on_agent_settled(data)
		"turn_start":
			PiEvents.events.turn_start.emit(local_id)
		"turn_end":
			PiEvents.events.turn_end.emit(local_id)
		"message_start":
			on_message_start(data)
		"message_update":
			on_message_update(data)
		"message_end":
			on_message_end(data)
		"tool_execution_start":
			on_tool_start(data)
		"tool_execution_update":
			on_tool_update(data)
		"tool_execution_end":
			on_tool_end(data)
		"queue_update":
			on_queue_update(data)
		"session_info_changed":
			on_session_info(data)
		"compaction_start":
			on_compaction_start(data)
		"compaction_end":
			on_compaction_end(data)
		"auto_retry_start":
			add_error_entry(T.t("gai_pi.chat.retrying", [int(data.get("attempt", 0)), int(data.get("maxAttempts", 0)), str(data.get("errorMessage", ""))]))
		"auto_retry_end":
			if not bool(data.get("success", true)):
				add_error_entry(T.t("gai_pi.chat.retry_failed", [str(data.get("finalError", "unknown"))]))
		_:
			pass


func on_agent_start() -> void:
	running = true
	_agent_entry = null
	_thinking_entry = null
	RuntimeManager.begin(local_id, self)
	PiEvents.events.agent_start.emit(local_id)
	run_started.emit()
	state_changed.emit()


func on_agent_end(data: Dictionary) -> void:
	# agent_end can still be followed by retries or queued work; the run ends at agent_settled.
	var will_retry := bool(data.get("willRetry", false))
	if will_retry:
		return


func on_agent_settled(data: Dictionary) -> void:
	var aborted := bool(data.get("aborted", false))
	running = false
	_agent_entry = null
	_thinking_entry = null
	for entry in entries:
		if entry.running:
			entry.running = false
			entry_updated.emit(entry, "content")
	RuntimeManager.end(local_id)
	PiEvents.events.agent_end.emit(local_id, "Aborted" if aborted else StringUtils.EMPTY)
	run_finished.emit("Aborted" if aborted else StringUtils.EMPTY)
	state_changed.emit()


func on_message_start(data: Dictionary) -> void:
	var message: Dictionary = as_dictionary(data.get("message", {}))
	var role := str(message.get("role", StringUtils.EMPTY))
	if role == "user":
		var text := content_text(message.get("content", StringUtils.EMPTY))
		if text.strip_edges() == last_user_text.strip_edges() and not last_user_text.is_empty():
			return
		if not text.strip_edges().is_empty():
			add_user_entry(text)
		return
	if role != "assistant":
		return
	_message_index += 1
	_agent_entry = null
	_thinking_entry = null


func on_message_update(data: Dictionary) -> void:
	var update: Dictionary = as_dictionary(data.get("assistantMessageEvent", {}))
	var kind := str(update.get("type", StringUtils.EMPTY))
	match kind:
		"text_start":
			ensure_agent_entry()
		"text_delta":
			var agent := ensure_agent_entry()
			agent.body += str(update.get("delta", StringUtils.EMPTY))
			agent.running = true
			entry_updated.emit(agent, "content")
			PiEvents.events.message_update.emit(local_id, str(update.get("delta", StringUtils.EMPTY)), OpenAiClient.STREAM_KIND_CONTENT)
		"text_end":
			var agent := ensure_agent_entry()
			agent.body = str(update.get("content", agent.body))
			entry_updated.emit(agent, "content")
		"thinking_start":
			ensure_thinking_entry()
		"thinking_delta":
			var thinking := ensure_thinking_entry()
			thinking.body += str(update.get("delta", StringUtils.EMPTY))
			thinking.running = true
			entry_updated.emit(thinking, "reasoning")
			PiEvents.events.message_update.emit(local_id, str(update.get("delta", StringUtils.EMPTY)), OpenAiClient.STREAM_KIND_REASONING)
		"thinking_end":
			var thinking := ensure_thinking_entry()
			thinking.body = str(update.get("content", thinking.body))
			entry_updated.emit(thinking, "reasoning")
		"toolcall_start":
			ensure_tool_entry(str(update.get("id", StringUtils.EMPTY)), str(update.get("toolName", StringUtils.EMPTY)), {})
		"toolcall_end":
			var call: Dictionary = as_dictionary(update.get("toolCall", {}))
			var entry := ensure_tool_entry(str(call.get("id", StringUtils.EMPTY)), str(call.get("name", StringUtils.EMPTY)), as_dictionary(call.get("arguments", {})))
			entry_updated.emit(entry, "content")
		"error":
			var error_text := str(update.get("error", "model stream error"))
			add_error_entry(error_text)
		_:
			pass
	update_usage(data.get("usage"))


func on_message_end(data: Dictionary) -> void:
	var message: Dictionary = as_dictionary(data.get("message", {}))
	if str(message.get("role", StringUtils.EMPTY)) != "assistant":
		return
	update_usage(message.get("usage"))
	var content: Variant = message.get("content", [])
	var text := StringUtils.EMPTY
	if typeof(content) == TYPE_ARRAY:
		for block_value in content as Array:
			var block: Dictionary = as_dictionary(block_value)
			match str(block.get("type", StringUtils.EMPTY)):
				"text":
					text += str(block.get("text", StringUtils.EMPTY))
				"thinking":
					var thinking := ensure_thinking_entry()
					thinking.body = str(block.get("thinking", thinking.body))
					thinking.running = false
					entry_updated.emit(thinking, "reasoning")
				"toolCall":
					ensure_tool_entry(str(block.get("id", StringUtils.EMPTY)), str(block.get("name", StringUtils.EMPTY)), as_dictionary(block.get("arguments", {})))
				_:
					pass
	elif typeof(content) == TYPE_STRING:
		text = str(content)
	if not text.is_empty():
		var agent := ensure_agent_entry()
		agent.body = text
		agent.running = false
		entry_updated.emit(agent, "content")
	elif _agent_entry != null:
		_agent_entry.running = false
		entry_updated.emit(_agent_entry, "content")
	PiEvents.events.message_complete.emit(local_id, usage)


func on_tool_start(data: Dictionary) -> void:
	var tool_name := str(data.get("toolName", StringUtils.EMPTY))
	var args: Dictionary = as_dictionary(data.get("args", {}))
	var entry := ensure_tool_entry(str(data.get("toolCallId", StringUtils.EMPTY)), tool_name, args)
	entry.running = true
	entry.body = PiSession.args_body(args)
	entry_updated.emit(entry, "content")
	PiEvents.events.tool_execution_start.emit(local_id, entry.tool_call_id, tool_name, args.duplicate())


func on_tool_update(data: Dictionary) -> void:
	var id := str(data.get("toolCallId", StringUtils.EMPTY))
	var entry: ChatEntry = _tool_entries.get(id)
	if entry == null:
		return
	var partial: Dictionary = as_dictionary(data.get("partialResult", {}))
	var text := result_text(partial)
	if not text.is_empty():
		entry.body = text
		entry_updated.emit(entry, "content")


func on_tool_end(data: Dictionary) -> void:
	var id := str(data.get("toolCallId", StringUtils.EMPTY))
	var tool_name := str(data.get("toolName", StringUtils.EMPTY))
	var entry := ensure_tool_entry(id, tool_name, as_dictionary(data.get("args", {})))
	var result: Dictionary = as_dictionary(data.get("result", {}))
	var text := result_text(result)
	var is_error := bool(data.get("isError", false))
	entry.running = false
	entry.is_error = is_error
	entry.body = text
	apply_result_details(entry, result)
	entry_updated.emit(entry, "content")
	var tool_result := AgentToolResult.new(text, is_error, entry.details.duplicate())
	PiEvents.events.tool_execution_end.emit(local_id, entry.tool_call_id, tool_name, tool_result)


func on_queue_update(data: Dictionary) -> void:
	steering_queue.clear()
	follow_up_queue.clear()
	for item_value in as_array(data.get("steering", [])):
		steering_queue.append(str(item_value))
	for item_value in as_array(data.get("followUp", [])):
		follow_up_queue.append(str(item_value))
	queued_changed.emit(steering_queue.duplicate(), follow_up_queue.duplicate())
	PiEvents.events.queue_changed.emit(local_id, steering_queue.duplicate(), follow_up_queue.duplicate())


func on_session_info(data: Dictionary) -> void:
	var name := str(data.get("name", StringUtils.EMPTY))
	if name.is_empty():
		return
	title = name
	title_changed.emit(title)
	state_changed.emit()


func on_compaction_start(data: Dictionary) -> void:
	var entry := ChatEntry.new(ChatEntry.KIND_COMPACTION, ChatEntry.TITLE_COMPACTION, "")
	entry.id = "compaction-%d" % entries.size()
	entry.running = true
	entries.append(entry)
	entry_added.emit(entry)
	PiEvents.events.chat_entry_add.emit(local_id, entry)


func on_compaction_end(data: Dictionary) -> void:
	var entry := find_entry_by_kind(ChatEntry.KIND_COMPACTION)
	if entry == null:
		return
	entry.running = false
	var result: Dictionary = as_dictionary(data.get("result", {}))
	entry.body = str(result.get("summary", StringUtils.EMPTY))
	if entry.body.is_empty():
		entry.body = str(data.get("errorMessage", T.t("gai_pi.chat.compact_failed")))
	entry_updated.emit(entry, "content")


# ---------------------------------------------------------------------------
# Persisted entries
# ---------------------------------------------------------------------------

## Rebuilds the transcript from `get_entries` output (append order, active-branch agnostic).
func rebuild(raw_entries: Array) -> void:
	entries.clear()
	_agent_entry = null
	_thinking_entry = null
	_tool_entries.clear()
	for value in raw_entries:
		var item: Dictionary = as_dictionary(value)
		match str(item.get("type", StringUtils.EMPTY)):
			"message":
				rebuild_message(as_dictionary(item.get("message", {})))
			"compaction":
				var compaction := ChatEntry.new(ChatEntry.KIND_COMPACTION, ChatEntry.TITLE_COMPACTION, str(item.get("summary", StringUtils.EMPTY)))
				compaction.id = str(item.get("id", StringUtils.EMPTY))
				append_entry(compaction)
			"branch_summary":
				var summary := ChatEntry.new(ChatEntry.KIND_SYSTEM, "Branch Summary", str(item.get("summary", StringUtils.EMPTY)))
				summary.id = str(item.get("id", StringUtils.EMPTY))
				append_entry(summary)
			_:
				pass
	state_changed.emit()


func rebuild_message(message: Dictionary) -> void:
	var role := str(message.get("role", StringUtils.EMPTY))
	match role:
		"user":
			var text := content_text(message.get("content", StringUtils.EMPTY))
			if not text.strip_edges().is_empty():
				var entry := ChatEntry.new(ChatEntry.KIND_USER, ChatEntry.TITLE_USER, text)
				entry.id = str(message.get("timestamp", ""))
				append_entry(entry)
		"assistant":
			var content: Variant = message.get("content", [])
			var text := StringUtils.EMPTY
			var thinking_text := StringUtils.EMPTY
			if typeof(content) == TYPE_ARRAY:
				for block_value in content as Array:
					var block: Dictionary = as_dictionary(block_value)
					match str(block.get("type", StringUtils.EMPTY)):
						"text":
							text += str(block.get("text", StringUtils.EMPTY))
						"thinking":
							thinking_text += str(block.get("thinking", StringUtils.EMPTY))
						"toolCall":
							ensure_tool_entry(str(block.get("id", StringUtils.EMPTY)), str(block.get("name", StringUtils.EMPTY)), as_dictionary(block.get("arguments", {})))
						_:
							pass
			elif typeof(content) == TYPE_STRING:
				text = str(content)
			if not thinking_text.is_empty():
				var thinking := ChatEntry.new(ChatEntry.KIND_THINKING, ChatEntry.TITLE_THINKING, thinking_text)
				append_entry(thinking)
			if not text.is_empty():
				var agent := ChatEntry.new(ChatEntry.KIND_AGENT, ChatEntry.TITLE_AGENT, text)
				append_entry(agent)
		"toolResult":
			var id := str(message.get("toolCallId", StringUtils.EMPTY))
			var entry: ChatEntry = _tool_entries.get(id)
			if entry == null:
				entry = ChatEntry.new(ChatEntry.KIND_TOOL, str(message.get("toolName", ChatEntry.TITLE_RESULT)), "")
				entry.tool_call_id = id
				append_entry(entry)
				_tool_entries[id] = entry
			entry.is_error = bool(message.get("isError", false))
			entry.running = false
			entry.body = result_text(message)
			apply_result_details(entry, message)
		_:
			pass


# ---------------------------------------------------------------------------
# Entry helpers
# ---------------------------------------------------------------------------

func add_user_entry(text: String) -> void:
	var entry := ChatEntry.new(ChatEntry.KIND_USER, ChatEntry.TITLE_USER, text)
	append_entry(entry)


func add_error_entry(text: String) -> void:
	var entry := ChatEntry.new(ChatEntry.KIND_ERROR, ChatEntry.TITLE_ERROR, text)
	entry.is_error = true
	append_entry(entry)


func append_entry(entry: ChatEntry) -> void:
	entries.append(entry)
	entry_added.emit(entry)
	PiEvents.events.chat_entry_add.emit(local_id, entry)


func ensure_agent_entry() -> ChatEntry:
	if _agent_entry != null:
		return _agent_entry
	var entry := ChatEntry.new(ChatEntry.KIND_AGENT, ChatEntry.TITLE_AGENT, "")
	entry.id = "assistant-%d" % _message_index
	_agent_entry = entry
	append_entry(entry)
	return entry


func ensure_thinking_entry() -> ChatEntry:
	if _thinking_entry != null:
		return _thinking_entry
	var entry := ChatEntry.new(ChatEntry.KIND_THINKING, ChatEntry.TITLE_THINKING, "")
	entry.id = "thinking-%d" % _message_index
	_thinking_entry = entry
	append_entry(entry)
	return entry


func ensure_tool_entry(tool_call_id: String, tool_name: String, args: Dictionary) -> ChatEntry:
	if tool_call_id.is_empty():
		tool_call_id = "tool-%d" % entries.size()
	var existing: ChatEntry = _tool_entries.get(tool_call_id)
	if existing != null:
		if not args.is_empty():
			existing.details["args"] = PiSession.args_body(args)
			var summary := ToolVisualDisplay.args_summary(tool_name, args)
			if not summary.is_empty():
				existing.details["summary"] = summary
		return existing
	var entry := ChatEntry.new(ToolVisualDisplay.entry_kind(tool_name), ToolVisualDisplay.title_name(tool_name), "")
	entry.id = tool_call_id
	entry.tool_call_id = tool_call_id
	entry.tool_name = tool_name
	entry.running = true
	entry.details["summary"] = ToolVisualDisplay.args_summary(tool_name, args)
	entry.details["args"] = PiSession.args_body(args)
	_tool_entries[tool_call_id] = entry
	append_entry(entry)
	return entry


func find_entry_by_kind(kind: String) -> ChatEntry:
	for index in range(entries.size() - 1, -1, -1):
		if entries[index].kind == kind:
			return entries[index]
	return null


func update_usage(value: Variant) -> void:
	var data := as_dictionary(value)
	if data.is_empty():
		return
	usage.prompt_tokens = int(data.get("input", usage.prompt_tokens))
	usage.completion_tokens = int(data.get("output", usage.completion_tokens))
	usage.total_tokens = int(data.get("totalTokens", usage.total_tokens))
	usage_changed.emit(usage)
	PiEvents.events.usage_changed.emit(local_id, usage)


func apply_result_details(entry: ChatEntry, result: Dictionary) -> void:
	var details: Dictionary = as_dictionary(result.get("details", {}))
	if details.is_empty():
		return
	for key: String in ["diff", "patch", "firstChangedLine", "fullOutputPath"]:
		var value: Variant = details.get(key)
		if value == null:
			continue
		entry.details[key] = str(value)


# ---------------------------------------------------------------------------
# Value helpers
# ---------------------------------------------------------------------------

static func as_dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value as Dictionary
	return {}


static func as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value as Array
	return []


static func content_text(content: Variant) -> String:
	if typeof(content) == TYPE_STRING:
		return str(content)
	if typeof(content) != TYPE_ARRAY:
		return StringUtils.EMPTY
	var text := StringUtils.EMPTY
	for block_value in content as Array:
		var block: Dictionary = as_dictionary(block_value)
		if str(block.get("type", StringUtils.EMPTY)) == "text":
			text += str(block.get("text", StringUtils.EMPTY))
	return text


## Tool output as plain text; pi shapes results as `{"content": [{type:text,text}]}`.
static func result_text(result: Dictionary) -> String:
	if result.has("content"):
		var text := content_text(result.get("content"))
		if not text.is_empty():
			return text
	if result.has("body"):
		return str(result.get("body"))
	return StringUtils.EMPTY


static func args_body(args: Dictionary) -> String:
	if args.is_empty():
		return StringUtils.EMPTY
	var text := JSON.stringify(args, "  ")
	if text.length() > 4000:
		text = text.left(4000) + "\n..."
	return text
