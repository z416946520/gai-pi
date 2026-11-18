extends Control

## gai-pi desktop shell: pi runs as an RPC child process, this scene is the whole UI.

const SIDEBAR_WIDTH := 300
const SIDEBAR_MIN_WIDTH := 240
const TOP_BAR_HEIGHT := 46
const COMPOSER_HEIGHT := 112
## Taller composer while image chips are attached; the transcript hides behind it.
const COMPOSER_HEIGHT_ATTACHED := 150
const FLUSH_INTERVAL_MS := 80
## Millisecond budget for replaying a session per frame; 400+ entries must not stall a frame.
const BUILD_BUDGET_MS := 8
## Bubbles re-rendered per flush tick, so a language switch cannot freeze for a second.
const FLUSH_BATCH := 24
## Entries built when a session opens; earlier history loads on demand so switching is instant.
const TRANSCRIPT_WINDOW := 50
const TRANSCRIPT_WINDOW_STEP := 60

const THINKING_LEVELS := ["off", "minimal", "low", "medium", "high", "xhigh", "max"]
## Longest value the usage chip shows before it is replaced by the context label.
const USAGE_KEY := "gai_pi.topbar.usage"


var workspace_host: PiWorkspace = null
var session: PiSession = null

var _bubbles: Dictionary = {}
var _dirty_bubbles: Array[ChatBubble] = []
var _last_flush: int = 0
var _follow_tail: bool = true
var _scroll_requested_at: int = 0
var _scroll_attempts: int = 0
var _programmatic_scroll: bool = false
var _last_scroll_max: float = 0.0
## While a rebuild or a stream is settling, scrollbar values change without user intent.
var _follow_until: int = 0

var _top_bar: PanelContainer = null
var _workspace_button: Button = null
var _usage_label: Label = null
var _model_button: Button = null
var _thinking_button: Button = null
var _visuals_picker: OptionButton = null
var _status_label: Label = null

var _session_list: VBoxContainer = null
var _new_session_button: Button = null
var _sidebar_status: Label = null

var _scroll: ScrollContainer = null
var _entries_box: VBoxContainer = null
var _visual_stage: VisualStage = null
var _composer: PanelContainer = null
var _input_field: TextEdit = null
var _send_button: Button = null
var _stop_button: Button = null
var _hint_label: Label = null
var _workspace_dialog: FileDialog = null
var _language_button: Button = null
var _editor_button: Button = null
var _theme_button: Button = null
var _search_button: Button = null
var _search_panel: PanelContainer = null
var _search_field: LineEdit = null
var _search_results: VBoxContainer = null
var _search_status: Label = null
var _search_env_at: int = 0
var _search_env_query: String = StringUtils.EMPTY
## Lowercased bodies, keyed by entry; cleared whenever the transcript is replaced.
var _search_lower: Dictionary = {}
var _editor: EditorPanel = null
var _attachments: Array[Dictionary] = []
var _attachment_row: HBoxContainer = null
var _runtime_strip: PanelContainer = null
var _strip_row: HBoxContainer = null
var _widget_label: Label = null
var _strip_status_label: Label = null
var _extension_status: Dictionary[String, String] = {}
var _extension_widgets: Dictionary[String, PackedStringArray] = {}
var _last_usage: OpenAiUsage = null
## Rebuilding the picker must not look like a user selection (some builds emit item_selected).
var _suppress_visual_signal: bool = false
var _sidebar_failed: bool = false
var _build_queue: Array[ChatEntry] = []
var _build_generation: int = 0
var _build_started_at: int = 0
var _sessions_signature: String = StringUtils.EMPTY
var _window_start: int = 0
var _load_earlier_button: Button = null
## One pi process per session so several sessions can run at the same time.
var _workspace_path: String = StringUtils.EMPTY
var _hosts: Dictionary[String, PiWorkspace] = {}
var _bound_hosts: Dictionary[String, bool] = {}
var _host_lru: Dictionary[String, int] = {}
var _dialog_host_by_id: Dictionary[String, String] = {}
var _active_key: String = StringUtils.EMPTY
var _local_id_seq: int = 0
var _new_session_seq: int = 0
var _boot_hooks_done: bool = false
var _pending_editor_diff: bool = false
var _session_search: LineEdit = null
var _prompt: ModalPrompt = null
var _pinned_paths: Array[String] = []
var _pending_delete: String = StringUtils.EMPTY
var _checkpoints: CheckpointManager = null
var _turn_start_commit: String = StringUtils.EMPTY
var _turn_entry: ChatEntry = null
var _turn_index: int = 0
var _switch_theme_at: int = 0
var _preview_visual_at: int = 0
var _preview_visual_type: int = -1
var _switch_locale_at: int = 0
var _switch_locale_code: String = StringUtils.EMPTY
var _empty_hint: VBoxContainer = null
var _dialogs: PiDialogLayer = null

## Verification hook: GAI_PI_SCREENSHOT=<png path> renders one frame, saves it, and quits.
var _screenshot_target: String = StringUtils.EMPTY
var _screenshot_at: int = 0
var _started_at: int = 0


func _ready() -> void:
	_started_at = Time.get_ticks_msec()
	_init_i18n()
	apply_locale_override()
	ThemeColor.load_theme()
	# GAI_PI_THEME forces the palette before the first build.
	var theme_env := OS.get_environment("GAI_PI_THEME").strip_edges()
	if theme_env == "light":
		ThemeColor.set_theme(ThemeColor.ThemeEnum.LIGHT)
	elif theme_env == "dark":
		ThemeColor.set_theme(ThemeColor.ThemeEnum.DARK)
	build_ui()
	gdf.events.locale_changed.connect(apply_locale)
	gdf.events.theme_changed.connect(on_theme_changed)
	PiEvents.events.agent_end.connect(on_agent_end_checkpoint)
	open_workspace(_initial_workspace())
	var visual_override := OS.get_environment("GAI_PI_VISUAL").strip_edges()
	if not visual_override.is_empty():
		AppSetting.set_int(AppSetting.KEY_VISUAL, visual_override.to_int())
		_visuals_picker.selected = clampi(visual_override.to_int(), 0, VisualStage.type_names().size() - 1)
	if OS.get_environment("GAI_PI_EDITOR") == "1":
		toggle_editor(true)
		var editor_file := OS.get_environment("GAI_PI_EDITOR_FILE").strip_edges()
		# Multiple files are separated by "|" so tab switching can be exercised.
		for file in editor_file.split("|", false):
			_editor.show_file(file)
		if OS.get_environment("GAI_PI_EDITOR_DIFF") == "1":
			# The checkpoint lookup needs a live session, which arrives with the host.
			_pending_editor_diff = true
	get_window().files_dropped.connect(on_files_dropped)
	get_window().title = "gai-pi"
	_input_field.grab_focus()
	_prompt = ModalPrompt.new()
	add_child(_prompt)
	load_pins()
	apply_locale()
	var initial_image := OS.get_environment("GAI_PI_ATTACH_IMAGE").strip_edges()
	if not initial_image.is_empty():
		var image := Image.new()
		if image.load(initial_image) == OK:
			attach_image(image, initial_image.get_file())
	var preview_visual := OS.get_environment("GAI_PI_PREVIEW_VISUAL").strip_edges()
	if not preview_visual.is_empty():
		_preview_visual_type = preview_visual.to_int()
		_preview_visual_at = _started_at + 2500
	var switch_env := OS.get_environment("GAI_PI_SWITCH_LOCALE").strip_edges()
	if not switch_env.is_empty():
		_switch_locale_code = switch_env
		_switch_locale_at = _started_at + 2500
	var search_env := OS.get_environment("GAI_PI_SEARCH").strip_edges()
	if not search_env.is_empty():
		_search_env_at = _started_at + 6000
		_search_env_query = search_env
	var switch_theme := OS.get_environment("GAI_PI_SWITCH_THEME").strip_edges()
	if not switch_theme.is_empty():
		var delay := 2500
		if switch_theme.is_valid_int():
			delay = int(switch_theme) * 1000
		_switch_theme_at = _started_at + delay
	_screenshot_target = OS.get_environment("GAI_PI_SCREENSHOT").strip_edges()
	_screenshot_at = _started_at + int(OS.get_environment("GAI_PI_SCREENSHOT_DELAY").to_int() if not OS.get_environment("GAI_PI_SCREENSHOT_DELAY").is_empty() else 6000)


func _process(_delta: float) -> void:
	if workspace_host != null:
		workspace_host.poll()
		_poll_errors()
	AsyncProcess.poll_all()
	var now := Time.get_ticks_msec()
	if now - _last_flush >= FLUSH_INTERVAL_MS and not _dirty_bubbles.is_empty():
		_last_flush = now
		flush_bubbles()
	if not _build_queue.is_empty():
		build_next_batch()
	watch_scroll_extent()
	if _search_env_at > 0 and now >= _search_env_at:
		_search_env_at = 0
		toggle_search(true)
		_search_field.text = _search_env_query
		run_search(_search_env_query)
		if OS.get_environment("GAI_PI_SEARCH_JUMP") == "1" and session != null:
			var matches := ChatSearch.find_matches(session.entries, _search_env_query)
			if not matches.is_empty():
				reveal_entry(matches[0]["entry"])
	if _switch_theme_at > 0 and now >= _switch_theme_at:
		_switch_theme_at = 0
		ThemeColor.toggle_theme()
	if _preview_visual_at > 0 and now >= _preview_visual_at:
		_preview_visual_at = 0
		if _visual_stage != null:
			_visuals_picker.selected = clampi(_preview_visual_type, 0, VisualStage.type_names().size() - 1)
			_visual_stage.apply_visual_type(_preview_visual_type)
	if _switch_locale_at > 0 and now >= _switch_locale_at:
		_switch_locale_at = 0
		switch_language(_switch_locale_code)
	if _scroll_requested_at > 0 and now - _scroll_requested_at >= 50:
		_scroll_requested_at = 0 if _scroll_attempts <= 1 else now
		_scroll_attempts -= 1
		apply_scroll_bottom()
	if not _screenshot_target.is_empty() and now >= _screenshot_at:
		_capture_screenshot()


func _capture_screenshot() -> void:
	var target := _screenshot_target
	_screenshot_target = StringUtils.EMPTY
	# Two frames are enough for layout and drawing to settle; frame_post_draw can stall when
	# the window is occluded, which would hang the verification run.
	await get_tree().process_frame
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(target)
	print("[gai-pi] screenshot ", target, " error=", error)
	await get_tree().process_frame
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown_hosts()


