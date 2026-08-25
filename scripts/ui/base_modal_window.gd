class_name BaseModalWindow
extends Control
## Reusable full-screen modal shell with dim overlay, ESC / X close, and a
## content slot (`%ContentContainer`) for child UI injection.

signal opened
signal closed

@onready var _overlay: ColorRect = %Overlay
@onready var _dialog: PanelContainer = %Dialog
@onready var _close_btn: Button = %CloseButton
@onready var content_container: Control = %ContentContainer

var _is_open: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(false)
	if _close_btn:
		_close_btn.pressed.connect(close)
		_style_close_button()
	if _overlay:
		_overlay.gui_input.connect(_on_overlay_gui_input)
	_style_dialog()


func _style_close_button() -> void:
	_close_btn.custom_minimum_size = Vector2(44, 40)
	_close_btn.add_theme_font_size_override("font_size", 22)
	_close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.add_theme_color_override("font_hover_color", GamePalette.PHOSPHOR_BRIGHT)
	_close_btn.add_theme_color_override("font_color", GamePalette.CRT_TEXT_MAIN)
	_close_btn.add_theme_color_override("font_pressed_color", GamePalette.PHOSPHOR_ACTIVE)


func is_open() -> bool:
	return _is_open


func open() -> void:
	visible = true
	_is_open = true
	set_process_unhandled_input(true)
	move_to_front()
	opened.emit()


func close() -> void:
	if not _is_open and not visible:
		return
	_is_open = false
	visible = false
	set_process_unhandled_input(false)
	closed.emit()


func clear_content() -> void:
	if content_container == null:
		return
	for child in content_container.get_children():
		child.queue_free()


func set_content(node: Control) -> void:
	clear_content()
	if node == null or content_container == null:
		return
	content_container.add_child(node)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_overlay_gui_input(event: InputEvent) -> void:
	## Clicking the dim backdrop also dismisses the modal.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


func _style_dialog() -> void:
	if _dialog == null:
		return
	var style := GamePalette.make_panel_stylebox(
		GamePalette.PANEL_BG, GamePalette.MUTED_GREEN, 1, 0, 0.0, false
	)
	_dialog.add_theme_stylebox_override("panel", style)
	if _overlay:
		_overlay.color = Color(
			GamePalette.BACKGROUND_DARK.r,
			GamePalette.BACKGROUND_DARK.g,
			GamePalette.BACKGROUND_DARK.b,
			0.75
		)
