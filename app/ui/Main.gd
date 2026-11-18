extends Control

## gai-pi desktop shell: pi runs as an RPC child process, this scene is the whole UI.

const SIDEBAR_WIDTH := 300
const SIDEBAR_MIN_WIDTH := 240
const TOP_BAR_HEIGHT := 46
const COMPOSER_HEIGHT := 112
const FLUSH_INTERVAL_MS := 80

const THINKING_LEVELS := ["off", "minimal", "low", "medium", "high", "xhigh", "max"]
const THINKING_LABELS := {
	"off": "Off",
	"minimal": "Minimal",
	"low": "Low",
	"medium": "Medium",
	"high": "High",
	"xhigh": "XHigh",
	"max": "Max",
}


var workspace_host: PiWorkspace = null
var session: PiSession = null

var _bubbles: Dictionary = {}
var _dirty_bubbles: Array[ChatBubble] = []
var _last_flush: int = 0
var _follow_tail: bool = true
var _scroll_requested_at: int = 0
var _scroll_attempts: int = 0
var _programmatic_scroll: bool = false

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
var _empty_hint: VBoxContainer = null
var _dialogs: PiDialogLayer = null

## Verification hook: GAI_PI_SCREENSHOT=<png path> renders one frame, saves it, and quits.
var _screenshot_target: String = StringUtils.EMPTY
var _screenshot_at: int = 0
var _started_at: int = 0


func _ready() -> void:
	_started_at = Time.get_ticks_msec()
	_init_i18n()
	ThemeColor.load_theme()
	build_ui()
	open_workspace(_initial_workspace())
	var visual_override := OS.get_environment("GAI_PI_VISUAL").strip_edges()
	if not visual_override.is_empty():
		AppSetting.set_int(AppSetting.KEY_VISUAL, visual_override.to_int())
		_visuals_picker.selected = clampi(visual_override.to_int(), 0, VisualStage.type_names().size() - 1)
	get_window().title = "gai-pi"
	_input_field.grab_focus()
	_screenshot_target = OS.get_environment("GAI_PI_SCREENSHOT").strip_edges()
	_screenshot_at = _started_at + int(OS.get_environment("GAI_PI_SCREENSHOT_DELAY").to_int() if not OS.get_environment("GAI_PI_SCREENSHOT_DELAY").is_empty() else 6000)


func _process(_delta: float) -> void:
	if workspace_host != null:
		workspace_host.poll()
		_poll_errors()
	var now := Time.get_ticks_msec()
	if now - _last_flush >= FLUSH_INTERVAL_MS and not _dirty_bubbles.is_empty():
		_last_flush = now
		flush_bubbles()
	if _scroll_requested_at > 0 and now - _scroll_requested_at >= 50:
		_scroll_requested_at = 0 if _scroll_attempts <= 1 else now
		_scroll_attempts -= 1
		apply_scroll_bottom()
	if not _screenshot_target.is_empty() and now >= _screenshot_at:
		_capture_screenshot()


func _capture_screenshot() -> void:
	var target := _screenshot_target
	_screenshot_target = StringUtils.EMPTY
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(target)
	print("[gai-pi] screenshot ", target, " error=", error)
	await get_tree().process_frame
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and workspace_host != null:
		workspace_host.stop()


func _exit_tree() -> void:
	if workspace_host != null:
		workspace_host.stop()


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func build_ui() -> void:
	var background := ColorRect.new()
	background.color = Colors.DARK_BACKGROUND
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


