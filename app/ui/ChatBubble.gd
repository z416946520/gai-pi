class_name ChatBubble
extends PanelContainer

## One transcript row: user message, assistant text, thinking, tool call, diff, or notice.
##
## Bodies are rendered progressively: [method apply_entry] re-renders markdown only when a
## bubble is marked dirty, and the shell flushes dirty bubbles at a fixed rate so a fast
## stream cannot re-parse markdown on every token.

signal expand_toggled

const COLLAPSED_LINES := 14
const STREAMING_COLLAPSED_LINES := 400

const COLOR_ADDED := Color("#7ddc9a")
const COLOR_REMOVED := Color("#ff8f8f")
const COLOR_CONTEXT := Color("#7d8490")

var entry: ChatEntry = null
var expanded: bool = false
var dirty: bool = true

var _badge: Label = null
var _title: Label = null
var _meta: Label = null
var _body: RichTextLabel = null
var _expand_button: Button = null
var _header: HBoxContainer = null


func setup(target: ChatEntry) -> void:
	entry = target
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()
	refresh()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", Margin.ma_3)
	margin.add_theme_constant_override("margin_right", Margin.ma_3)
	margin.add_theme_constant_override("margin_top", Margin.ma_2)
	margin.add_theme_constant_override("margin_bottom", Margin.ma_2)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", Margin.ma_1)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(column)

	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", Margin.ma_2)
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.gui_input.connect(on_header_input)
	column.add_child(_header)

	_badge = Label.new()
	_badge.add_theme_font_override("font", Fonts.code())
	_badge.add_theme_font_size_override("font_size", Typography.body_small)
	_badge.custom_minimum_size = Vector2(26, 0)
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header.add_child(_badge)

	_title = Label.new()
	_title.add_theme_font_override("font", Fonts.semibold())
	_title.add_theme_font_size_override("font_size", Typography.body_small)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.clip_text = true
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(_title)

	_meta = Label.new()
	_meta.add_theme_font_override("font", Fonts.code())
	_meta.add_theme_font_size_override("font_size", Typography.body_small - 1)
	_meta.add_theme_color_override("font_color", ThemeColor.body_color.darkened(0.1))
	_meta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header.add_child(_meta)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.selection_enabled = true
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_color_override("default_color", ThemeColor.title_color)
	_body.add_theme_font_override("normal_font", Fonts.regular())
	_body.add_theme_font_override("bold_font", Fonts.bold())
	_body.add_theme_font_override("italics_font", Fonts.regular())
	_body.add_theme_font_override("bold_italics_font", Fonts.bold())
	_body.add_theme_font_override("mono_font", Fonts.code())
	_body.add_theme_font_size_override("normal_font_size", Typography.body_large)
	_body.add_theme_font_size_override("bold_font_size", Typography.body_large)
	_body.add_theme_font_size_override("mono_font_size", Typography.body_large - 1)
	_body.add_theme_color_override("selection_color", ThemeColor.selection_color)
	_body.add_theme_color_override("font_selected_color", ThemeColor.title_color)
	column.add_child(_body)

	_expand_button = Button.new()
	_expand_button.flat = true
	_expand_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_expand_button.add_theme_font_override("font", Fonts.code())
	_expand_button.add_theme_font_size_override("font_size", Typography.body_small - 1)
	_expand_button.add_theme_color_override("font_color", ThemeColor.theme_color)
	_expand_button.visible = false
	_expand_button.pressed.connect(on_expand_pressed)
	column.add_child(_expand_button)

	var background := StyleBoxFlat.new()
	background.bg_color = ThemeColor.card_surface
	background.set_corner_radius_all(10)
	background.set_content_margin_all(0)
	background.border_color = Colors.DARK_OUTLINE_VARIANT
	background.set_border_width_all(0)
	add_theme_stylebox_override("panel", background)


## Applies the entry into the widgets without touching the transcript model.
func refresh() -> void:
	if entry == null:
		return
	dirty = false
	var is_user := entry.kind == ChatEntry.KIND_USER
	var accent := accent_for_kind(entry.kind)
	_badge.text = badge_for_kind(entry.kind)
	_badge.add_theme_color_override("font_color", accent)
	_title.text = header_text()
	_title.add_theme_color_override("font_color", ThemeColor.title_color if not is_user else accent)
	_meta.text = meta_text()
	_meta.visible = not _meta.text.is_empty()
	apply_body()
	apply_background(is_user, accent)


func header_text() -> String:
	if entry.kind == ChatEntry.KIND_USER:
		return "You"
	var summary := str(entry.details.get("summary", StringUtils.EMPTY))
	if not summary.is_empty():
		return "%s  %s" % [entry.title, summary]
	return entry.title


func meta_text() -> String:
	if entry.running:
		return "running"
	if entry.is_error:
		return "failed"
	if entry.kind == ChatEntry.KIND_TOOL or entry.kind == ChatEntry.KIND_FILE_TOOL or entry.kind == ChatEntry.KIND_EXPLORER_TOOL or entry.kind == ChatEntry.KIND_WEB_TOOL:
		var lines := entry.body.count("\n") + 1
		return "" if entry.body.is_empty() else "%d lines" % lines
	return StringUtils.EMPTY