func _exit_tree() -> void:
	AsyncProcess.stop_all()
	shutdown_hosts()


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func build_ui() -> void:
	var background := ColorRect.new()
	background.color = AppTheme.background() 
	background.set_anchors_preset(PRESET_FULL_RECT)
	background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(background)

	var root := VBoxContainer.new()
	root.set_anchors_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(build_top_bar())

	var body := HSplitContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	body.add_child(build_sidebar())
	body.add_child(build_chat_area())
	_editor = EditorPanel.new()
	_editor.custom_minimum_size = Vector2(620, 0)
	_editor.visible = false
	_editor.closed.connect(func() -> void: toggle_editor(false))
	_editor.reference_requested.connect(on_editor_reference)
	_editor.diff_requested.connect(on_editor_diff)
	body.add_child(_editor)


func build_top_bar() -> Control:
	_top_bar = PanelContainer.new()
	_top_bar.custom_minimum_size = Vector2(0, TOP_BAR_HEIGHT)
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.deep_surface() 
	style.border_color = AppTheme.outline() 
	style.border_width_bottom = 1
	style.content_margin_left = Margin.ma_4
	style.content_margin_right = Margin.ma_4
	_top_bar.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Margin.ma_3)
	_top_bar.add_child(row)

	var logo := Label.new()
	logo.text = "gai-pi"
	logo.add_theme_font_override("font", Fonts.bold())
	logo.add_theme_font_size_override("font_size", Typography.title_medium)
	logo.add_theme_color_override("font_color", ThemeColor.theme_color)
	logo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(logo)

	_workspace_button = make_flat_button("", "")
	_workspace_button.pressed.connect(on_workspace_pressed)
	row.add_child(_workspace_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(spacer)

	_usage_label = Label.new()
	_usage_label.add_theme_font_override("font", Fonts.code())
	_usage_label.add_theme_font_size_override("font_size", Typography.body_small)
	_usage_label.add_theme_color_override("font_color", ThemeColor.body_color)
	_usage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_usage_label)

	_model_button = make_flat_button("", "")
	_model_button.pressed.connect(on_model_pressed)
	row.add_child(_model_button)

	_thinking_button = make_flat_button("", "")
	_thinking_button.pressed.connect(on_thinking_pressed)
	row.add_child(_thinking_button)

	_visuals_picker = OptionButton.new()
	_visuals_picker.flat = true
	_visuals_picker.focus_mode = FOCUS_NONE
	_visuals_picker.add_theme_font_override("font", Fonts.regular())
	_visuals_picker.add_theme_font_size_override("font_size", Typography.body_small)
	_visuals_picker.add_theme_color_override("font_color", ThemeColor.body_color)
	_visuals_picker.add_theme_color_override("font_hover_color", ThemeColor.title_color)
	_visuals_picker.add_theme_color_override("font_focus_color", ThemeColor.title_color)

	_suppress_visual_signal = true
	for index in VisualStage.type_names().size():
		_visuals_picker.add_item(VisualStage.localized_name(index), index)
	_visuals_picker.selected = clampi(AppSetting.get_int(AppSetting.KEY_VISUAL, 0), 0, VisualStage.type_names().size() - 1)
	_visuals_picker.item_selected.connect(on_visual_selected)
	_suppress_visual_signal = false
	row.add_child(_visuals_picker)

	_editor_button = make_flat_button("", "")
	_editor_button.pressed.connect(func() -> void: toggle_editor(not _editor.visible))
	row.add_child(_editor_button)

	_search_button = make_flat_button("⌕", "")
	_search_button.pressed.connect(func() -> void: toggle_search(not (_search_panel != null and _search_panel.visible)))
	row.add_child(_search_button)

	_theme_button = make_flat_button("", "")
	_theme_button.pressed.connect(func() -> void: ThemeColor.toggle_theme())
	row.add_child(_theme_button)

	_language_button = make_flat_button("", "")
	_language_button.pressed.connect(on_language_pressed)
	row.add_child(_language_button)

	_dialogs = PiDialogLayer.new()
	_dialogs.answered.connect(on_dialog_answered)
	add_child(_dialogs)

	_status_label = Label.new()
	_status_label.clip_text = true
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.custom_minimum_size = Vector2(0, 0)
	_status_label.size_flags_horizontal = SIZE_SHRINK_END
	_status_label.add_theme_font_override("font", Fonts.code())
	_status_label.add_theme_font_size_override("font_size", Typography.body_small - 1)
	_status_label.add_theme_color_override("font_color", AppTheme.ink(Color("#ff8f8f")))
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.visible = false
	row.add_child(_status_label)

	_workspace_dialog = FileDialog.new()
	_workspace_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_workspace_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_workspace_dialog.title = T.t("gai_pi.topbar.switch_workspace")
	_workspace_dialog.use_native_dialog = true
	_workspace_dialog.dir_selected.connect(on_workspace_selected)
	add_child(_workspace_dialog)
	return _top_bar


func build_sidebar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SIDEBAR_MIN_WIDTH, 0)
	panel.size_flags_horizontal = SIZE_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.chrome_surface() 
	style.border_color = AppTheme.outline() 
	style.border_width_right = 1
	style.content_margin_left = Margin.ma_3
	style.content_margin_right = Margin.ma_3
	style.content_margin_top = Margin.ma_3
	style.content_margin_bottom = Margin.ma_3
	panel.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", Margin.ma_2)
	panel.add_child(column)

	_new_session_button = Button.new()
	_new_session_button.text = T.t("gai_pi.sidebar.new")
	if _session_search != null:
		_session_search.placeholder_text = T.t("gai_pi.session.search_placeholder")
	_new_session_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_new_session_button.add_theme_font_override("font", Fonts.medium())
	_new_session_button.add_theme_font_size_override("font_size", Typography.body_medium)
	_new_session_button.custom_minimum_size = Vector2(0, 36)
	_new_session_button.pressed.connect(on_new_session_pressed)
	column.add_child(_new_session_button)

	_session_search = LineEdit.new()
	_session_search.custom_minimum_size = Vector2(0, 30)
	_session_search.clear_button_enabled = true
	_session_search.add_theme_font_override("font", Fonts.regular())
	_session_search.add_theme_font_size_override("font_size", Typography.body_small)
	style_sidebar_field(_session_search)
	_session_search.text_changed.connect(func(_text: String) -> void: refresh_sessions(true))
	column.add_child(_session_search)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_session_list = VBoxContainer.new()
	_session_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_session_list.add_theme_constant_override("separation", Margin.ma_1)
	scroll.add_child(_session_list)

	_sidebar_status = Label.new()
	_sidebar_status.add_theme_font_override("font", Fonts.code())
	_sidebar_status.add_theme_font_size_override("font_size", Typography.body_small - 1)
	_sidebar_status.add_theme_color_override("font_color", ThemeColor.body_color.darkened(0.2))
	_sidebar_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_sidebar_status)
	return panel


