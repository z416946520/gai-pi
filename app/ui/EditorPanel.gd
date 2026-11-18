class_name EditorPanel
extends PanelContainer

## Workspace browser: file tree on the left, read-only preview on the right.
##
## Deliberately read-only: edits belong to pi, and the shell should not race it. Markdown,
## images, and plain text are covered; binary files get a size notice instead of garbage.

signal reference_requested(path: String)
signal closed

const EXCLUDED_DIRS := [".git", ".godot", ".dependency", ".verify", "node_modules", "__pycache__"]
const EXCLUDED_EXTS := ["import", "uid", "tmp", "log"]
const MAX_PREVIEW_BYTES := 2 * 1024 * 1024
## A runaway tree would stall the frame; stop adding rows past this.
const MAX_TREE_ITEMS := 4000
const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp", "bmp", "svg", "gif"]
const MARKDOWN_EXTS := ["md", "markdown"]

var workspace: String = StringUtils.EMPTY

var _tree: Tree = null
var _title: Label = null
var _preview_host: Control = null
var _preview_scroll: ScrollContainer = null
var _reference_button: Button = null
var _current_path: String = StringUtils.EMPTY
var _tabs: TabBar = null
var _open_files: Array[String] = []
## Set while the tab bar is being synced, so programmatic changes do not re-enter.
var _syncing_tabs: bool = false
var _items_added: int = 0


## Path currently shown in the preview, or "" when nothing is open.
func current_file() -> String:
	return _current_path


func is_built() -> bool:
	return _tree != null


func set_workspace(workspace_path: String) -> void:
	workspace = workspace_path
	if _tree != null:
		close_all_tabs()
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


func reload() -> void:
	if _tree == null:
		return
	_tree.clear()
	_items_added = 0
	var root := _tree.create_item()
	root.set_text(0, workspace.get_file() if not workspace.is_empty() else "workspace")
	root.set_metadata(0, workspace)
	add_directory(root, workspace)
	root.set_collapsed(false)
	_title.text = workspace


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", Margin.ma_2)
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Margin.ma_2)
	column.add_child(header)

	_title = Label.new()
	_title.text = T.t("gai_pi.editor.title")
	_title.size_flags_horizontal = SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.add_theme_font_override("font", Fonts.semibold())
	_title.add_theme_font_size_override("font_size", Typography.body_medium)
	_title.add_theme_color_override("font_color", ThemeColor.title_color)
	header.add_child(_title)

	var refresh := tool_button("⟳", T.t("gai_pi.editor.refresh"))
	refresh.pressed.connect(reload)
	header.add_child(refresh)
	var close := tool_button("✕", T.t("gai_pi.editor.close"))
	close.pressed.connect(func() -> void: closed.emit())
	header.add_child(close)

	var split := HSplitContainer.new()
	split.size_flags_vertical = SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", Margin.ma_2)
	column.add_child(split)

	_tree = Tree.new()
	_tree.custom_minimum_size = Vector2(158, 0)
	_tree.hide_root = false
	_tree.allow_reselect = true
	_tree.add_theme_font_override("font", Fonts.regular())
	_tree.add_theme_font_size_override("font_size", Typography.body_small)
	_tree.add_theme_color_override("font_color", ThemeColor.title_color)
	_tree.add_theme_color_override("font_selected_color", ThemeColor.title_color)
	_tree.add_theme_color_override("font_hovered_color", ThemeColor.theme_color)
	_tree.add_theme_color_override("guide_color", AppTheme.outline())
	var tree_panel := StyleBoxFlat.new()
	tree_panel.bg_color = AppTheme.background()
	tree_panel.set_corner_radius_all(6)
	tree_panel.content_margin_left = Margin.ma_1
	tree_panel.content_margin_right = Margin.ma_1
	tree_panel.content_margin_top = Margin.ma_1
	tree_panel.content_margin_bottom = Margin.ma_1
	_tree.add_theme_stylebox_override("panel", tree_panel)
	_tree.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var tree_selected := StyleBoxFlat.new()
	tree_selected.bg_color = ThemeColor.mix_with_theme_color(AppTheme.control_surface(), 0.45)
	tree_selected.set_corner_radius_all(4)
	_tree.add_theme_stylebox_override("selected", tree_selected)
	_tree.add_theme_stylebox_override("selected_focus", tree_selected)
	_tree.item_selected.connect(on_item_selected)
	_tree.item_activated.connect(on_item_selected)
	split.add_child(_tree)

	var preview_column := VBoxContainer.new()
	preview_column.size_flags_horizontal = SIZE_EXPAND_FILL
	preview_column.add_theme_constant_override("separation", Margin.ma_1)
	split.add_child(preview_column)

	_tabs = TabBar.new()
	_tabs.clip_tabs = true
	_tabs.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	_tabs.add_theme_font_override("font", Fonts.regular())
	_tabs.add_theme_font_size_override("font_size", Typography.body_small)
	_tabs.add_theme_color_override("font_selected_color", ThemeColor.title_color)
	_tabs.add_theme_color_override("font_unselected_color", ThemeColor.body_color)
	_tabs.add_theme_color_override("font_hovered_color", ThemeColor.title_color)
	for state: String in ["tab_selected", "tab_unselected", "tab_hovered"]:
		var tab_style := StyleBoxFlat.new()
		tab_style.bg_color = AppTheme.control_surface() if state != "tab_unselected" else Color(0, 0, 0, 0)
		tab_style.set_corner_radius_all(6)
		tab_style.content_margin_left = Margin.ma_2
		tab_style.content_margin_right = Margin.ma_2
		tab_style.content_margin_top = 2
		tab_style.content_margin_bottom = 2
		_tabs.add_theme_stylebox_override(state, tab_style)
	_tabs.tab_selected.connect(on_tab_selected)
	_tabs.tab_close_pressed.connect(on_tab_close)
	preview_column.add_child(_tabs)

	_preview_scroll = ScrollContainer.new()
	_preview_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_preview_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	_preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_column.add_child(_preview_scroll)

	_preview_host = VBoxContainer.new()
	_preview_host.size_flags_horizontal = SIZE_EXPAND_FILL
	_preview_host.add_theme_constant_override("separation", Margin.ma_1)
	_preview_scroll.add_child(_preview_host)

	_reference_button = Button.new()
	_reference_button.text = T.t("gai_pi.editor.reference_short")
	_reference_button.tooltip_text = T.t("gai_pi.editor.reference")
	_reference_button.visible = false
	_reference_button.add_theme_font_override("font", Fonts.regular())
	_reference_button.add_theme_font_size_override("font_size", Typography.body_small)
	var reference_style := StyleBoxFlat.new()
	reference_style.bg_color = AppTheme.control_surface()
	reference_style.set_corner_radius_all(6)
	reference_style.content_margin_left = Margin.ma_2
	reference_style.content_margin_right = Margin.ma_2
	reference_style.content_margin_top = 2
	reference_style.content_margin_bottom = 2
	_reference_button.add_theme_stylebox_override("normal", reference_style)
	_reference_button.add_theme_stylebox_override("hover", reference_style)
	_reference_button.add_theme_stylebox_override("pressed", reference_style)
	_reference_button.add_theme_color_override("font_color", ThemeColor.title_color)
	_reference_button.pressed.connect(func() -> void:
		if not _current_path.is_empty():
			reference_requested.emit(_current_path)
	)
	preview_column.add_child(_reference_button)