func build_top_bar() -> Control:
	_top_bar = PanelContainer.new()
	_top_bar.custom_minimum_size = Vector2(0, TOP_BAR_HEIGHT)
	var style := StyleBoxFlat.new()
	style.bg_color = Colors.DARK_DEEP_SURFACE
	style.border_color = Colors.DARK_OUTLINE_VARIANT
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

	_workspace_button = make_flat_button("project", "Switch workspace")
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

	_model_button = make_flat_button("model", "Choose model")
	_model_button.pressed.connect(on_model_pressed)
	row.add_child(_model_button)

	_thinking_button = make_flat_button("thinking", "Thinking level")
	_thinking_button.pressed.connect(on_thinking_pressed)
	row.add_child(_thinking_button)

	_visuals_picker = OptionButton.new()
	_visuals_picker.flat = true
	_visuals_picker.focus_mode = FOCUS_NONE
	_visuals_picker.add_theme_font_override("font", Fonts.regular())
	_visuals_picker.add_theme_font_size_override("font_size", Typography.body_small)
	_visuals_picker.tooltip_text = "Agent visual"
	for index in VisualStage.type_names().size():
		_visuals_picker.add_item(VisualStage.localized_name(index), index)
	_visuals_picker.selected = clampi(AppSetting.get_int(AppSetting.KEY_VISUAL, 0), 0, VisualStage.type_names().size() - 1)
	_visuals_picker.item_selected.connect(on_visual_selected)
	row.add_child(_visuals_picker)

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
	_status_label.add_theme_color_override("font_color", Color("#ff8f8f"))
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.visible = false
	row.add_child(_status_label)

	_workspace_dialog = FileDialog.new()
	_workspace_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_workspace_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_workspace_dialog.title = "Choose workspace"
	_workspace_dialog.use_native_dialog = true
	_workspace_dialog.dir_selected.connect(on_workspace_selected)
	add_child(_workspace_dialog)
	return _top_bar


func build_sidebar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SIDEBAR_MIN_WIDTH, 0)
	panel.size_flags_horizontal = SIZE_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Colors.DARK_CHROME_SURFACE
	style.border_color = Colors.DARK_OUTLINE_VARIANT
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
	_new_session_button.text = "＋  New session"
	_new_session_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_new_session_button.add_theme_font_override("font", Fonts.medium())
	_new_session_button.add_theme_font_size_override("font_size", Typography.body_medium)
	_new_session_button.custom_minimum_size = Vector2(0, 36)
	_new_session_button.pressed.connect(on_new_session_pressed)
	column.add_child(_new_session_button)

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
	style.bg_color = Colors.DARK_CONTROL_SURFACE
	style.border_color = Colors.DARK_OUTLINE_VARIANT
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

	_input_field = TextEdit.new()
	_input_field.placeholder_text = "Ask pi to read, change, or verify something…"
	_input_field.custom_minimum_size = Vector2(0, 56)
	_input_field.size_flags_vertical = SIZE_EXPAND_FILL
	_input_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_input_field.add_theme_font_override("font", Fonts.regular())
	_input_field.add_theme_font_size_override("font_size", Typography.body_large)
	_input_field.add_theme_color_override("font_color", ThemeColor.title_color)
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
	_hint_label.text = "Enter sends · Shift+Enter newline"
	_hint_label.add_theme_font_override("font", Fonts.code())
	_hint_label.add_theme_font_size_override("font_size", Typography.body_small - 1)
	_hint_label.add_theme_color_override("font_color", ThemeColor.body_color.darkened(0.2))
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(_hint_label)

	_stop_button = make_flat_button("■ Stop", "Abort the run")
	_stop_button.add_theme_color_override("font_color", Color("#ff8f8f"))
	_stop_button.pressed.connect(on_stop_pressed)
	_stop_button.visible = false
	row.add_child(_stop_button)

	_send_button = Button.new()
	_send_button.text = "Send"
	_send_button.add_theme_font_override("font", Fonts.semibold())
	_send_button.add_theme_font_size_override("font_size", Typography.body_medium)
	_send_button.custom_minimum_size = Vector2(84, 30)
	_send_button.add_theme_color_override("font_color", Colors.DARK_BACKGROUND)
	_send_button.add_theme_color_override("font_hover_color", Colors.DARK_BACKGROUND)
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


func open_workspace(path: String) -> void:
	if workspace_host != null:
		workspace_host.stop()
	workspace_host = PiWorkspace.new(path)
	workspace_host.ready.connect(on_workspace_ready)
	workspace_host.failed.connect(on_workspace_failed)
	workspace_host.session_loaded.connect(on_session_loaded)
	workspace_host.streaming_changed.connect(on_streaming_changed)
	workspace_host.state_changed.connect(on_state_changed)
	workspace_host.prompt_done.connect(on_prompt_done)
	workspace_host.dialog_requested.connect(on_dialog_requested)
	workspace_host.notification.connect(on_notification)
	AppSetting.set_string(AppSetting.KEY_WORKSPACE, path)
	PiEvents.events.workspace_changed.emit(path)
	_workspace_button.text = _short_path(path)
	_sidebar_status.text = "starting pi…"
	workspace_host.start()