func build_chat_area() -> Control:
	var area := Control.new()
	area.size_flags_horizontal = SIZE_EXPAND_FILL
	area.size_flags_vertical = SIZE_EXPAND_FILL

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(PRESET_FULL_RECT)
	_scroll.offset_bottom = -COMPOSER_HEIGHT
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	area.add_child(_scroll)
	_scroll.get_v_scroll_bar().value_changed.connect(on_scroll_changed)

	var margin_container := MarginContainer.new()
	margin_container.size_flags_horizontal = SIZE_EXPAND_FILL
	margin_container.add_theme_constant_override("margin_left", Margin.ma_8)
	margin_container.add_theme_constant_override("margin_right", Margin.ma_8)
	margin_container.add_theme_constant_override("margin_top", Margin.ma_5)
	margin_container.add_theme_constant_override("margin_bottom", Margin.ma_5)
	_scroll.add_child(margin_container)

	_entries_box = VBoxContainer.new()
	_entries_box.size_flags_horizontal = SIZE_EXPAND_FILL
	_entries_box.add_theme_constant_override("separation", Margin.ma_2)
	margin_container.add_child(_entries_box)

	_load_earlier_button = Button.new()
	_load_earlier_button.anchor_left = 0.5
	_load_earlier_button.anchor_right = 0.5
	_load_earlier_button.offset_left = 0
	_load_earlier_button.offset_right = 0
	_load_earlier_button.offset_top = Margin.ma_3
	_load_earlier_button.offset_bottom = Margin.ma_3 + 30
	_load_earlier_button.grow_horizontal = GROW_DIRECTION_BOTH
	_load_earlier_button.focus_mode = FOCUS_NONE
	_load_earlier_button.visible = false
	_load_earlier_button.add_theme_font_override("font", Fonts.regular())
	_load_earlier_button.add_theme_font_size_override("font_size", Typography.body_small)
	_load_earlier_button.add_theme_color_override("font_color", ThemeColor.title_color)
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(AppTheme.control_surface(), 0.92)
	pill.border_color = AppTheme.outline() 
	pill.set_border_width_all(1)
	pill.set_corner_radius_all(15)
	pill.content_margin_left = Margin.ma_3
	pill.content_margin_right = Margin.ma_3
	_load_earlier_button.add_theme_stylebox_override("normal", pill)
	_load_earlier_button.add_theme_stylebox_override("hover", pill)
	_load_earlier_button.add_theme_stylebox_override("pressed", pill)
	_load_earlier_button.pressed.connect(on_load_earlier_pressed)
	area.add_child(_load_earlier_button)

	_search_panel = PanelContainer.new()
	_search_panel.anchor_left = 1.0
	_search_panel.anchor_right = 1.0
	_search_panel.offset_left = -Margin.ma_8 - 480
	_search_panel.offset_right = -Margin.ma_8
	_search_panel.offset_top = Margin.ma_4
	_search_panel.offset_bottom = Margin.ma_4
	_search_panel.custom_minimum_size = Vector2(480, 0)
	_search_panel.visible = false
	var search_style := StyleBoxFlat.new()
	search_style.bg_color = AppTheme.container_surface()
	search_style.border_color = ThemeColor.theme_color
	search_style.set_border_width_all(1)
	search_style.set_corner_radius_all(10)
	search_style.content_margin_left = Margin.ma_3
	search_style.content_margin_right = Margin.ma_3
	search_style.content_margin_top = Margin.ma_2
	search_style.content_margin_bottom = Margin.ma_2
	_search_panel.add_theme_stylebox_override("panel", search_style)
	area.add_child(_search_panel)

	var search_column := VBoxContainer.new()
	search_column.add_theme_constant_override("separation", Margin.ma_1)
	_search_panel.add_child(search_column)

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", Margin.ma_2)
	search_column.add_child(search_row)

	_search_field = LineEdit.new()
	_search_field.size_flags_horizontal = SIZE_EXPAND_FILL
	_search_field.custom_minimum_size = Vector2(0, 30)
	_search_field.clear_button_enabled = true
	_search_field.add_theme_font_override("font", Fonts.regular())
	_search_field.add_theme_font_size_override("font_size", Typography.body_small)
	_search_field.add_theme_color_override("font_color", ThemeColor.title_color)
	_search_field.add_theme_color_override("font_placeholder_color", ThemeColor.body_color.darkened(0.15))
	_search_field.add_theme_color_override("caret_color", ThemeColor.theme_color)
	for state: String in ["normal", "focus", "read_only"]:
		var field_style := StyleBoxFlat.new()
		field_style.bg_color = AppTheme.control_surface()
		field_style.border_color = ThemeColor.theme_color if state == "focus" else AppTheme.outline()
		field_style.set_border_width_all(1)
		field_style.set_corner_radius_all(8)
		field_style.content_margin_left = Margin.ma_2
		field_style.content_margin_right = Margin.ma_2
		_search_field.add_theme_stylebox_override(state, field_style)
	_search_field.text_changed.connect(func(text: String) -> void: run_search(text))
	_search_field.text_submitted.connect(func(_text: String) -> void: focus_first_result())
	search_row.add_child(_search_field)

	var search_close := Button.new()
	search_close.text = "✕"
	search_close.flat = true
	search_close.focus_mode = FOCUS_NONE
	search_close.custom_minimum_size = Vector2(26, 24)
	search_close.add_theme_font_override("font", Fonts.code())
	search_close.add_theme_color_override("font_color", ThemeColor.body_color)
	search_close.pressed.connect(func() -> void: toggle_search(false))
	search_row.add_child(search_close)

	_search_status = Label.new()
	_search_status.add_theme_font_override("font", Fonts.code())
	_search_status.add_theme_font_size_override("font_size", Typography.body_small - 1)
	_search_status.add_theme_color_override("font_color", ThemeColor.body_color)
	search_column.add_child(_search_status)

	var search_scroll := ScrollContainer.new()
	search_scroll.custom_minimum_size = Vector2(0, 280)
	search_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	search_column.add_child(search_scroll)

	_search_results = VBoxContainer.new()
	_search_results.size_flags_horizontal = SIZE_EXPAND_FILL
	_search_results.add_theme_constant_override("separation", 4)
	search_scroll.add_child(_search_results)

	_runtime_strip = PanelContainer.new()
	_runtime_strip.anchor_left = 0.0
	_runtime_strip.anchor_right = 1.0
	_runtime_strip.anchor_top = 1.0
	_runtime_strip.anchor_bottom = 1.0
	_runtime_strip.offset_left = Margin.ma_8
	_runtime_strip.offset_right = -Margin.ma_8
	_runtime_strip.offset_top = -COMPOSER_HEIGHT - 8
	_runtime_strip.offset_bottom = -COMPOSER_HEIGHT - 4
	_runtime_strip.grow_vertical = GROW_DIRECTION_BEGIN
	_runtime_strip.mouse_filter = MOUSE_FILTER_IGNORE
	_runtime_strip.visible = false
	var strip_style := StyleBoxFlat.new()
	strip_style.bg_color = Color(AppTheme.control_surface(), 0.86)
	strip_style.set_corner_radius_all(8)
	strip_style.content_margin_left = Margin.ma_2
	strip_style.content_margin_right = Margin.ma_2
	strip_style.content_margin_top = Margin.ma_1
	strip_style.content_margin_bottom = Margin.ma_1
	_runtime_strip.add_theme_stylebox_override("panel", strip_style)
	area.add_child(_runtime_strip)

	_strip_row = HBoxContainer.new()
	_strip_row.add_theme_constant_override("separation", Margin.ma_2)
	_runtime_strip.add_child(_strip_row)

	_widget_label = Label.new()
	_widget_label.add_theme_font_override("font", Fonts.code())
	_widget_label.add_theme_font_size_override("font_size", Typography.body_small - 1)
	_widget_label.add_theme_color_override("font_color", ThemeColor.body_color.darkened(0.15))
	_strip_row.add_child(_widget_label)

	_strip_status_label = Label.new()
	_strip_status_label.clip_text = true
	_strip_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_strip_status_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_strip_status_label.add_theme_font_override("font", Fonts.code())
	_strip_status_label.add_theme_font_size_override("font_size", Typography.body_small - 1)
	_strip_status_label.add_theme_color_override("font_color", ThemeColor.theme_color)
	_strip_row.add_child(_strip_status_label)

	_empty_hint = VBoxContainer.new()
	_empty_hint.set_anchors_preset(PRESET_FULL_RECT)
	_empty_hint.offset_bottom = -COMPOSER_HEIGHT
	_empty_hint.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty_hint.mouse_filter = MOUSE_FILTER_IGNORE
	_empty_hint.add_theme_constant_override("separation", Margin.ma_2)
	area.add_child(_empty_hint)

	_visual_stage = VisualStage.new()
	_visual_stage.name = "VisualStage"
	area.add_child(_visual_stage)

	area.add_child(build_composer())
	return area


func build_composer() -> Control:
	_composer = PanelContainer.new()
	_composer.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_composer.offset_top = -COMPOSER_HEIGHT
	_composer.offset_left = Margin.ma_8
	_composer.offset_right = -Margin.ma_8
	_composer.offset_bottom = -Margin.ma_4
	_composer.mouse_filter = MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.control_surface() 
	style.border_color = AppTheme.outline() 
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = Margin.ma_3
	style.content_margin_right = Margin.ma_3
	style.content_margin_top = Margin.ma_2
	style.content_margin_bottom = Margin.ma_2
	_composer.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", Margin.ma_1)
	_composer.add_child(column)

	_attachment_row = HBoxContainer.new()
	_attachment_row.add_theme_constant_override("separation", Margin.ma_2)
	_attachment_row.visible = false
	column.add_child(_attachment_row)

	_input_field = TextEdit.new()
	_input_field.placeholder_text = T.t("gai_pi.composer.placeholder")
	_input_field.custom_minimum_size = Vector2(0, 56)
	_input_field.size_flags_vertical = SIZE_EXPAND_FILL
	_input_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_input_field.add_theme_font_override("font", Fonts.regular())
	_input_field.add_theme_font_size_override("font_size", Typography.body_large)
	_input_field.add_theme_color_override("font_color", ThemeColor.title_color)
	_input_field.add_theme_color_override("font_placeholder_color", ThemeColor.body_color.darkened(0.1))
	_input_field.add_theme_color_override("caret_color", ThemeColor.theme_color)
	var flat_edit := StyleBoxEmpty.new()
	_input_field.add_theme_stylebox_override("normal", flat_edit)
	_input_field.add_theme_stylebox_override("focus", flat_edit)
	_input_field.add_theme_stylebox_override("read_only", flat_edit)
	column.add_child(_input_field)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Margin.ma_2)
	column.add_child(row)

	_hint_label = Label.new()
	_hint_label.text = T.t("gai_pi.composer.hint")
	_hint_label.add_theme_font_override("font", Fonts.code())
	_hint_label.add_theme_font_size_override("font_size", Typography.body_small - 1)
	_hint_label.add_theme_color_override("font_color", ThemeColor.body_color.darkened(0.2))
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(_hint_label)

	_stop_button = make_flat_button(T.t("gai_pi.composer.stop"), T.t("gai_pi.composer.stop_tooltip"))
	_stop_button.add_theme_color_override("font_color", AppTheme.ink(Color("#ff8f8f")))
	_stop_button.pressed.connect(on_stop_pressed)
	_stop_button.visible = false
	row.add_child(_stop_button)

	_send_button = Button.new()
	_send_button.text = T.t("gai_pi.composer.send")
	_send_button.add_theme_font_override("font", Fonts.semibold())
	_send_button.add_theme_font_size_override("font_size", Typography.body_medium)
	_send_button.custom_minimum_size = Vector2(84, 30)
	_send_button.add_theme_color_override("font_color", AppTheme.background())
	_send_button.add_theme_color_override("font_hover_color", AppTheme.background())
	for state: String in ["normal", "hover", "pressed"]:
		var button_style := StyleBoxFlat.new()
		button_style.bg_color = ThemeColor.theme_color if state == "normal" else ThemeColor.theme_color.lightened(0.12)
		button_style.set_corner_radius_all(8)
		button_style.content_margin_left = Margin.ma_3
		button_style.content_margin_right = Margin.ma_3
		_send_button.add_theme_stylebox_override(state, button_style)
	_send_button.pressed.connect(on_send_pressed)
	row.add_child(_send_button)
	return _composer


