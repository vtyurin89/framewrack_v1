class_name GameOverUI
extends Control
## Full-screen game over overlay: SYSTEM FAILURE + Restart / Main Menu.

signal restart_pressed
signal main_menu_pressed

@onready var _title: Label = %TitleLabel
@onready var _subtitle: Label = %SubtitleLabel
@onready var _restart_btn: Button = %RestartButton
@onready var _menu_btn: Button = %MainMenuButton


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_restart_btn.pressed.connect(_on_restart)
	_menu_btn.pressed.connect(_on_main_menu)
	_restart_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_menu_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_panel()
	if not LocalizationManager.language_changed.is_connected(_apply_locale):
		LocalizationManager.language_changed.connect(_apply_locale)
	_apply_locale()


func _style_panel() -> void:
	var panel := get_node_or_null("Center/Panel") as PanelContainer
	if panel == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.11, 1)
	style.set_border_width_all(1)
	style.border_color = Color(0.55, 0.2, 0.22)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", style)


func show_game_over() -> void:
	_apply_locale()
	visible = true
	move_to_front()


func hide_game_over() -> void:
	visible = false


func _apply_locale(_locale: String = "") -> void:
	_title.text = tr("KEY_GAME_OVER_TITLE")
	var reason_key: String = GameManager.get_game_over_reason_key()
	_subtitle.text = tr(reason_key)
	_restart_btn.text = tr("KEY_RESTART")
	_menu_btn.text = tr("KEY_MAIN_MENU")
	if _title:
		GamePalette.apply_font_emphasis(_title)
	if _subtitle:
		GamePalette.apply_font_header(_subtitle)
	GamePalette.apply_button_theme(_restart_btn, 16)
	GamePalette.apply_button_theme(_menu_btn, 16)


func _on_restart() -> void:
	restart_pressed.emit()


func _on_main_menu() -> void:
	main_menu_pressed.emit()
