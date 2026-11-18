class_name MentionScan
extends Object

## Minimal `@path` scanner shared by the Markdown highlighter.
##
## Copied behaviour from gai's chat input completion: a mention starts at `@` when it begins
## a token, and ends at the next token break.

const MENTION := "@"
const TOKEN_BREAKS := ",;!?()[]{}<>\"'“”‘’，。；：！？、（）【】「」《》"


static func mention_start(prefix: String) -> int:
	var start := prefix.length()
	while start > 0 and not is_token_break(prefix.unicode_at(start - 1)):
		start -= 1
	var token := prefix.substr(start)
	var mention_at := token.rfind(MENTION)
	if mention_at < 0:
		return -1
	if mention_at > 0 and token.unicode_at(mention_at - 1) < 128:
		return -1
	return start + mention_at


static func token_end(line: String, caret_column: int) -> int:
	var end := caret_column
	while end < line.length() and not is_token_break(line.unicode_at(end)):
		end += 1
	return end


static func is_token_break(code: int) -> bool:
	if code <= 32:
		return true
	return TOKEN_BREAKS.contains(String.chr(code))