func make_flat_button(text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.focus_mode = FOCUS_NONE
	button.tooltip_text = tooltip
	button.add_theme_font_override("font", Fonts.regular())
	button.add_theme_font_size_override("font_size", Typography.body_small)
	button.add_theme_color_override("font_color", ThemeColor.body_color)
	button.add_theme_color_override("font_hover_color", ThemeColor.title_color)
	return button


# ---------------------------------------------------------------------------
# Workspace lifecycle
# ---------------------------------------------------------------------------

func _initial_workspace() -> String:
	var configured := AppSetting.get_string(AppSetting.KEY_WORKSPACE)
	if not configured.is_empty() and DirAccess.dir_exists_absolute(configured):
		return configured
	var environment := OS.get_environment("GAI_PI_WORKSPACE").strip_edges()
	if not environment.is_empty() and DirAccess.dir_exists_absolute(environment):
		return environment
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://")
	return OS.get_executable_path().get_base_dir()


## Opens a workspace: stops the previous hosts, then starts a fresh session process.
func open_workspace(path: String) -> void:
	shutdown_hosts()
	_workspace_path = path
	_hosts.clear()
	_bound_hosts.clear()
	_host_lru.clear()
	_active_key = StringUtils.EMPTY
	_boot_hooks_done = false
	AppSetting.set_string(AppSetting.KEY_WORKSPACE, path)
	PiEvents.events.workspace_changed.emit(path)
	_workspace_button.text = _short_path(path)
	_sidebar_failed = false
	_sidebar_status.text = T.t("gai_pi.sidebar.starting")
	_checkpoints = CheckpointManager.new()
	_checkpoints.failed.connect(func(message: String) -> void: show_status(message))
	_checkpoints.setup(path)
	if _editor != null:
		_editor.set_workspace(path)
	var key := "new:%d" % _new_session_seq
	_new_session_seq += 1
	create_host(key, StringUtils.EMPTY)
	activate_session(key)


func on_agent_end_checkpoint(session_id: int, _error_message: String) -> void:
	# Background hosts settle too; only the visible turn owns the checkpoint.
	if session == null or session.local_id != session_id:
		return
	finish_checkpoint()


func on_dialog_requested(data: Dictionary) -> void:
	if _dialogs != null:
		_dialogs.request(data)


func on_dialog_answered(id: String, payload: Dictionary) -> void:
	var key: String = _dialog_host_by_id.get(id, _active_key)
	_dialog_host_by_id.erase(id)
	var host: PiWorkspace = _hosts.get(key)
	if host != null:
		host.answer_dialog(id, payload)


func on_notification(message: String, level: String) -> void:
	if _status_label == null:
		return
	if level == "error":
		_status_label.add_theme_color_override("font_color", AppTheme.ink(Color("#ff8f8f")))
	elif level == "warning":
		_status_label.add_theme_color_override("font_color", AppTheme.ink(Color("#ffd479")))
	else:
		_status_label.add_theme_color_override("font_color", ThemeColor.body_color)
	show_status(message)


func create_host(key: String, session_path: String) -> PiWorkspace:
	_local_id_seq += 1
	var host := PiWorkspace.new(_workspace_path, session_path)
	host.local_id = _local_id_seq
	host.checkpoints = _checkpoints
	host.ready.connect(func() -> void: on_host_ready(key))
	host.failed.connect(func(message: String) -> void: on_host_failed(key, message))
	host.session_loaded.connect(func(session_value: PiSession) -> void: on_host_loaded(key, session_value))
	host.streaming_changed.connect(func(streaming: bool) -> void: on_host_streaming(key, streaming))
	host.state_changed.connect(func() -> void: on_host_state(key))
	host.prompt_done.connect(func(_disposition: String) -> void: refresh_sessions(true))
	host.dialog_requested.connect(func(data: Dictionary) -> void: on_host_dialog(key, data))
	host.notification.connect(on_notification)
	host.status_changed.connect(on_extension_status)
	host.widget_changed.connect(on_extension_widget)
	_hosts[key] = host
	host.start()
	return host


func shutdown_hosts() -> void:
	for host in _hosts.values():
		if host != null:
			host.stop()
	_hosts.clear()
	_bound_hosts.clear()
	_host_lru.clear()
	workspace_host = null
	session = null


func bind_host_session(key: String) -> void:
	var host: PiWorkspace = _hosts.get(key)
	if host == null or host.session == null or _bound_hosts.has(key):
		return
	_bound_hosts[key] = true
	host.session.entry_added.connect(func(entry: ChatEntry) -> void: on_host_entry_added(key, entry))
	host.session.entry_updated.connect(func(entry: ChatEntry, kind: String) -> void: on_host_entry_updated(key, entry, kind))
	host.session.usage_changed.connect(func(usage: OpenAiUsage) -> void:
		if key == _active_key:
			on_usage_changed(usage)
	)
	host.session.title_changed.connect(func(_title: String) -> void: refresh_sessions(true))


## Shows one host's transcript without stopping the others.
func activate_session(key: String) -> bool:
	if not _hosts.has(key):
		return false
	var host: PiWorkspace = _hosts[key]
	_active_key = key
	_host_lru[key] = Time.get_ticks_msec()
	workspace_host = host
	session = host.session
	bind_host_session(key)
	_sidebar_failed = false
	update_empty_state()
	if host.is_ready and session != null:
		start_transcript_build(session.entries)
		on_state_changed()
		_sidebar_status.text = StringUtils.EMPTY
	else:
		clear_transcript()
		_sidebar_status.text = T.t("gai_pi.sidebar.starting")
	_visuals_picker.selected = clampi(AppSetting.get_int(AppSetting.KEY_VISUAL, 0), 0, VisualStage.type_names().size() - 1)
	refresh_sessions(true)
	evict_hosts()
	return true


## Reuses the running host for this file, or starts one for it.
func open_session_by_path(path: String) -> void:
	if path.is_empty():
		return
	if _hosts.has(path):
		activate_session(path)
		return
	_sidebar_status.text = T.t("gai_pi.sidebar.switching")
	create_host(path, path)
	activate_session(path)


func on_host_ready(key: String) -> void:
	var host: PiWorkspace = _hosts.get(key)
	if host == null or key != _active_key:
		bind_host_session(key)
		return
	session = host.session
	bind_host_session(key)
	start_transcript_build(session.entries)
	on_state_changed()
	refresh_sessions(true)
	_sidebar_status.text = StringUtils.EMPTY
	_visuals_picker.selected = clampi(AppSetting.get_int(AppSetting.KEY_VISUAL, 0), 0, VisualStage.type_names().size() - 1)
	if not _boot_hooks_done:
		_boot_hooks_done = true
		run_boot_hooks()
	else:
		update_empty_state()
	maybe_show_pending_diff()


func run_boot_hooks() -> void:
	var fake_dialog := OS.get_environment("GAI_PI_FAKE_DIALOG").strip_edges()
	if not fake_dialog.is_empty() and _dialogs != null:
		_dialogs.request({
			"id": "fake-dialog",
			"method": fake_dialog,
			"title": "Allow dangerous command?" if fake_dialog == "confirm" else "Pick a target",
			"message": "pi wants to run: rm -rf build/",
			"options": ["Allow once", "Allow for this session", "Block"],
			"placeholder": "type a value…",
		})
	var open_session := OS.get_environment("GAI_PI_SESSION").strip_edges()
	if not open_session.is_empty():
		var target := open_session if FileAccess.file_exists(open_session) else PiSessionIndex.path_for_id(_workspace_path, open_session)
		if not target.is_empty():
			open_session_by_path(target)
	var auto_prompt := OS.get_environment("GAI_PI_AUTOPROMPT").strip_edges()
	if not auto_prompt.is_empty():
		_input_field.text = auto_prompt
		on_send_pressed()


func on_host_failed(key: String, message: String) -> void:
	var host: PiWorkspace = _hosts.get(key)
	if host != null:
		_hosts.erase(key)
		_bound_hosts.erase(key)
		host.stop()
	if key != _active_key:
		return
	_sidebar_failed = true
	_sidebar_status.text = message
	show_status(message)


func on_host_loaded(key: String, loaded: PiSession) -> void:
	print("[gai-pi] session ", loaded.pi_id, " entries=", loaded.entries.size(), " path=", loaded.path)
	bind_host_session(key)
	rekey_host(key)
	if key != _active_key:
		return
	session = loaded
	if _sidebar_status != null and not _sidebar_failed:
		_sidebar_status.text = StringUtils.EMPTY
	start_transcript_build(loaded.entries)
	refresh_sessions(true)
	maybe_show_pending_diff()
	if not _pending_delete.is_empty() and loaded.path != _pending_delete:
		var stale := _pending_delete
		_pending_delete = StringUtils.EMPTY
		remove_session_file(stale)


func on_host_streaming(key: String, streaming: bool) -> void:
	rekey_host(key)
	refresh_sessions(true)
	if key != _active_key:
		return
	if _stop_button != null:
		_stop_button.visible = streaming
	if _send_button != null:
		_send_button.text = T.t("gai_pi.composer.steer") if streaming else T.t("gai_pi.composer.send")


func on_host_state(key: String) -> void:
	if key != _active_key:
		return
	on_state_changed()


## A fresh session gets its file after the first message; move the host to that key.
func rekey_host(key: String) -> void:
	var host: PiWorkspace = _hosts.get(key)
	if host == null or host.session == null:
		return
	var path := host.session.path
	if path.is_empty() or path == key or _hosts.has(path):
		return
	_hosts.erase(key)
	_hosts[path] = host
	if _active_key == key:
		_active_key = path
	_bound_hosts.erase(key)
	if _host_lru.has(key):
		_host_lru[path] = _host_lru[key]
		_host_lru.erase(key)
	refresh_sessions(true)


## Keeps memory bounded: idle, unselected processes are stopped first.
func evict_hosts() -> void:
	const MAX_HOSTS := 4
	if _hosts.size() <= MAX_HOSTS:
		return
	var candidates: Array[String] = []
	for key in _hosts:
		var host: PiWorkspace = _hosts[key]
		if key == _active_key or host.is_streaming:
			continue
		candidates.append(key)
	candidates.sort_custom(func(a: String, b: String) -> bool:
		return int(_host_lru.get(a, 0)) < int(_host_lru.get(b, 0))
	)
	while _hosts.size() > MAX_HOSTS and not candidates.is_empty():
		var victim: String = candidates.pop_front()
		_hosts[victim].stop()
		_hosts.erase(victim)
		_bound_hosts.erase(victim)
		_host_lru.erase(victim)


func on_host_dialog(key: String, data: Dictionary) -> void:
	var id := str(data.get("id", StringUtils.EMPTY))
	if not id.is_empty():
		_dialog_host_by_id[id] = key
	if _dialogs != null:
		_dialogs.request(data)


## Builds an explicit slice, used when a search hit is outside the tail window.
func start_transcript_window(from: int, to: int) -> void:
	if session == null:
		return
	clear_transcript()
	_build_generation += 1
	_window_start = clampi(from, 0, session.entries.size())
	_build_queue = session.entries.slice(_window_start, clampi(to, _window_start, session.entries.size()))
	_build_started_at = Time.get_ticks_msec()
	update_load_earlier()
	build_next_batch()


## Replays a session across frames; the interface stays responsive while hundreds of
## markdown bubbles are being laid out.
func start_transcript_build(entries: Array[ChatEntry]) -> void:
	clear_transcript()
	_build_generation += 1
	var start := maxi(0, entries.size() - TRANSCRIPT_WINDOW)
	_window_start = start
	_build_queue = entries.slice(start, entries.size())
	_build_started_at = Time.get_ticks_msec()
	update_load_earlier()
	build_next_batch()


func build_next_batch() -> void:
	var generation := _build_generation
	var started := Time.get_ticks_msec()
	while not _build_queue.is_empty() and generation == _build_generation:
		add_bubble(_build_queue.pop_front())
		if Time.get_ticks_msec() - started >= BUILD_BUDGET_MS:
			break
	if generation != _build_generation:
		return
	if _build_queue.is_empty():
		scroll_to_bottom()
		print("[gai-pi] transcript ready entries=", _bubbles.size(), " window_start=", _window_start, " in ", Time.get_ticks_msec() - _build_started_at, "ms")


## Shows or hides the "load earlier" pill above the transcript.
func update_load_earlier() -> void:
	if _load_earlier_button == null:
		return
	var hidden_count := _window_start
	_load_earlier_button.visible = hidden_count > 0
	if hidden_count > 0:
		_load_earlier_button.text = T.t("gai_pi.chat.load_earlier", [mini(hidden_count, TRANSCRIPT_WINDOW_STEP), hidden_count])


func on_load_earlier_pressed() -> void:
	if session == null or _window_start <= 0:
		return
	var from := maxi(0, _window_start - TRANSCRIPT_WINDOW_STEP)
	var slice := session.entries.slice(from, _window_start)
	var old_height := _entries_box.size.y
	for index in slice.size():
		var bubble := make_bubble(slice[index])
		_entries_box.add_child(bubble)
		_entries_box.move_child(bubble, index)
	_window_start = from
	update_load_earlier()
	# Keep the reader's position: the window grew above the viewport.
	await get_tree().process_frame
	await get_tree().process_frame
	var added := _entries_box.size.y - old_height
	if added > 0:
		_programmatic_scroll = true
		_scroll.scroll_vertical += int(added)
		_programmatic_scroll = false


# ---------------------------------------------------------------------------
# Transcript
# ---------------------------------------------------------------------------

func on_host_entry_added(key: String, entry: ChatEntry) -> void:
	if key != _active_key:
		return
	add_bubble(entry)
	if _follow_tail:
		scroll_to_bottom()


func make_bubble(entry: ChatEntry) -> ChatBubble:
	var bubble := ChatBubble.new()
	bubble.setup(entry)
	bubble.expand_toggled.connect(on_bubble_expanded)
	bubble.copy_requested.connect(on_copy_entry)
	bubble.prefill_requested.connect(on_prefill_entry)
	bubble.restore_requested.connect(on_restore_entry)
	bubble.revert_requested.connect(on_revert_entry)
	return bubble


func on_copy_entry(entry: ChatEntry) -> void:
	DisplayServer.clipboard_set(entry.body)
	show_status(T.t("gai_pi.chat.copied"))


func on_prefill_entry(entry: ChatEntry) -> void:
	_input_field.text = entry.body
	_input_field.grab_focus()
	_input_field.set_caret_line(maxi(0, _input_field.get_line_count() - 1))


func on_restore_entry(entry: ChatEntry) -> void:
	if session == null:
		return
	var error := session.restore_snapshot(entry.tool_call_id)
	show_status(T.t("gai_pi.chat.restore_failed") if not error.is_empty() else T.t("gai_pi.chat.restored"))


func on_bubble_expanded() -> void:
	if _follow_tail:
		scroll_to_bottom()


func add_bubble(entry: ChatEntry) -> void:
	if _bubbles.has(entry):
		return
	var bubble := make_bubble(entry)
	_entries_box.add_child(bubble)
	_bubbles[entry] = bubble
	update_empty_state()


func on_host_entry_updated(key: String, entry: ChatEntry, _stream_kind: String) -> void:
	if key != _active_key:
		return
	var bubble: ChatBubble = _bubbles.get(entry)
	if bubble == null:
		add_bubble(entry)
		bubble = _bubbles.get(entry)
	if bubble == null:
		return
	bubble.dirty = true
	if not _dirty_bubbles.has(bubble):
		_dirty_bubbles.append(bubble)
	if _follow_tail:
		scroll_to_bottom()


func flush_bubbles() -> void:
	var refreshed := 0
	while not _dirty_bubbles.is_empty() and refreshed < FLUSH_BATCH:
		var bubble: ChatBubble = _dirty_bubbles.pop_front()
		refreshed += 1
		if is_instance_valid(bubble):
			bubble.refresh()
			if bubble.entry != null and (bubble.entry.running or bubble.entry.kind == ChatEntry.KIND_AGENT):
				if _follow_tail:
					scroll_to_bottom()


func clear_transcript() -> void:
	_search_lower.clear()
	for bubble in _bubbles.values():
		if is_instance_valid(bubble):
			bubble.queue_free()
	_bubbles.clear()
	_dirty_bubbles.clear()
	_build_generation += 1
	_build_queue.clear()
	_window_start = 0
	if _load_earlier_button != null:
		_load_earlier_button.visible = false
	update_empty_state()


## Rebuilds the first-run hint that sits under the transcript while it is empty.
func update_empty_state() -> void:
	if _empty_hint == null:
		return
	_empty_hint.visible = _bubbles.is_empty() and _build_queue.is_empty() and _window_start == 0
	if not _empty_hint.visible:
		return
	for child in _empty_hint.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "gai-pi"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", Fonts.bold())
	title.add_theme_font_size_override("font_size", Typography.headline_medium)
	title.add_theme_color_override("font_color", ThemeColor.theme_color)
	_empty_hint.add_child(title)
	var subtitle := Label.new()
	subtitle.text = T.t("gai_pi.empty.subtitle")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", Fonts.regular())
	subtitle.add_theme_font_size_override("font_size", Typography.body_medium)
	subtitle.add_theme_color_override("font_color", ThemeColor.body_color)
	_empty_hint.add_child(subtitle)
	var path_label := Label.new()
	path_label.text = workspace_host.workspace if workspace_host != null else StringUtils.EMPTY
	path_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	path_label.add_theme_font_override("font", Fonts.code())
	path_label.add_theme_font_size_override("font_size", Typography.body_small)
	path_label.add_theme_color_override("font_color", ThemeColor.body_color.darkened(0.2))
	_empty_hint.add_child(path_label)


## Keeps the tail visible when the transcript grows between frames, such as a 400-entry rebuild
## whose layout settles after the short retry window.
func watch_scroll_extent() -> void:
	if _scroll == null:
		return
	var bar := _scroll.get_v_scroll_bar()
	if bar == null:
		return
	if is_equal_approx(bar.max_value, _last_scroll_max):
		return
	_last_scroll_max = bar.max_value
	if _follow_tail:
		scroll_to_bottom()


## Requests a follow-the-tail scroll; several frames are retried so a long rebuild can settle.
func scroll_to_bottom() -> void:
	_follow_tail = true
	_follow_until = Time.get_ticks_msec() + 1500
	_scroll_requested_at = Time.get_ticks_msec()
	_scroll_attempts = 24


func apply_scroll_bottom() -> void:
	if _scroll == null:
		return
	var bar := _scroll.get_v_scroll_bar()
	if bar == null:
		return
	_programmatic_scroll = true
	_scroll.scroll_vertical = int(bar.max_value)
	_programmatic_scroll = false


## User scrolling away from the bottom stops auto-follow until they scroll back down.
func on_scroll_changed(value: float) -> void:
	if _programmatic_scroll or _scroll == null:
		return
	if Time.get_ticks_msec() < _follow_until:
		return
	var bar := _scroll.get_v_scroll_bar()
	if bar == null:
		return
	_follow_tail = value + bar.page >= bar.max_value - 48


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func on_submit() -> void:
	on_send_pressed()


## Enter submits, Shift+Enter keeps the newline. Handled before GUI delivery so the
## TextEdit never sees the key and cannot insert a line break.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F and key.ctrl_pressed and not key.alt_pressed:
		if _search_panel != null and not (_prompt != null and _prompt.visible):
			get_viewport().set_input_as_handled()
			toggle_search(not _search_panel.visible)
		return
	if key.keycode == KEY_ESCAPE and _search_panel != null and _search_panel.visible:
		get_viewport().set_input_as_handled()
		toggle_search(false)
		return
	if _prompt != null and _prompt.visible:
		return
	if _dialogs != null and _dialogs.is_open():
		# A modal owns the keyboard: Escape cancels, Enter must not reach the composer.
		if key.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_dialogs.answer({"cancelled": true})
		elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
		return
	if _input_field == null or not _input_field.has_focus():
		return
	if key.keycode == KEY_V and (key.ctrl_pressed or key.meta_pressed) and DisplayServer.clipboard_has_image():
		if DisplayServer.clipboard_get().strip_edges().is_empty():
			var image := DisplayServer.clipboard_get_image()
			if image != null and not image.is_empty():
				get_viewport().set_input_as_handled()
				attach_image(image, "clipboard.png")
				return
	if key.keycode != KEY_ENTER and key.keycode != KEY_KP_ENTER:
		return
	if key.shift_pressed:
		return
	get_viewport().set_input_as_handled()
	on_submit()


func on_send_pressed() -> void:
	if workspace_host == null or session == null or _input_field == null:
		return
	var text := _input_field.text.strip_edges()
	var images := pending_images()
	if text.is_empty() and images.is_empty():
		return
	var behavior := StringUtils.EMPTY
	if workspace_host.is_streaming:
		behavior = "steer" if AppSetting.get_string(AppSetting.KEY_STEERING, "steer") == "steer" else "followUp"
	_input_field.text = StringUtils.EMPTY
	_follow_tail = true
	if behavior.is_empty():
		begin_checkpoint()
	if text.is_empty():
		text = T.t("gai_pi.composer.image_prompt")
	_attachments.clear()
	rebuild_attachment_row()
	workspace_host.prompt(text, behavior, images)
	scroll_to_bottom()


func on_stop_pressed() -> void:
	if workspace_host != null:
		workspace_host.abort()


func on_new_session_pressed() -> void:
	if workspace_host == null:
		return
	var key := "new:%d" % _new_session_seq
	_new_session_seq += 1
	create_host(key, StringUtils.EMPTY)
	activate_session(key)


func on_workspace_pressed() -> void:
	if _workspace_dialog != null:
		_workspace_dialog.popup_centered_ratio(0.6)


func on_workspace_selected(path: String) -> void:
	open_workspace(path)


func on_visual_selected(index: int) -> void:
	if _suppress_visual_signal:
		return
	if _visual_stage == null:
		AppSetting.set_int(AppSetting.KEY_VISUAL, index)
		return
	_visual_stage.apply_visual_type(index)


func on_model_pressed() -> void:
	if workspace_host == null:
		return
	workspace_host.get_models(func(result: Dictionary) -> void:
		if not bool(result.get("success", false)):
			show_status(T.t("gai_pi.status.models_failed"))
			return
		var data := PiSession.as_dictionary(result.get("data", {}))
		var menu := PopupMenu.new()
		menu.add_theme_font_override("font", Fonts.regular())
		var models: Array = PiSession.as_array(data.get("models", []))
		var labels: Array[String] = []
		for index in models.size():
			var model: Dictionary = PiSession.as_dictionary(models[index])
			var label := "%s  ·  %s" % [str(model.get("name", model.get("id", ""))), str(model.get("provider", ""))]
			labels.append(str(model.get("id", "")))
			menu.add_item(label, index)
		menu.id_pressed.connect(func(index: int) -> void:
			if index >= 0 and index < labels.size():
				workspace_host.set_model(labels[index])
		)
		add_child(menu)
		menu.popup_hide.connect(menu.queue_free)
		menu.position = Vector2i(get_global_mouse_position())
		menu.popup()
	)


func on_thinking_pressed() -> void:
	var menu := PopupMenu.new()
	menu.add_theme_font_override("font", Fonts.regular())
	for index in THINKING_LEVELS.size():
		var level: String = THINKING_LEVELS[index]
		menu.add_item(thinking_label(level), index)
	menu.id_pressed.connect(func(index: int) -> void:
		if workspace_host != null and index >= 0 and index < THINKING_LEVELS.size():
			workspace_host.set_thinking_level(THINKING_LEVELS[index])
	)
	add_child(menu)
	menu.popup_hide.connect(menu.queue_free)
	menu.position = Vector2i(get_global_mouse_position())
	menu.popup()


func on_state_changed() -> void:
	if workspace_host == null:
		return
	_model_button.text = workspace_host.model_label if not workspace_host.model_label.is_empty() else "model"
	_thinking_button.text = thinking_label(workspace_host.thinking_level)
	refresh_sessions()


func on_usage_changed(usage: OpenAiUsage) -> void:
	_last_usage = usage
	render_usage()


func render_usage() -> void:
	if _usage_label == null:
		return
	if _last_usage == null or not _last_usage.has_data():
		_usage_label.text = StringUtils.EMPTY
		return
	_usage_label.text = T.t("gai_pi.topbar.usage", [format_tokens(_last_usage.prompt_tokens)])


# ---------------------------------------------------------------------------
# Sessions
# ---------------------------------------------------------------------------

## Right-click menu for a session row: pin, rename, delete.
func show_session_menu(meta: Dictionary, pinned: bool) -> void:
	var path := str(meta.get("path", StringUtils.EMPTY))
	if path.is_empty():
		return
	var streaming := workspace_host != null and workspace_host.is_streaming
	var active := session != null and session.path == path
	var menu := PopupMenu.new()
	menu.add_theme_font_override("font", Fonts.regular())
	menu.add_item(T.t("gai_pi.session.unpin") if pinned else T.t("gai_pi.session.pin"), 0)
	menu.add_item(T.t("gai_pi.session.rename"), 1)
	menu.add_item(T.t("gai_pi.session.delete"), 2)
	menu.set_item_disabled(1, not active)
	menu.set_item_disabled(2, streaming)
	menu.id_pressed.connect(func(index: int) -> void:
		match index:
			0:
				toggle_pin(path)
			1:
				rename_active_session(meta)
			2:
				ask_delete_session(meta)
	)
	add_child(menu)
	menu.popup_hide.connect(menu.queue_free)
	menu.position = Vector2i(get_global_mouse_position())
	menu.popup()


func load_pins() -> void:
	_pinned_paths.clear()
	var stored := AppSetting.get_string(AppSetting.KEY_PINS)
	if stored.is_empty():
		return
	for path in stored.split("|", false):
		_pinned_paths.append(path)


func save_pins() -> void:
	AppSetting.set_string(AppSetting.KEY_PINS, "|".join(_pinned_paths))


func toggle_pin(path: String) -> void:
	if _pinned_paths.has(path):
		_pinned_paths.erase(path)
	else:
		_pinned_paths.append(path)
	save_pins()
	refresh_sessions(true)


func rename_active_session(meta: Dictionary) -> void:
	if workspace_host == null or session == null:
		return
	var path := str(meta.get("path", StringUtils.EMPTY))
	if session.path != path:
		show_status(T.t("gai_pi.status.rename_active_only"))
		return
	var current := str(meta.get("title", StringUtils.EMPTY))
	_prompt.ask_text(T.t("gai_pi.session.rename"), current, T.t("gai_pi.session.rename_placeholder"), func(value: String) -> void:
		workspace_host.set_session_name(value)
		PiSessionIndex.invalidate(path)
		refresh_sessions(true)
	)


func ask_delete_session(meta: Dictionary) -> void:
	if workspace_host == null:
		return
	if workspace_host.is_streaming:
		show_status(T.t("gai_pi.status.delete_while_running"))
		return
	var path := str(meta.get("path", StringUtils.EMPTY))
	if path.is_empty():
		return
	_prompt.ask_confirm(T.t("gai_pi.session.delete_title"), T.t("gai_pi.session.delete_message"), func() -> void:
		delete_session_file(path)
	)


func delete_session_file(path: String) -> void:
	if session != null and session.path == path:
		# pi still holds the file open; park the delete until a fresh session is loaded.
		_pending_delete = path
		on_new_session_pressed()
		return
	remove_session_file(path)


func remove_session_file(path: String) -> void:
	DirAccess.remove_absolute(path)
	PiSessionIndex.invalidate(path)
	_pinned_paths.erase(path)
	save_pins()
	refresh_sessions(true)


func refresh_sessions(force: bool = false) -> void:
	if _session_list == null or workspace_host == null:
		return
	var active_path := session.path if session != null else StringUtils.EMPTY
	var filter := _session_search.text.strip_edges().to_lower() if _session_search != null else StringUtils.EMPTY
	var pinned_rows: Array[Dictionary] = []
	var recent_rows: Array[Dictionary] = []
	var signature_parts := PackedStringArray([active_path, filter, "|".join(_pinned_paths)])
	for meta in workspace_host.session_list():
		var path := str(meta.get("path", ""))
		var title := str(meta.get("title", ""))
		var preview := str(meta.get("preview", ""))
		var host: PiWorkspace = _hosts.get(path)
		var running := host != null and host.is_streaming
		signature_parts.append("%s|%s|%s|%s" % [path, title, str(meta.get("modified", 0)), running])
		if not filter.is_empty() and not title.to_lower().contains(filter) and not preview.to_lower().contains(filter):
			continue
		if _pinned_paths.has(path):
			pinned_rows.append(meta)
		else:
			recent_rows.append(meta)
	var signature := "|".join(signature_parts)
	if not force and signature == _sessions_signature:
		return
	_sessions_signature = signature
	for child in _session_list.get_children():
		child.queue_free()
	if not pinned_rows.is_empty():
		add_session_header(T.t("gai_pi.session.pinned"))
		for meta in pinned_rows:
			_session_list.add_child(build_session_row(meta, str(meta.get("path", "")) == active_path, true))
	if not recent_rows.is_empty():
		if not pinned_rows.is_empty():
			add_session_header(T.t("gai_pi.session.recent"))
		for meta in recent_rows:
			_session_list.add_child(build_session_row(meta, str(meta.get("path", "")) == active_path, false))
	if pinned_rows.is_empty() and recent_rows.is_empty():
		var empty := Label.new()
		empty.text = T.t("gai_pi.sidebar.empty")
		empty.add_theme_font_override("font", Fonts.code())
		empty.add_theme_font_size_override("font_size", Typography.body_small)
		empty.add_theme_color_override("font_color", ThemeColor.body_color.darkened(0.25))
		_session_list.add_child(empty)


func add_session_header(text: String) -> void:
	var header := Label.new()
	header.text = text
	header.add_theme_font_override("font", Fonts.semibold())
	header.add_theme_font_size_override("font_size", Typography.body_small - 1)
	header.add_theme_color_override("font_color", ThemeColor.body_color.darkened(0.15))
	header.custom_minimum_size = Vector2(0, 22)
	header.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_session_list.add_child(header)


func style_sidebar_field(control: LineEdit) -> void:
	control.add_theme_color_override("font_color", ThemeColor.title_color)
	control.add_theme_color_override("font_placeholder_color", ThemeColor.body_color.darkened(0.2))
	control.add_theme_color_override("caret_color", ThemeColor.theme_color)
	for state: String in ["normal", "focus", "read_only"]:
		var style := StyleBoxFlat.new()
		style.bg_color = AppTheme.control_surface() 
		style.border_color = ThemeColor.theme_color if state == "focus" else AppTheme.outline() 
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.content_margin_left = Margin.ma_2
		style.content_margin_right = Margin.ma_2
		control.add_theme_stylebox_override(state, style)


func build_session_row(meta: Dictionary, is_active: bool, pinned: bool = false) -> Control:
	var path := str(meta.get("path", StringUtils.EMPTY))
	var button := Button.new()
	button.flat = true
	button.focus_mode = FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 48)
	button.tooltip_text = str(meta.get("preview", StringUtils.EMPTY))
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	button.mouse_filter = MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColor.mix_with_theme_color(AppTheme.control_surface(), 0.35) if is_active else Color(0, 0, 0, 0)
	style.set_corner_radius_all(8)
	style.content_margin_left = Margin.ma_2
	style.content_margin_right = Margin.ma_2
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.pressed.connect(func() -> void:
		if path.is_empty():
			return
		open_session_by_path(path)
	)
	button.gui_input.connect(func(event: InputEvent) -> void:
		var mouse := event as InputEventMouseButton
		if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
			show_session_menu(meta, pinned)
	)

	var column := VBoxContainer.new()
	column.set_anchors_preset(PRESET_FULL_RECT)
	column.offset_left = Margin.ma_2
	column.offset_right = -Margin.ma_2
	column.offset_top = Margin.ma_1
	column.offset_bottom = -Margin.ma_1
	column.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	button.add_child(column)

	var title := Label.new()
	var raw_title := str(meta.get("title", StringUtils.EMPTY))
	title.text = raw_title if not raw_title.is_empty() else T.t("gai_pi.sidebar.untitled")
	var host: PiWorkspace = _hosts.get(path)
	if host != null and host.is_streaming:
		title.text = "● " + title.text
		title.add_theme_color_override("font_color", ThemeColor.theme_color)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_override("font", Fonts.medium())
	title.add_theme_font_size_override("font_size", Typography.body_medium)
	title.add_theme_color_override("font_color", ThemeColor.theme_color if pinned else (ThemeColor.title_color if is_active else ThemeColor.body_color))
	title.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(title)

	var preview := Label.new()
	preview.text = str(meta.get("preview", StringUtils.EMPTY))
	preview.clip_text = true
	preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	preview.add_theme_font_override("font", Fonts.code())
	preview.add_theme_font_size_override("font_size", Typography.body_small - 2)
	preview.add_theme_color_override("font_color", ThemeColor.body_color.darkened(0.25))
	preview.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(preview)
	return button