func apply_body() -> void:
	var text := entry.body
	if text.is_empty():
		_body.visible = false
		_expand_button.visible = false
		return
	_body.visible = true
	var diff := str(entry.details.get("diff", StringUtils.EMPTY))
	if not diff.is_empty():
		_body.text = diff_bbcode(diff)
		update_expand_button(diff.count("\n") + 1)
		return
	_body.add_theme_color_override("default_color", ThemeColor.body_color if entry.kind == ChatEntry.KIND_THINKING else ThemeColor.title_color)
	var is_markdown := entry.kind == ChatEntry.KIND_AGENT or entry.kind == ChatEntry.KIND_COMPACTION or entry.kind == ChatEntry.KIND_SYSTEM
	if is_markdown:
		_body.add_theme_font_override("normal_font", Fonts.regular())
		_body.text = MarkdownParser.to_bbcode(clamp_text(text, is_markdown)).bbcode
	else:
		_body.add_theme_font_override("normal_font", Fonts.code())
		_body.text = escape_bbcode(clamp_text(text, is_markdown))
	update_expand_button(text.count("\n") + 1)


func clamp_text(text: String, is_markdown: bool) -> String:
	if expanded:
		return text
	var limit := STREAMING_COLLAPSED_LINES if is_markdown else COLLAPSED_LINES
	var lines := text.split("\n")
	if lines.size() <= limit:
		return text
	return "\n".join(lines.slice(0, limit))


func update_expand_button(total_lines: int) -> void:
	var limit := STREAMING_COLLAPSED_LINES if entry.kind == ChatEntry.KIND_AGENT else COLLAPSED_LINES
	if total_lines <= limit:
		_expand_button.visible = false
		return
	_expand_button.visible = true
	_expand_button.text = "collapse" if expanded else "%d more lines" % (total_lines - limit)


func apply_background(is_user: bool, accent: Color) -> void:
	var background := get_theme_stylebox("panel") as StyleBoxFlat
	if background == null:
		return
	if is_user:
		background.bg_color = ThemeColor.mix_with_theme_color(ThemeColor.card_surface, 0.18)
	elif entry.kind == ChatEntry.KIND_THINKING or entry.kind == ChatEntry.KIND_SYSTEM:
		background.bg_color = ThemeColor.inset_surface
	else:
		background.bg_color = ThemeColor.card_surface
	background.set_border_width_all(1 if entry.is_error else 0)
	background.border_width_left = 3
	background.border_color = accent
	add_theme_stylebox_override("panel", background)


func on_header_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	on_expand_pressed()


func on_expand_pressed() -> void:
	expanded = not expanded
	apply_body()
	expand_toggled.emit()


static func accent_for_kind(kind: String) -> Color:
	match kind:
		ChatEntry.KIND_USER:
			return ThemeColor.theme_color
		ChatEntry.KIND_ERROR:
			return Color("#ff8f8f")
		ChatEntry.KIND_THINKING:
			return Color("#b49bff")
		ChatEntry.KIND_TOOL, ChatEntry.KIND_FILE_TOOL, ChatEntry.KIND_EXPLORER_TOOL, ChatEntry.KIND_WEB_TOOL:
			return Color("#7fd4ff")
		ChatEntry.KIND_COMPACTION:
			return Color("#ffd479")
		_:
			return ThemeColor.title_color


static func badge_for_kind(kind: String) -> String:
	match kind:
		ChatEntry.KIND_USER:
			return ">"
		ChatEntry.KIND_AGENT:
			return "AI"
		ChatEntry.KIND_THINKING:
			return "?"
		ChatEntry.KIND_TOOL, ChatEntry.KIND_FILE_TOOL, ChatEntry.KIND_EXPLORER_TOOL, ChatEntry.KIND_WEB_TOOL:
			return "#"
		ChatEntry.KIND_ERROR:
			return "!"
		ChatEntry.KIND_COMPACTION:
			return "%"
		_:
			return "*"


static func escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")


## Renders a unified diff with per-line coloring; context lines stay subdued.
static func diff_bbcode(diff: String) -> String:
	var output := PackedStringArray()
	for line in diff.split("\n"):
		var escaped := escape_bbcode(line)
		if line.begins_with("+"):
			output.append("[color=%s]%s[/color]" % [COLOR_ADDED.to_html(false), escaped])
		elif line.begins_with("-"):
			output.append("[color=%s]%s[/color]" % [COLOR_REMOVED.to_html(false), escaped])
		elif line.begins_with("@"):
			output.append("[color=%s]%s[/color]" % [ThemeColor.theme_color.to_html(false), escaped])
		else:
			output.append("[color=%s]%s[/color]" % [COLOR_CONTEXT.to_html(false), escaped])
	return "\n".join(output)
