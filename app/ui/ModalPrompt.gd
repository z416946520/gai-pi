class_name ModalPrompt
extends Control

## Small modal used by the shell for rename and delete confirmation.
## Mirrors the visual language of [PiDialogLayer] but is not tied to pi extensions.

signal text_submitted(value: String)
signal confirmed
signal cancelled

var _overlay: ColorRect = null
var _card: PanelContainer = null
var _body: VBoxContainer = null
var _text_field: LineEdit = null
var _accept: Callable = Callable()
var _mode: String = StringUtils.EMPTY


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false


func ask_text(title: String, initial: String, placeholder: String, on_accept: Callable) -> void:
	_mode = "text"
	_accept = on_accept
	_build(title, StringUtils.EMPTY)
	_text_field = LineEdit.new()
	_text_field.text = initial
	_text_field.placeholder_text = placeholder
	_text_field.custom_minimum_size = Vector2(0, 34)
	_style_field(_text_field)
	_body.add_child(_text_field)
	_add_buttons(T.t("common.cancel"), T.t("gai_pi.dialog.save"))
	_text_field.grab_focus()
	_text_field.select_all()
	_text_field.text_submitted.connect(func(_text: String) -> void: accept())


func ask_confirm(title: String, message: String, on_accept: Callable) -> void:
	_mode = "confirm"
	_accept = on_accept
	_build(title, message)
	_add_buttons(T.t("common.cancel"), T.t("common.delete"), true)


func _build(title: String, message: String) -> void:
	visible = true
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
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
	style.bg_color = AppTheme.container_surface() 
	style.border_color = ThemeColor.theme_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = Margin.ma_5
	style.content_margin_right = Margin.ma_5
	style.content_margin_top = Margin.ma_4
	style.content_margin_bottom = Margin.ma_4
	_card.add_theme_stylebox_override("panel", style)
	_card.custom_minimum_size = Vector2(460, 0)
	center.add_child(_card)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", Margin.ma_3)
	_card.add_child(_body)

	var title_label := Label.new()
	title_label.text = title
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_override("font", Fonts.semibold())
	title_label.add_theme_font_size_override("font_size", Typography.title_medium)
	title_label.add_theme_color_override("font_color", ThemeColor.title_color)
	_body.add_child(title_label)

	if not message.is_empty():
		var message_label := Label.new()
		message_label.text = message
		message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message_label.add_theme_font_override("font", Fonts.regular())
		message_label.add_theme_font_size_override("font_size", Typography.body_medium)
		message_label.add_theme_color_override("font_color", ThemeColor.body_color)
		_body.add_child(message_label)


func _add_buttons(cancel_text: String, accept_text: String, destructive: bool = false) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", Margin.ma_2)
	_body.add_child(row)

	var cancel := Button.new()
	cancel.text = cancel_text
	cancel.custom_minimum_size = Vector2(88, 32)
	_style_button(cancel, false)
	cancel.pressed.connect(func() -> void: dismiss())
	row.add_child(cancel)

	var accept := Button.new()
	accept.text = accept_text
	accept.custom_minimum_size = Vector2(96, 32)
	_style_button(accept, true, destructive)
	accept.pressed.connect(func() -> void: accept())
	row.add_child(accept)


func accept() -> void:
	if _mode == "text":
		var value := _text_field.text.strip_edges() if _text_field != null else StringUtils.EMPTY
		if value.is_empty():
			return
		var callback := _accept
		dismiss()
		text_submitted.emit(value)
		if callback.is_valid():
			callback.call(value)
		return
	var callback := _accept
	dismiss()
	confirmed.emit()
	if callback.is_valid():
		callback.call()


func dismiss() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_IGNORE
	for child in get_children():
		child.queue_free()
	_overlay = null
	_card = null
	_body = null
	_text_field = null


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		dismiss()
		cancelled.emit()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		get_viewport().set_input_as_handled()
		accept()


func _style_field(control: Control) -> void:
	control.add_theme_color_override("font_color", ThemeColor.title_color)
	control.add_theme_color_override("font_placeholder_color", ThemeColor.body_color.darkened(0.15))
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


func _style_button(button: Button, primary: bool, destructive: bool = false) -> void:
	button.add_theme_font_override("font", Fonts.medium())
	button.add_theme_font_size_override("font_size", Typography.body_medium)
	var accent := Color("#ff8f8f") if destructive else ThemeColor.theme_color
	button.add_theme_color_override("font_color", Colors.DARK_BACKGROUND if primary else ThemeColor.title_color)
	button.add_theme_color_override("font_hover_color", Colors.DARK_BACKGROUND if primary else ThemeColor.title_color)
	for state: String in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		if primary:
			style.bg_color = accent if state == "normal" else accent.lightened(0.12)
		else:
			style.bg_color = AppTheme.control_surface()  if state == "normal" else AppTheme.container_high() 
		style.set_corner_radius_all(8)
		style.content_margin_left = Margin.ma_3
		style.content_margin_right = Margin.ma_3
		button.add_theme_stylebox_override(state, style)
