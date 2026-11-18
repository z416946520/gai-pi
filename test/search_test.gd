extends SceneTree

## Headless check of the transcript matcher (no UI, no model call).

func _initialize() -> void:
	var entries: Array[ChatEntry] = []
	entries.append(_entry(ChatEntry.KIND_USER, "You", "Please refactor the Poller module."))
	entries.append(_entry(ChatEntry.KIND_AGENT, "Agent", "Done: poller.ts now uses events.\nTests pass."))
	entries.append(_entry(ChatEntry.KIND_FILE_TOOL, "Edit", "Successfully replaced 1 block(s) in src/poller.ts."))
	entries.append(_entry(ChatEntry.KIND_THINKING, "Thinking", "The POLLER loop is gone."))
	entries.append(_entry(ChatEntry.KIND_ERROR, "Error", "unrelated failure"))

	var hits := ChatSearch.find_matches(entries, "poller")
	print("[search] hits=", hits.size())
	if hits.size() != 4:
		print("[search] FAIL expected 4 case-insensitive hits")
		quit(1)
		return

	var snippet := ChatSearch.snippet("alpha beta gamma", 6)
	if not snippet.contains("beta"):
		print("[search] FAIL snippet=", snippet)
		quit(1)
		return

	var limited := ChatSearch.find_matches(entries, "poller", 2)
	if limited.size() != 2:
		print("[search] FAIL limit=", limited.size())
		quit(1)
		return

	var none := ChatSearch.find_matches(entries, "   ")
	if not none.is_empty():
		print("[search] FAIL empty query should match nothing")
		quit(1)
		return

	# Title-only matches still surface through entry.title.
	var title_hits := ChatSearch.find_matches(entries, "agent")
	if title_hits.is_empty():
		print("[search] FAIL title match")
		quit(1)
		return

	print("[search] PASS")
	quit(0)


func _entry(kind: String, title: String, body: String) -> ChatEntry:
	return ChatEntry.new(kind, title, body)
