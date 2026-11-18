class_name PiDialogLayer
extends Control

## Modal surface for pi extension dialogs (`select`, `confirm`, `input`, `editor`).
##
## pi blocks the extension until an `extension_ui_response` arrives, so every dialog must be
## answered or cancelled. Dialogs that carry a timeout are auto-cancelled here as well, and a
## later request queues behind the visible one.

signal answered(id: String, payload: Dictionary)

var _current: Dictionary = {}
var _queue: Array[Dictionary] = []
var _overlay: ColorRect = null
var _card: PanelContainer = null
var _body: VBoxContainer = null
var _deadline_ms: int = 0
var _input: LineEdit = null
var _multiline: TextEdit = null


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	set_process(true)


func is_open() -> bool:
	return not _current.is_empty()


## Accepts an `extension_ui_request`; only dialog methods are rendered here.
func request(data: Dictionary) -> void:
	var method := str(data.get("method", StringUtils.EMPTY))
	if method != "select" and method != "confirm" and method != "input" and method != "editor":
		return
	if _current.is_empty():
		open(data)
	else:
		_queue.append(data)


func open(data: Dictionary) -> void:
	_current = data
	visible = true
	mouse_filter = MOUSE_FILTER_STOP
	# The layer can be created before the window's first layout pass, so re-assert the rect.
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build()
	var timeout := int(data.get("timeout", 0))
	_deadline_ms = 0 if timeout <= 0 else Time.get_ticks_msec() + timeout


## Re-renders the open dialog, used when the interface language changes.
func rebuild() -> void:
	if _current.is_empty():
		return
	_build()


func _clear() -> void:
	for child in get_children():
		child.queue_free()
	_overlay = null
	_card = null
	_body = null
	_input = null
	_multiline = null


func _build() -> void:
	_clear()
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.55)
	_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)

	_card = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Colors.DARK_SURFACE_CONTAINER
	style.border_color = ThemeColor.theme_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = Margin.ma_5
	style.content_margin_right = Margin.ma_5
	style.content_margin_top = Margin.ma_4
	style.content_margin_bottom = Margin.ma_4
	_card.add_theme_stylebox_override("panel", style)
	_card.custom_minimum_size = Vector2(520, 0)
	center.add_child(_card)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", Margin.ma_3)
	_card.add_child(_body)

	var title := Label.new()
	title.text = str(_current.get("title", T.t("gai_pi.dialog.default_title")))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_override("font", Fonts.semibold())
	title.add_theme_font_size_override("font_size", Typography.title_medium)
	title.add_theme_color_override("font_color", ThemeColor.title_color)
	_body.add_child(title)

	var message := str(_current.get("message", StringUtils.EMPTY))
	if not message.is_empty():
		var message_label := Label.new()
		message_label.text = message
		message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message_label.add_theme_font_override("font", Fonts.regular())
		message_label.add_theme_font_size_override("font_size", Typography.body_medium)
		message_label.add_theme_color_override("font_color", ThemeColor.body_color)
		_body.add_child(message_label)

	var method := str(_current.get("method", StringUtils.EMPTY))
	match method:
		"select":
			_build_select()
		"confirm":
			pass
		"input":
			_build_input(false)
		"editor":
			_build_input(true)
	_body.add_child(build_buttons(method))


func _build_select() -> void:
	var options: Array = PiSession.as_array(_current.get("options", []))
	for index in options.size():
		var option := str(options[index])
		var button := Button.new()
		button.text = option
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 34)
		button.add_theme_font_override("font", Fonts.regular())
		button.add_theme_font_size_override("font_size", Typography.body_medium)
		style_button(button, false)
		button.pressed.connect(func() -> void: answer({"value": option}))
		_body.add_child(button)