# ---------------------------------------------------------------------------
# Checkpoints
# ---------------------------------------------------------------------------

## Opens a checkpoint before a fresh turn; steering messages stay inside the same turn.
func begin_checkpoint() -> void:
	if _checkpoints == null or not _checkpoints.enabled or session == null:
		return
	if not _turn_start_commit.is_empty():
		return
	# The entry is created before the prompt so it sits at the top of the turn; the commit lands
	# a moment later and fills in the revert handle.
	_turn_entry = session.add_checkpoint_entry(_turn_index + 1, StringUtils.EMPTY)
	# Timestamp the checkpoint before the prompt is sent, so replay puts it above the message.
	var stamp := int(Time.get_unix_time_from_system() * 1000.0)
	_checkpoints.begin_turn(func(turn: int, commit: String) -> void:
		if session == null:
			return
		if turn < 0 or commit.is_empty():
			session.finish_checkpoint_entry(_turn_entry, T.t("gai_pi.checkpoint.unavailable"))
			_turn_entry = null
			return
		_turn_start_commit = commit
		_turn_index = turn
		_turn_entry.timestamp = stamp
		if _turn_entry != null:
			_turn_entry.id = "checkpoint-%d" % turn
			_turn_entry.details["checkpoint"] = commit
			_turn_entry.details["turn"] = str(turn)
		if session != null:
			_checkpoints.save_turn_record(session.pi_id, turn, commit, StringUtils.EMPTY, stamp)
		if not session.running:
			finish_checkpoint()
	)


