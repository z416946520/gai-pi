class_name ChatSearch
extends Object

## Case-insensitive transcript search over [ChatEntry] values.
##
## Kept free of UI so the matcher can be exercised headlessly; the panel only renders the
## results and asks [Main] to reveal one.

const SNIPPET_RADIUS := 44
const MAX_RESULTS := 60


static func find_matches(entries: Array[ChatEntry], query: String, limit: int = MAX_RESULTS, lower_cache: Dictionary = {}) -> Array[Dictionary]:
	var needle := query.strip_edges().to_lower()
	var results: Array[Dictionary] = []
	if needle.is_empty():
		return results
	for entry in entries:
		if entry == null:
			continue
		var body_lower: String = lower_cache.get(entry, "")
		if body_lower.is_empty():
			body_lower = entry.body.to_lower()
			if not lower_cache.is_empty():
				lower_cache[entry] = body_lower
		var body_at := body_lower.find(needle)
		var title_at := entry.title.to_lower().find(needle)
		if body_at < 0 and title_at < 0:
			continue
		results.append({
			"entry": entry,
			"kind": entry.kind,
			"snippet": snippet(entry.body, body_at),
			"title_hit": body_at < 0,
		})
		if results.size() >= limit:
			break
	return results


## One line around the match, with the line breaks around it collapsed.
static func snippet(body: String, match_index: int) -> String:
	if body.is_empty():
		return StringUtils.EMPTY
	if match_index < 0:
		match_index = 0
	var start := maxi(0, match_index - SNIPPET_RADIUS)
	var end := mini(body.length(), match_index + SNIPPET_RADIUS)
	var text := body.substr(start, end - start)
	text = text.replace("\r", " ").replace("\n", " ").replace("\t", " ")
	while text.contains("  "):
		text = text.replace("  ", " ")
	text = text.strip_edges()
	if start > 0:
		text = "…" + text
	if end < body.length():
		text = text + "…"
	return text


## Localized label for a result row; unknown kinds fall back to the title.
static func kind_label(kind: String) -> String:
	match kind:
		ChatEntry.KIND_USER:
			return T.t("gai_pi.bubble.you")
		ChatEntry.KIND_AGENT:
			return T.t("gai_pi.bubble.agent")
		ChatEntry.KIND_THINKING:
			return T.t("gai_pi.bubble.thinking")
		ChatEntry.KIND_ERROR:
			return T.t("gai_pi.bubble.error")
		ChatEntry.KIND_COMPACTION:
			return T.t("gai_pi.bubble.compaction")
		ChatEntry.KIND_CHECKPOINT:
			return T.t("gai_pi.bubble.checkpoint")
		ChatEntry.KIND_TOOL, ChatEntry.KIND_FILE_TOOL, ChatEntry.KIND_EXPLORER_TOOL, ChatEntry.KIND_WEB_TOOL:
			return T.t("gai_pi.search.tool")
		_:
			return T.t("gai_pi.bubble.system")