func on_prompt_done(_disposition: String) -> void:
	refresh_sessions()


func on_dialog_requested(data: Dictionary) -> void:
	if _dialogs != null:
		_dialogs.request(data)


func on_dialog_answered(id: String, payload: Dictionary) -> void:
	if workspace_host != null:
		workspace_host.answer_dialog(id, payload)


func on_notification(message: String, level: String) -> void:
	if _status_label == null:
		return
	if level == "error":
		_status_label.add_theme_color_override("font_color", Color("#ff8f8f"))
	elif level == "warning":
		_status_label.add_theme_color_override("font_color", Color("#ffd479"))
	else:
		_status_label.add_theme_color_override("font_color", ThemeColor.body_color)
	show_status(message)


func on_workspace_ready() -> void:
	session = workspace_host.session
	update_empty_state()
	_apply_session_signals(session)
	_sidebar_status.text = ""
	_visuals_picker.selected = clampi(AppSetting.get_int(AppSetting.KEY_VISUAL, 0), 0, VisualStage.type_names().size() - 1)
	refresh_sessions()
	on_state_changed()
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
		var target := open_session if FileAccess.file_exists(open_session) else PiSessionIndex.path_for_id(workspace_host.workspace, open_session)
		if not target.is_empty():
			workspace_host.switch_session(target)
	var auto_prompt := OS.get_environment("GAI_PI_AUTOPROMPT").strip_edges()
	if not auto_prompt.is_empty():
		_input_field.text = auto_prompt
		on_send_pressed()


func on_workspace_failed(message: String) -> void:
	_sidebar_status.text = message
	show_status(message)


func on_session_loaded(loaded: PiSession) -> void:
	print("[gai-pi] session ", loaded.pi_id, " entries=", loaded.entries.size(), " path=", loaded.path)
	session = loaded
	_apply_session_signals(loaded)
	clear_transcript()
	for entry in loaded.entries:
		add_bubble(entry)
	refresh_sessions()
	scroll_to_bottom()


func _apply_session_signals(target: PiSession) -> void:
	if target.is_connected("entry_added", on_entry_added):
		return
	target.entry_added.connect(on_entry_added)
	target.entry_updated.connect(on_entry_updated)
	target.usage_changed.connect(on_usage_changed)
	target.title_changed.connect(func(_title: String) -> void: refresh_sessions())


# ---------------------------------------------------------------------------
# Transcript
# ---------------------------------------------------------------------------

func on_entry_added(entry: ChatEntry) -> void:
	add_bubble(entry)
	if _follow_tail:
		scroll_to_bottom()


func add_bubble(entry: ChatEntry) -> void:
	if _bubbles.has(entry):
		return
	var bubble := ChatBubble.new()
	bubble.setup(entry)
	bubble.expand_toggled.connect(scroll_to_bottom)
	_entries_box.add_child(bubble)
	_bubbles[entry] = bubble
	update_empty_state()


func on_entry_updated(entry: ChatEntry, _stream_kind: String) -> void:
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
	for bubble in _dirty_bubbles:
		if is_instance_valid(bubble):
			bubble.refresh()
			if bubble.entry != null and (bubble.entry.running or bubble.entry.kind == ChatEntry.KIND_AGENT):
				if _follow_tail:
					scroll_to_bottom()
	_dirty_bubbles.clear()


func clear_transcript() -> void:
	for bubble in _bubbles.values():
		if is_instance_valid(bubble):
			bubble.queue_free()
	_bubbles.clear()
	_dirty_bubbles.clear()
	update_empty_state()


## Rebuilds the first-run hint that sits under the transcript while it is empty.
func update_empty_state() -> void:
	if _empty_hint == null:
		return
	_empty_hint.visible = _bubbles.is_empty()
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
	subtitle.text = "pi is loaded here — ask it to read, change, or verify this workspace."
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


## Requests a follow-the-tail scroll; several frames are retried so a long rebuild can settle.
func scroll_to_bottom() -> void:
	_scroll_requested_at = Time.get_ticks_msec()
	_scroll_attempts = 3


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
	if text.is_empty():
		return
	var behavior := StringUtils.EMPTY
	if workspace_host.is_streaming:
		behavior = "steer" if AppSetting.get_string(AppSetting.KEY_STEERING, "steer") == "steer" else "followUp"
	_input_field.text = StringUtils.EMPTY
	_follow_tail = true
	workspace_host.prompt(text, behavior)
	scroll_to_bottom()