func finish_checkpoint() -> void:
	if _turn_start_commit.is_empty() or _checkpoints == null:
		return
	var start := _turn_start_commit
	var turn := _turn_index
	var entry := _turn_entry
	var session_id := session.pi_id if session != null else StringUtils.EMPTY
	_turn_start_commit = StringUtils.EMPTY
	_turn_entry = null
	_checkpoints.end_turn(turn, start, func(files: Array) -> void:
		var summary := _checkpoints.format_file_list(files)
		if session != null and entry != null and is_instance_valid(entry):
			session.finish_checkpoint_entry(entry, summary)
		_checkpoints.set_turn_summary(session_id, turn, summary)
	)

func on_revert_entry(entry: ChatEntry) -> void:
	if _checkpoints == null or not _checkpoints.enabled or workspace_host == null:
		return
	if workspace_host.is_streaming:
		show_status(T.t("gai_pi.status.switch_while_running"))
		return
	var commit := str(entry.details.get("checkpoint", StringUtils.EMPTY))
	var turn := int(entry.details.get("turn", "0"))
	if commit.is_empty():
		return
	_prompt.ask_confirm(T.t("gai_pi.checkpoint.revert_title"), T.t("gai_pi.checkpoint.revert_message"), func() -> void:
		_checkpoints.revert_turn(turn, commit, func(ok: bool) -> void:
			if ok and session != null:
				session.mark_checkpoint_reverted(entry)
				_checkpoints.set_turn_summary(session.pi_id, turn, entry.body, true)
				show_status(T.t("gai_pi.checkpoint.revert_done"))
			else:
				show_status(T.t("gai_pi.checkpoint.revert_failed"))
		)
	)