func _build_input(multiline: bool) -> void:
	var prefill := str(_current.get("prefill", StringUtils.EMPTY))
	if multiline:
		_multiline = TextEdit.new()
		_multiline.text = prefill
		_multiline.custom_minimum_size = Vector2(0, 160)
		_multiline.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		_multiline.add_theme_font_override("font", Fonts.code())
		style_field(_multiline)
		_body.add_child(_multiline)
		_multiline.grab_focus()
		return
	_input = LineEdit.new()
	_input.text = prefill
	_input.placeholder_text = str(_current.get("placeholder", StringUtils.EMPTY))
	_input.custom_minimum_size = Vector2(0, 34)
	_input.add_theme_font_override("font", Fonts.regular())
	style_field(_input)
	_input.text_submitted.connect(func(_text: String) -> void: submit())
	_body.add_child(_input)
	_input.grab_focus()


func build_buttons(method: String) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", Margin.ma_2)

	var cancel := Button.new()
	cancel.text = T.t("common.cancel")
	cancel.custom_minimum_size = Vector2(88, 32)
	style_button(cancel, false)
	cancel.pressed.connect(func() -> void: answer({"cancelled": true}))
	row.add_child(cancel)

	if method == "select" or method == "confirm":
		if method == "confirm":
			var confirm := Button.new()
			confirm.text = T.t("gai_pi.dialog.allow")
			confirm.custom_minimum_size = Vector2(96, 32)
			style_button(confirm, true)
			confirm.pressed.connect(func() -> void: answer({"confirmed": true}))
			row.add_child(confirm)
		return row

	var submit_button := Button.new()
	submit_button.text = T.t("gai_pi.dialog.submit")
	submit_button.custom_minimum_size = Vector2(96, 32)
	style_button(submit_button, true)
	submit_button.pressed.connect(func() -> void: submit())
	row.add_child(submit_button)
	return row


func submit() -> void:
	if _multiline != null:
		answer({"value": _multiline.text})
		return
	if _input != null:
		answer({"value": _input.text})


func answer(payload: Dictionary) -> void:
	var id := str(_current.get("id", StringUtils.EMPTY))
	_current = {}
	visible = false
	mouse_filter = MOUSE_FILTER_IGNORE
	_clear()
	if not id.is_empty():
		answered.emit(id, payload)
	_next()


func _next() -> void:
	if _queue.is_empty():
		_card = null
		return
	var data: Dictionary = _queue.pop_front()
	open(data)


func _process(_delta: float) -> void:
	if _current.is_empty() or _deadline_ms <= 0:
		return
	if Time.get_ticks_msec() >= _deadline_ms:
		answer({"cancelled": true})


func _gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		accept_event()
		answer({"cancelled": true})


## Dark control styling so dialog fields and buttons sit in the same palette as the shell.
func style_field(control: Control) -> void:
	control.add_theme_color_override("font_color", ThemeColor.title_color)
	control.add_theme_color_override("font_placeholder_color", ThemeColor.body_color.darkened(0.15))
	control.add_theme_color_override("caret_color", ThemeColor.theme_color)
	control.add_theme_color_override("font_selected_color", ThemeColor.title_color)
	control.add_theme_color_override("selection_color", ThemeColor.selection_color)
	for state: String in ["normal", "focus", "read_only"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Colors.DARK_CONTROL_SURFACE
		style.border_color = ThemeColor.theme_color if state == "focus" else Colors.DARK_OUTLINE_VARIANT
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.content_margin_left = Margin.ma_2
		style.content_margin_right = Margin.ma_2
		control.add_theme_stylebox_override(state, style)


func style_button(button: Button, primary: bool) -> void:
	button.add_theme_font_override("font", Fonts.medium())
	button.add_theme_font_size_override("font_size", Typography.body_medium)
	button.add_theme_color_override("font_color", Colors.DARK_BACKGROUND if primary else ThemeColor.title_color)
	button.add_theme_color_override("font_hover_color", Colors.DARK_BACKGROUND if primary else ThemeColor.title_color)
	for state: String in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		if primary:
			style.bg_color = ThemeColor.theme_color if state == "normal" else ThemeColor.theme_color.lightened(0.12)
		else:
			style.bg_color = Colors.DARK_CONTROL_SURFACE if state == "normal" else Colors.DARK_SURFACE_CONTAINER_HIGH
		style.set_corner_radius_all(8)
		style.content_margin_left = Margin.ma_3
		style.content_margin_right = Margin.ma_3
		button.add_theme_stylebox_override(state, style)