func on_stop_pressed() -> void:
	if workspace_host != null:
		workspace_host.abort()


func on_new_session_pressed() -> void:
	if workspace_host == null:
		return
	if workspace_host.is_streaming:
		show_status("Stop the running turn before starting a new session")
		return
	clear_transcript()
	workspace_host.new_session()
	refresh_sessions()


func on_workspace_pressed() -> void:
	if _workspace_dialog != null:
		_workspace_dialog.popup_centered_ratio(0.6)


func on_workspace_selected(path: String) -> void:
	open_workspace(path)


func on_visual_selected(index: int) -> void:
	AppSetting.set_int(AppSetting.KEY_VISUAL, index)


func on_model_pressed() -> void:
	if workspace_host == null:
		return
	workspace_host.get_models(func(result: Dictionary) -> void:
		if not bool(result.get("success", false)):
			show_status("Could not list models")
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
		menu.add_item(THINKING_LABELS.get(level, level.capitalize()), index)
	menu.id_pressed.connect(func(index: int) -> void:
		if workspace_host != null and index >= 0 and index < THINKING_LEVELS.size():
			workspace_host.set_thinking_level(THINKING_LEVELS[index])
	)
	add_child(menu)
	menu.popup_hide.connect(menu.queue_free)
	menu.position = Vector2i(get_global_mouse_position())
	menu.popup()


func on_streaming_changed(streaming: bool) -> void:
	if _stop_button != null:
		_stop_button.visible = streaming
	if _send_button != null:
		_send_button.text = "Steer" if streaming else "Send"


func on_state_changed() -> void:
	if workspace_host == null:
		return
	_model_button.text = workspace_host.model_label if not workspace_host.model_label.is_empty() else "model"
	_thinking_button.text = THINKING_LABELS.get(workspace_host.thinking_level, workspace_host.thinking_level)
	refresh_sessions()


func on_usage_changed(usage: OpenAiUsage) -> void:
	if _usage_label == null:
		return
	_usage_label.text = "ctx %s" % format_tokens(usage.prompt_tokens) if usage.has_data() else StringUtils.EMPTY


# ---------------------------------------------------------------------------
# Sessions
# ---------------------------------------------------------------------------

func refresh_sessions() -> void:
	if _session_list == null or workspace_host == null:
		return
	for child in _session_list.get_children():
		child.queue_free()
	var active_path := session.path if session != null else StringUtils.EMPTY
	var sessions := workspace_host.session_list()
	for meta in sessions:
		_session_list.add_child(build_session_row(meta, str(meta.get("path", "")) == active_path))
	if sessions.is_empty():
		var empty := Label.new()
		empty.text = "No sessions yet"
		empty.add_theme_font_override("font", Fonts.code())
		empty.add_theme_font_size_override("font_size", Typography.body_small)
		empty.add_theme_color_override("font_color", ThemeColor.body_color.darkened(0.25))
		_session_list.add_child(empty)


func build_session_row(meta: Dictionary, is_active: bool) -> Control:
	var path := str(meta.get("path", StringUtils.EMPTY))
	var button := Button.new()
	button.flat = true
	button.focus_mode = FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 48)
	button.tooltip_text = str(meta.get("preview", StringUtils.EMPTY))
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	button.mouse_filter = MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColor.mix_with_theme_color(Colors.DARK_CONTROL_SURFACE, 0.35) if is_active else Color(0, 0, 0, 0)
	style.set_corner_radius_all(8)
	style.content_margin_left = Margin.ma_2
	style.content_margin_right = Margin.ma_2
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.pressed.connect(func() -> void:
		if workspace_host == null or path.is_empty():
			return
		if workspace_host.is_streaming:
			show_status("Stop the running turn before switching sessions")
			return
		workspace_host.switch_session(path)
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
	title.text = str(meta.get("title", "Session"))
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_override("font", Fonts.medium())
	title.add_theme_font_size_override("font_size", Typography.body_medium)
	title.add_theme_color_override("font_color", ThemeColor.title_color if is_active else ThemeColor.body_color)
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