# ---------------------------------------------------------------------------
# Transcript search
# ---------------------------------------------------------------------------

func toggle_search(show_search: bool) -> void:
	if _search_panel == null:
		return
	_search_panel.visible = show_search
	if not show_search:
		return
	_search_field.grab_focus()
	run_search(_search_field.text)


func focus_first_result() -> void:
	_search_field.release_focus()
	if _search_results.get_child_count() > 0:
		var first := _search_results.get_child(0) as Button
		if first != null:
			first.pressed.emit()


func run_search(query: String) -> void:
	if _search_results == null or session == null:
		return
	for child in _search_results.get_children():
		child.queue_free()
	if query.strip_edges().is_empty():
		_search_status.text = StringUtils.EMPTY
		return
	var matches := ChatSearch.find_matches(session.entries, query, ChatSearch.MAX_RESULTS, _search_lower)
	_search_status.text = T.t("gai_pi.search.no_results") if matches.is_empty() else T.t("gai_pi.search.results", [matches.size()])
	for match in matches:
		var entry: ChatEntry = match["entry"]
		var row := Button.new()
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.custom_minimum_size = Vector2(0, 30)
		row.text = "%s · %s" % [ChatSearch.kind_label(str(match["kind"])), str(match["snippet"])]
		row.add_theme_font_override("font", Fonts.regular())
		row.add_theme_font_size_override("font_size", Typography.body_small)
		row.add_theme_color_override("font_color", ThemeColor.title_color)
		row.add_theme_color_override("font_hover_color", ThemeColor.theme_color)
		for state: String in ["normal", "hover", "pressed"]:
			var row_style := StyleBoxFlat.new()
			row_style.bg_color = Color(0, 0, 0, 0) if state == "normal" else ThemeColor.mix_with_theme_color(AppTheme.control_surface(), 0.35)
			row_style.set_corner_radius_all(6)
			row_style.content_margin_left = Margin.ma_2
			row_style.content_margin_right = Margin.ma_2
			row.add_theme_stylebox_override(state, row_style)
		row.tooltip_text = entry.body
		row.pressed.connect(func() -> void: reveal_entry(entry))
		_search_results.add_child(row)


## Jumps to a search hit: rebuilds the window around it when it is older than the tail.
func reveal_entry(entry: ChatEntry) -> void:
	toggle_search(false)
	if session == null:
		return
	var index := session.entries.find(entry)
	if index < 0:
		return
	if not _bubbles.has(entry):
		# A hit far back gets a window around itself instead of just the tail.
		var from := maxi(0, index - 8)
		start_transcript_window(from, from + TRANSCRIPT_WINDOW)
		var guard := 0
		while not _build_queue.is_empty() and guard < 900:
			guard += 1
			await get_tree().process_frame
	var bubble: ChatBubble = _bubbles.get(entry)
	if bubble == null:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_follow_tail = false
	scroll_to_bubble(bubble)
	bubble.flash()


func scroll_to_bubble(bubble: Control) -> void:
	if _scroll == null:
		return
	var offset := bubble.global_position.y - _scroll.global_position.y
	var target := _scroll.scroll_vertical + int(offset) - int(_scroll.size.y * 0.3)
	_programmatic_scroll = true
	_scroll.scroll_vertical = maxi(0, target)
	_programmatic_scroll = false


# ---------------------------------------------------------------------------
# Theme
# ---------------------------------------------------------------------------

## Panel styles are built with concrete colors, so a theme change rebuilds the shell.
## The pi process and the session survive: only the widgets are disposable.
func on_theme_changed() -> void:
	rebuild_ui_for_theme()


func rebuild_ui_for_theme() -> void:
	var draft := _input_field.text if _input_field != null else StringUtils.EMPTY
	var attachments := _attachments.duplicate()
	var editor_open := _editor != null and _editor.visible
	var editor_file := _editor.current_file() if editor_open else StringUtils.EMPTY
	_bubbles.clear()
	_dirty_bubbles.clear()
	_build_queue.clear()
	_build_generation += 1
	_sessions_signature = StringUtils.EMPTY
	# Remove before freeing so the old shell cannot draw over the new one for a frame.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	build_ui()
	_prompt = ModalPrompt.new()
	add_child(_prompt)
	_attachments = attachments
	apply_locale()
	if not attachments.is_empty():
		rebuild_attachment_row()
	rebuild_runtime_strip()
	if session != null:
		start_transcript_build(session.entries)
	_input_field.text = draft
	if editor_open:
		toggle_editor(true)
		if not editor_file.is_empty():
			_editor.show_file(editor_file)


# ---------------------------------------------------------------------------
# Editor
# ---------------------------------------------------------------------------

func toggle_editor(show_editor: bool) -> void:
	if _editor == null:
		return
	if show_editor and not _editor.is_built():
		_editor.setup(_editor.workspace)
	_editor.visible = show_editor
	if show_editor and _editor.is_built():
		_editor.reload()


## Shows what the last turn changed in this file, against its opening checkpoint.
func maybe_show_pending_diff() -> void:
	if not _pending_editor_diff or _editor == null or not _editor.visible:
		return
	# Wait for the host that owns the checkpoint records: a fresh session has no path yet.
	if session == null or session.path.is_empty() or _checkpoints == null or not _checkpoints.enabled:
		return
	var file := _editor.current_file()
	if file.is_empty():
		return
	_pending_editor_diff = false
	on_editor_diff(file)


func on_editor_diff(path: String) -> void:
	if _editor == null or _checkpoints == null or not _checkpoints.enabled or session == null:
		return
	var base := _checkpoints.latest_start_commit(session.pi_id)
	if base.is_empty():
		base = _checkpoints.baseline_commit()
	if base.is_empty():
		_editor.show_diff_notice(T.t("gai_pi.editor.no_checkpoint"))
		return
	var relative := path.replace("\\", "/")
	if relative.begins_with(_workspace_path.replace("\\", "/") + "/"):
		relative = relative.substr(_workspace_path.replace("\\", "/").length() + 1)
	_checkpoints.file_diff(base, relative, func(text: String) -> void:
		_editor.show_diff(path, text)
	)


func on_editor_reference(path: String) -> void:
	if _input_field == null:
		return
	var relative := _editor.relative_path(path).replace("\\", "/")
	var reference := "@" + relative
	var existing := _input_field.text.strip_edges()
	_input_field.text = (existing + " " + reference).strip_edges() if not existing.is_empty() else reference
	_input_field.grab_focus()
	_input_field.set_caret_line(maxi(0, _input_field.get_line_count() - 1))


# ---------------------------------------------------------------------------
# Attachments
# ---------------------------------------------------------------------------

const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp", "bmp", "gif"]
const MAX_ATTACHMENTS := 5
const MAX_IMAGE_EDGE := 1600


## Queues an image for the next prompt; pi takes it as base64 ImageContent.
func attach_image(image: Image, name: String) -> void:
	if image == null or image.is_empty() or _attachments.size() >= MAX_ATTACHMENTS:
		return
	var normalized := image.duplicate()
	if normalized.get_width() > MAX_IMAGE_EDGE or normalized.get_height() > MAX_IMAGE_EDGE:
		var factor := float(MAX_IMAGE_EDGE) / float(maxi(normalized.get_width(), normalized.get_height()))
		normalized.resize(
			maxi(1, int(normalized.get_width() * factor)),
			maxi(1, int(normalized.get_height() * factor)),
			Image.INTERPOLATE_LANCZOS
		)
	_attachments.append({
		"type": "image",
		"data": Marshalls.raw_to_base64(normalized.save_png_to_buffer()),
		"mimeType": "image/png",
		"name": name,
		"texture": ImageTexture.create_from_image(normalized),
	})
	rebuild_attachment_row()


