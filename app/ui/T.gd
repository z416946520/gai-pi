class_name T
extends Object

## Shell translation lookup. Every user-facing string in gai-pi lives under `gai_pi.*` in
## `app/locale/zh.json` and `app/locale/en.json`; `{}` marks an argument.
##
## Missing keys fall back to the key itself so a forgotten entry is visible instead of silent.

static func t(key: String, values: Array = []) -> String:
	var text := I18n.t(key)
	if text == key:
		return key
	if values.is_empty():
		return text
	return text.format(values, "{}")


## Locale code the UI is currently running in: "zh" or "en".
static func locale_code() -> String:
	return "zh" if I18n.get_locale().begins_with("zh") else "en"
