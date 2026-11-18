class_name LlamaHelper
extends Object

## Token value objects for the transformer effect.
##
## gai tokenized through a local llama.cpp server; gai-pi has no local VLM, so health always
## answers false and the effect falls back to [LocalTokenizer]. The stubs keep the effect's
## existing call sites valid.

class Token extends RefCounted:
	var id: int
	var piece: String

	func _init(token_id: int, token_piece: String) -> void:
		id = token_id
		piece = token_piece


class TokenizeResult extends RefCounted:
	var tokens: Array[Token] = []
	var total_tokens: int = 0


static func async_health(_server_url: String) -> bool:
	return false


static func async_tokenize(_server_url: String, prompt: String) -> TokenizeResult:
	var result := TokenizeResult.new()
	result.tokens = LocalTokenizer.tokenize(prompt)
	result.total_tokens = result.tokens.size()
	return result
