class_name MemoryPanel
extends PanelContainer

## Project memory files: the Markdown pi reads as context, editable in place.
##
## pi loads AGENTS.md and skills at session start, so edits here apply to the next session;
## the panel says that instead of pretending a live session re-reads them.

signal saved(path: String)
signal status(message: String)

const ROOT_FILES := ["AGENTS.md", "MEMORY.md", "SYSTEM.md", "SKILLS.md"]
const MEMORY_DIR := ".memory"

var workspace: String = StringUtils.EMPTY

var _list: VBoxContainer = null
var _title: Label = null
var _edit: CodeEdit = null
var _save_button: Button = null
var _current_path: String = StringUtils.EMPTY
var _dirty: bool = false


func is_built() -> bool:
	return _list != null


func set_workspace(workspace_path: String) -> void:
	workspace = workspace_path
	if _list != null:
		reload()


func setup(workspace_path: String) -> void:
	workspace = workspace_path
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.chrome_surface()
	style.border_color = AppTheme.outline()
	style.border_width_left = 1
	style.content_margin_left = Margin.ma_2
	style.content_margin_right = Margin.ma_2
	style.content_margin_top = Margin.ma_2
	style.content_margin_bottom = Margin.ma_2
	add_theme_stylebox_override("panel", style)
	_build()
	reload()


## Files offered by the panel: the workspace root files that exist plus `.memory/*.md`.
static func candidate_files(workspace_path: String) -> Array[String]:
	var files: Array[String] = []
	for name in ROOT_FILES:
		var path := workspace_path.path_join(name)
		if FileAccess.file_exists(path):
			files.append(path)
	var memory_root := workspace_path.path_join(MEMORY_DIR)
	var dir := DirAccess.open(memory_root)
	if dir == null:
		return files
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir() and entry.ends_with(".md"):
			files.append(memory_root.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	return files


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", Margin.ma_2)
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Margin.ma_2)
	column.add_child(header)

	_title = Label.new()
	_title.size_flags_horizontal = SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.add_theme_font_override("font", Fonts.semibold())
	_title.add_theme_font_size_override("font_size", Typography.body_medium)
	_title.add_theme_color_override("font_color", ThemeColor.title_color)
	header.add_child(_title)

	_save_button = Button.new()
	_save_button.text = T.t("gai_pi.memory.save")
	_save_button.focus_mode = FOCUS_NONE
	_save_button.add_theme_font_override("font", Fonts.regular())
	_save_button.add_theme_font_size_override("font_size", Typography.body_small)
	_save_button.pressed.connect(save_current)
	header.add_child(_save_button)

	var split := HSplitContainer.new()
	split.size_flags_vertical = SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", Margin.ma_2)
	column.add_child(split)

	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(180, 0)
	_list.add_theme_constant_override("separation", 2)
	split.add_child(_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	split.add_child(right)

	var hint := Label.new()
	hint.text = T.t("gai_pi.memory.hint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_override("font", Fonts.code())
	hint.add_theme_font_size_override("font_size", Typography.body_small - 1)
	hint.add_theme_color_override("font_color", ThemeColor.body_color.darkened(0.1))
	right.add_child(hint)

	_edit = CodeEdit.new()
	_edit.size_flags_vertical = SIZE_EXPAND_FILL
	_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_edit.add_theme_font_override("font", Fonts.code())
	_edit.add_theme_font_size_override("font_size", Typography.body_small)
	_edit.add_theme_color_override("font_color", ThemeColor.title_color)
	_edit.add_theme_color_override("caret_color", ThemeColor.theme_color)
	var edit_style := StyleBoxFlat.new()
	edit_style.bg_color = AppTheme.background()
	edit_style.set_corner_radius_all(6)
	edit_style.content_margin_left = Margin.ma_2
	edit_style.content_margin_right = Margin.ma_2
	for state: String in ["normal", "focus", "read_only"]:
		_edit.add_theme_stylebox_override(state, edit_style)
	_edit.text_changed.connect(func() -> void: _dirty = true)
	right.add_child(_edit)


func reload() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var files := candidate_files(workspace)
	if files.is_empty():
		var empty := Label.new()
		empty.text = T.t("gai_pi.memory.empty")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_override("font", Fonts.code())
		empty.add_theme_font_size_override("font_size", Typography.body_small)
		empty.add_theme_color_override("font_color", ThemeColor.body_color.darkened(0.2))
		_list.add_child(empty)
		_edit.text = StringUtils.EMPTY
		_edit.editable = false
		return
	for path in files:
		var button := Button.new()
		button.text = relative_name(path)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.flat = true
		button.custom_minimum_size = Vector2(0, 26)
		button.add_theme_font_override("font", Fonts.regular())
		button.add_theme_font_size_override("font_size", Typography.body_small)
		button.add_theme_color_override("font_color", ThemeColor.title_color)
		button.pressed.connect(func() -> void: open_file(path))
		_list.add_child(button)
	open_file(files[0])


func relative_name(path: String) -> String:
	if path.contains("/.memory/"):
		return MEMORY_DIR + "/" + path.get_file()
	return path.get_file()


func open_file(path: String) -> void:
	_current_path = path
	_title.text = relative_name(path)
	var file := FileAccess.open(path, FileAccess.READ)
	_edit.editable = true
	_edit.text = file.get_as_text() if file != null else StringUtils.EMPTY
	if file != null:
		file.close()
	_dirty = false


func save_current() -> void:
	if _current_path.is_empty() or not _edit.editable:
		return
	var file := FileAccess.open(_current_path, FileAccess.WRITE)
	if file == null:
		status.emit(T.t("gai_pi.memory.save_failed"))
		return
	file.store_string(_edit.text)
	file.close()
	_dirty = false
	saved.emit(_current_path)
	status.emit(T.t("gai_pi.memory.saved", [relative_name(_current_path)]))


func apply_locale() -> void:
	if _title != null and _current_path.is_empty():
		_title.text = T.t("gai_pi.memory.title")
	if _save_button != null:
		_save_button.text = T.t("gai_pi.memory.save")