func rebuild_attachment_row() -> void:
	if _attachment_row == null:
		return
	for child in _attachment_row.get_children():
		child.queue_free()
	_attachment_row.visible = not _attachments.is_empty()
	apply_composer_height()
	for index in _attachments.size():
		var chip := PanelContainer.new()
		var chip_style := StyleBoxFlat.new()
		chip_style.bg_color = AppTheme.container_surface() 
		chip_style.set_corner_radius_all(6)
		chip_style.content_margin_left = Margin.ma_1
		chip_style.content_margin_right = Margin.ma_1
		chip_style.content_margin_top = 2
		chip_style.content_margin_bottom = 2
		chip.add_theme_stylebox_override("panel", chip_style)
		_attachment_row.add_child(chip)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Margin.ma_1)
		chip.add_child(row)
		var thumb := TextureRect.new()
		thumb.texture = _attachments[index]["texture"]
		thumb.custom_minimum_size = Vector2(26, 26)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		row.add_child(thumb)
		var remove := Button.new()
		remove.text = "✕"
		remove.flat = true
		remove.focus_mode = FOCUS_NONE
		remove.custom_minimum_size = Vector2(20, 20)
		remove.add_theme_font_override("font", Fonts.code())
		remove.add_theme_font_size_override("font_size", Typography.body_small - 2)
		remove.tooltip_text = T.t("gai_pi.composer.remove_image")
		remove.pressed.connect(func() -> void:
			_attachments.remove_at(index)
			rebuild_attachment_row()
		)
		row.add_child(remove)


## The composer and the transcript reserve only what the current attachments need.
func apply_composer_height() -> void:
	if _composer == null or _scroll == null:
		return
	var height := COMPOSER_HEIGHT_ATTACHED if not _attachments.is_empty() else COMPOSER_HEIGHT
	_composer.offset_top = -height
	_scroll.offset_bottom = -height
	if _empty_hint != null:
		_empty_hint.offset_bottom = -height
	if _runtime_strip != null:
		_runtime_strip.offset_top = -height - 8
		_runtime_strip.offset_bottom = -height - 4


func pending_images() -> Array:
	var images: Array = []
	for attachment in _attachments:
		images.append({
			"type": "image",
			"data": str(attachment.get("data", StringUtils.EMPTY)),
			"mimeType": str(attachment.get("mimeType", "image/png")),
		})
	return images


## Files dropped anywhere on the window attach when they are images.
func on_files_dropped(files: PackedStringArray) -> void:
	for path in files:
		if not IMAGE_EXTS.has(path.get_extension().to_lower()):
			continue
		var image := Image.new()
		if image.load(path) == OK:
			attach_image(image, path.get_file())


# ---------------------------------------------------------------------------
# Extension status and widgets
# ---------------------------------------------------------------------------

func on_extension_status(key: String, text: String) -> void:
	if key.is_empty():
		return
	if text.strip_edges().is_empty():
		_extension_status.erase(key)
	else:
		_extension_status[key] = text
	rebuild_runtime_strip()


func on_extension_widget(key: String, lines: Array, _placement: String) -> void:
	if key.is_empty():
		return
	var cleaned := TextSanitize.widget_lines(lines)
	if cleaned.is_empty():
		_extension_widgets.erase(key)
	else:
		_extension_widgets[key] = cleaned
	rebuild_runtime_strip()


func rebuild_runtime_strip() -> void:
	if _runtime_strip == null:
		return
	var widget_lines := PackedStringArray()
	for key in _extension_widgets:
		widget_lines.append_array(_extension_widgets[key])
	_widget_label.text = "\n".join(widget_lines)
	_widget_label.visible = not widget_lines.is_empty()
	var statuses := PackedStringArray()
	for key in _extension_status:
		statuses.append(_extension_status[key])
	_strip_status_label.text = "  ·  ".join(statuses)
	_strip_status_label.tooltip_text = _strip_status_label.text
	_strip_status_label.visible = not statuses.is_empty()
	_runtime_strip.visible = _widget_label.visible or _strip_status_label.visible


# ---------------------------------------------------------------------------
# Language
# ---------------------------------------------------------------------------

## Re-applies every shell string; called on boot and whenever the locale changes.
func apply_locale() -> void:
	if _workspace_button == null:
		return
	_workspace_button.tooltip_text = T.t("gai_pi.topbar.switch_workspace")
	if not _workspace_path.is_empty():
		_workspace_button.text = _short_path(_workspace_path)
	_model_button.tooltip_text = T.t("gai_pi.topbar.choose_model")
	_thinking_button.tooltip_text = T.t("gai_pi.topbar.thinking")
	_visuals_picker.tooltip_text = T.t("gai_pi.topbar.visual")
	_editor_button.text = T.t("gai_pi.editor.toggle")
	_editor_button.tooltip_text = T.t("gai_pi.editor.toggle_tooltip")
	_search_button.tooltip_text = T.t("gai_pi.search.button")
	if _search_field != null:
		_search_field.placeholder_text = T.t("gai_pi.search.placeholder")
	_theme_button.text = "☀" if AppTheme.is_dark() else "☾"
	_theme_button.tooltip_text = T.t("gai_pi.topbar.toggle_light") if AppTheme.is_dark() else T.t("gai_pi.topbar.toggle_dark")
	if _editor != null:
		_editor.apply_locale()
	_language_button.text = T.t("gai_pi.language.code")
	_language_button.tooltip_text = T.t("gai_pi.topbar.language")
	if _workspace_dialog != null:
		_workspace_dialog.title = T.t("gai_pi.topbar.switch_workspace")
	_new_session_button.text = T.t("gai_pi.sidebar.new")
	if _session_search != null:
		_session_search.placeholder_text = T.t("gai_pi.session.search_placeholder")
	_stop_button.text = T.t("gai_pi.composer.stop")
	_stop_button.tooltip_text = T.t("gai_pi.composer.stop_tooltip")
	var streaming := workspace_host != null and workspace_host.is_streaming
	_send_button.text = T.t("gai_pi.composer.steer") if streaming else T.t("gai_pi.composer.send")
	_input_field.placeholder_text = T.t("gai_pi.composer.placeholder")
	_hint_label.text = T.t("gai_pi.composer.hint")
	if workspace_host != null and not workspace_host.is_ready and not _sidebar_failed:
		_sidebar_status.text = T.t("gai_pi.sidebar.starting")
	refresh_visual_picker()
	refresh_sessions(true)
	update_empty_state()
	render_usage()
	on_state_changed()
	for bubble in _bubbles.values():
		if is_instance_valid(bubble):
			bubble.refresh()
	update_load_earlier()
	if _prompt != null and _prompt.visible:
		return
	if _dialogs != null and _dialogs.is_open():
		_dialogs.rebuild()


func refresh_visual_picker() -> void:
	if _visuals_picker == null:
		return
	var selected := _visuals_picker.selected
	_suppress_visual_signal = true
	_visuals_picker.clear()
	for index in VisualStage.type_names().size():
		_visuals_picker.add_item(VisualStage.localized_name(index), index)
	_visuals_picker.selected = clampi(selected, 0, VisualStage.type_names().size() - 1)
	_suppress_visual_signal = false


func thinking_label(level: String) -> String:
	if level.is_empty():
		return T.t("gai_pi.topbar.thinking")
	var key := "gai_pi.thinking." + level
	var text := T.t(key)
	return text if text != key else level.capitalize()


func on_language_pressed() -> void:
	var menu := PopupMenu.new()
	menu.add_theme_font_override("font", Fonts.regular())
	menu.add_item(T.t("gai_pi.language.zh"), 0)
	menu.add_item(T.t("gai_pi.language.en"), 1)
	menu.set_item_checked(0 if T.locale_code() == "zh" else 1, true)
	menu.id_pressed.connect(func(index: int) -> void:
		switch_language("zh" if index == 0 else "en")
	)
	add_child(menu)
	menu.popup_hide.connect(menu.queue_free)
	menu.position = Vector2i(get_global_mouse_position())
	menu.popup()


## Switches the interface language immediately; I18n persists the choice.
func switch_language(code: String) -> void:
	if code == T.locale_code() and I18n.is_initialized():
		return
	I18n.set_locale("res://app/locale/zh.json" if code == "zh" else "res://app/locale/en.json")
	# I18n.set_locale emits gdf.events.locale_changed, which runs apply_locale().


## GAI_PI_LOCALE forces a language for screenshots and verification runs.
func apply_locale_override() -> void:
	var code := OS.get_environment("GAI_PI_LOCALE").strip_edges()
	if code.is_empty():
		return
	I18n.set_locale("res://app/locale/zh.json" if code.begins_with("zh") else "res://app/locale/en.json")


# ---------------------------------------------------------------------------
# Status helpers
# ---------------------------------------------------------------------------

var _error_shown_at: int = 0
var _error_text: String = StringUtils.EMPTY
var _status_shown_at: int = 0


func _poll_errors() -> void:
	if _status_label != null and _status_label.visible and _status_shown_at > 0 and Time.get_ticks_msec() - _status_shown_at > 8000:
		_status_label.visible = false
	if _error_text.is_empty():
		return
	show_status(_error_text)
	_error_text = StringUtils.EMPTY


func show_status(message: String) -> void:
	if _status_label == null:
		return
	var single_line := message.replace("
", "  ")
	_status_label.text = single_line if single_line.length() <= 72 else single_line.left(69) + "…"
	_status_label.tooltip_text = message
	_status_label.visible = not message.is_empty()
	_status_shown_at = Time.get_ticks_msec()
	if _sidebar_status != null and message.begins_with("pi "):
		_sidebar_status.text = message


func on_host_error(message: String) -> void:
	_error_text = message


func _init_i18n() -> void:
	if I18n.is_initialized():
		return
	var locale := I18n.get_locale()
	var path := "res://app/locale/zh.json" if locale.begins_with("zh") else "res://app/locale/en.json"
	I18n.set_locale(path)


func _short_path(path: String) -> String:
	var normalized := path.replace("\\", "/").trim_suffix("/")
	var parts := normalized.split("/", false)
	if parts.size() <= 2:
		return normalized
	return "…/" + "/".join(parts.slice(parts.size() - 2))


static func format_tokens(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.1fk" % (value / 1000.0)
	return str(value)
