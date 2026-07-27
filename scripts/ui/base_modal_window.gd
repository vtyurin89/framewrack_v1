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
	## Slightly brighter on hover so the hit target feels clickable.
	_close_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	_close_btn.add_theme_color_override("font_color", Color(0.82, 0.82, 0.85))
	_close_btn.add_theme_color_override("font_pressed_color", Color(0.7, 0.7, 0.75))


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
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.13, 1)
	style.set_border_width_all(1)
	style.border_color = Color(0.4, 0.4, 0.45)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(0)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 12
	_dialog.add_theme_stylebox_override("panel", style)