func tool_button(glyph: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = glyph
	button.flat = true
	button.focus_mode = FOCUS_NONE
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(26, 24)
	button.add_theme_font_override("font", Fonts.code())
	button.add_theme_color_override("font_color", ThemeColor.body_color)
	button.add_theme_color_override("font_hover_color", ThemeColor.theme_color)
	return button


# ---------------------------------------------------------------------------
# Tree
# ---------------------------------------------------------------------------

func add_directory(parent: TreeItem, path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	var directories: Array[String] = []
	var files: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name.begins_with(".") and name != ".agents":
			name = dir.get_next()
			continue
		if dir.current_is_dir():
			if not EXCLUDED_DIRS.has(name):
				directories.append(name)
		else:
			if not EXCLUDED_EXTS.has(name.get_extension().to_lower()):
				files.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	directories.sort()
	files.sort()
	for directory in directories:
		if _items_added >= MAX_TREE_ITEMS:
			return
		_items_added += 1
		var item := parent.create_child()
		item.set_text(0, directory + "/")
		item.set_metadata(0, path.path_join(directory))
		item.collapsed = true
		add_directory(item, path.path_join(directory))
	for file in files:
		if _items_added >= MAX_TREE_ITEMS:
			return
		_items_added += 1
		var item := parent.create_child()
		item.set_text(0, file)
		item.set_metadata(0, path.path_join(file))


func on_item_selected() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var path := str(item.get_metadata(0))
	if path.is_empty() or DirAccess.dir_exists_absolute(path):
		return
	show_file(path)


# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------

func show_file(path: String) -> void:
	if path.is_empty():
		return
	if not _open_files.has(path):
		_open_files.append(path)
		_syncing_tabs = true
		_tabs.add_tab(path.get_file())
		_tabs.set_tab_tooltip(_open_files.size() - 1, relative_path(path))
		_syncing_tabs = false
	_syncing_tabs = true
	_tabs.current_tab = _open_files.find(path)
	_syncing_tabs = false
	render_file(path)


func on_tab_selected(index: int) -> void:
	if _syncing_tabs or index < 0 or index >= _open_files.size():
		return
	render_file(_open_files[index])


func on_tab_close(index: int) -> void:
	if index < 0 or index >= _open_files.size():
		return
	_open_files.remove_at(index)
	_syncing_tabs = true
	_tabs.remove_tab(index)
	_syncing_tabs = false
	if _open_files.is_empty():
		_current_path = StringUtils.EMPTY
		_reference_button.visible = false
		_clear_preview()
		return
	var next := clampi(index, 0, _open_files.size() - 1)
	_syncing_tabs = true
	_tabs.current_tab = next
	_syncing_tabs = false
	render_file(_open_files[next])


func close_all_tabs() -> void:
	_open_files.clear()
	if _tabs != null:
		_syncing_tabs = true
		_tabs.clear_tabs()
		_syncing_tabs = false
	_current_path = StringUtils.EMPTY
	if _reference_button != null:
		_reference_button.visible = false
	if _preview_host != null:
		_clear_preview()


## Renders one file into the preview area; tabs decide which file that is.
func render_file(path: String) -> void:
	_current_path = path
	_reference_button.visible = true
	_clear_preview()
	var extension := path.get_extension().to_lower()
	if IMAGE_EXTS.has(extension):
		_show_image(path)
		return
	if FileAccess.get_file_as_string(path).length() > MAX_PREVIEW_BYTES:
		_add_notice(T.t("gai_pi.editor.too_large"))
		return
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and not FileAccess.file_exists(path):
		_add_notice(T.t("gai_pi.editor.unreadable"))
		return
	if MARKDOWN_EXTS.has(extension):
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.selection_enabled = true
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		label.add_theme_color_override("default_color", ThemeColor.title_color)
		label.add_theme_font_override("normal_font", Fonts.regular())
		label.add_theme_font_override("mono_font", Fonts.code())
		label.add_theme_font_size_override("normal_font_size", Typography.body_medium)
		label.add_theme_font_size_override("mono_font_size", Typography.body_small - 1)
		label.text = MarkdownParser.to_bbcode(strip_html(text)).bbcode
		_preview_host.add_child(label)
		return
	var code := CodeEdit.new()
	code.text = text
	code.editable = false
	code.size_flags_horizontal = SIZE_EXPAND_FILL
	code.custom_minimum_size = Vector2(0, 200)
	code.scroll_fit_content_height = true
	code.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code.add_theme_font_override("font", Fonts.code())
	code.add_theme_font_size_override("font_size", Typography.body_small)
	code.add_theme_color_override("font_color", ThemeColor.title_color)
	code.add_theme_color_override("font_readonly_color", ThemeColor.title_color)
	code.add_theme_color_override("caret_color", ThemeColor.theme_color)
	code.add_theme_color_override("line_number_color", ThemeColor.body_color)
	code.add_theme_color_override("selection_color", ThemeColor.selection_color)
	var code_style := StyleBoxFlat.new()
	code_style.bg_color = AppTheme.background()
	code_style.set_corner_radius_all(6)
	code_style.content_margin_left = Margin.ma_2
	code_style.content_margin_right = Margin.ma_2
	code_style.content_margin_top = Margin.ma_1
	code_style.content_margin_bottom = Margin.ma_1
	code.add_theme_stylebox_override("normal", code_style)
	code.add_theme_stylebox_override("focus", code_style)
	code.add_theme_stylebox_override("read_only", code_style)
	code.syntax_highlighter = CommonHighlighter.create(path)
	_preview_host.add_child(code)


## README badges and centered blocks are HTML; the parser renders tags literally, so the
## preview drops them and keeps the text between them.
static func strip_html(markdown: String) -> String:
	var pattern := RegEx.new()
	pattern.compile("<[^>]+>")
	return pattern.sub(markdown, StringUtils.EMPTY, true)


func _show_image(path: String) -> void:
	var image := Image.new()
	var error := OK
	if path.get_extension().to_lower() == "svg":
		error = image.load_svg_from_string(FileAccess.get_file_as_string(path), 1.0)
	else:
		error = image.load(path)
	if error != OK:
		_add_notice(T.t("gai_pi.editor.unreadable"))
		return
	var texture := ImageTexture.create_from_image(image)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(0, 360)
	rect.size_flags_horizontal = SIZE_EXPAND_FILL
	_preview_host.add_child(rect)


func _add_notice(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", Fonts.regular())
	label.add_theme_font_size_override("font_size", Typography.body_small)
	label.add_theme_color_override("font_color", ThemeColor.body_color)
	_preview_host.add_child(label)


func _clear_preview() -> void:
	for child in _preview_host.get_children():
		child.queue_free()


## Re-applies translated labels after a language switch.
func apply_locale() -> void:
	if _reference_button != null:
		_reference_button.text = T.t("gai_pi.editor.reference_short")
		_reference_button.tooltip_text = T.t("gai_pi.editor.reference")
	if _title != null and workspace.is_empty():
		_title.text = T.t("gai_pi.editor.title")


func relative_path(path: String) -> String:
	if workspace.is_empty():
		return path
	return path.replace(workspace, StringUtils.EMPTY).trim_prefix("/").trim_prefix("\\")
