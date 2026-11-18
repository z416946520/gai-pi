class_name ChatEntryCursor
extends RefCounted

## Incremental sentence feed from the live transcript to the visual effects.
##
## Agent text is consumed sentence by sentence so effects render whole phrases instead of
## tokens. Each session keeps its own cursor, so interleaved runs never reread or skip text.

class ChatEntrySentence:
	extends RefCounted

	var text: String = ""
	var entry: ChatEntry = null

	func _init(sentence_text: String = "", sentence_entry: ChatEntry = null) -> void:
		text = sentence_text
		entry = sentence_entry

	func is_empty() -> bool:
		return text.is_empty()


class SentenceParse:
	extends RefCounted

	var text: String = ""
	var next_index: int = 0

	func _init(sentence_text: String = "", sentence_next_index: int = 0) -> void:
		text = sentence_text
		next_index = sentence_next_index


# ---------------------------------------------------------------------------
# Instance cursor operations
# ---------------------------------------------------------------------------

var chat_entry_index: int = 0
var entry_char_index: int = 0


func reset(entries: Array[ChatEntry]) -> void:
	chat_entry_index = find_latest_user_entry(entries)
	entry_char_index = 0


## Next complete sentence and its source entry; an unfinished tail stays unconsumed.
func take_next(entries: Array[ChatEntry]) -> ChatEntrySentence:
	while chat_entry_index < entries.size():
		var entry: ChatEntry = entries[chat_entry_index]
		var parse := parse_sentence(entry.body, entry_char_index)
		entry_char_index = parse.next_index
		if not parse.text.is_empty():
			return ChatEntrySentence.new(parse.text, entry)
		if chat_entry_index == entries.size() - 1:
			return ChatEntrySentence.new()
		chat_entry_index += 1
		entry_char_index = 0
	return ChatEntrySentence.new()


static func parse_sentence(text: String, start_index: int) -> SentenceParse:
	var start := clampi(start_index, 0, text.length())
	while start < text.length() and text.substr(start, 1).strip_edges().is_empty():
		start += 1
	for index in range(start, text.length()):
		if not StringUtils.is_sentence_end(text.substr(start, index - start + 1)):
			continue
		return SentenceParse.new(text.substr(start, index - start + 1).strip_edges(), index + 1)
	return SentenceParse.new(StringUtils.EMPTY, start)


# ---------------------------------------------------------------------------
# Shared session cursor cache
# ---------------------------------------------------------------------------

static var session_cursors: Dictionary[int, ChatEntryCursor] = {}


static func take_next_sentence() -> ChatEntrySentence:
	for session_id: int in RuntimeManager.runtimes:
		var sentence := take_next_sentence_from_session(session_id)
		if not sentence.is_empty():
			return sentence
	return ChatEntrySentence.new()


static func take_next_sentence_from_session(session_id: int) -> ChatEntrySentence:
	var session: PiSession = RuntimeManager.runtimes.get(session_id)
	if session == null:
		remove_session(session_id)
		return ChatEntrySentence.new()
	var has_cursor := session_cursors.has(session_id)
	var cursor := get_or_create_cursor(session_id)
	if not has_cursor:
		cursor.reset(session.entries)
	return cursor.take_next(session.entries)


## Most recent non-blank entry of [param kind] since [param start_index]; does not advance state.
static func latest_entry_text(session_id: int, start_index: int, kind: String) -> String:
	var session: PiSession = RuntimeManager.runtimes.get(session_id)
	if session == null:
		return StringUtils.EMPTY
	for index in range(session.entries.size() - 1, start_index - 1, -1):
		var entry: ChatEntry = session.entries[index]
		if entry.kind == kind and StringUtils.is_not_blank(entry.body):
			return entry.body
	return StringUtils.EMPTY


## Effect-ready color for one entry kind, derived from the bubble accent and the theme.
static func color_for_entry_kind(entry_kind: String) -> Color:
	var accent := ChatBubble.accent_for_kind(entry_kind)
	return VisualColor.appearance_color(ThemeColor.mix_with_theme_color(accent, 0.18))


static func remove_session(session_id: int) -> void:
	session_cursors.erase(session_id)
	pass


static func get_or_create_cursor(session_id: int) -> ChatEntryCursor:
	var cursor: ChatEntryCursor = session_cursors.get(session_id)
	if cursor == null:
		cursor = ChatEntryCursor.new()
		session_cursors[session_id] = cursor
	return cursor


static func find_latest_user_entry(entries: Array[ChatEntry]) -> int:
	for index in range(entries.size() - 1, -1, -1):
		if entries[index].kind == ChatEntry.KIND_USER:
			return index
	return entries.size()
