class_name MainMenuUI
extends Control
## Main menu overlay: Continue / New Game / Settings / Exit.

signal continue_pressed
signal new_game_pressed
signal settings_pressed
signal exit_pressed

@onready var _title: Label = %TitleLabel
@onready var _tagline: Label = %TaglineLabel
@onready var _continue_btn: Button = %ContinueButton
@onready var _new_game_btn: Button = %NewGameButton
@onready var _settings_btn: Button = %SettingsButton
@onready var _exit_btn: Button = %ExitButton


func _ready() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_continue_btn.pressed.connect(func() -> void: continue_pressed.emit())
	_new_game_btn.pressed.connect(func() -> void: new_game_pressed.emit())
	_settings_btn.pressed.connect(func() -> void: settings_pressed.emit())
	_exit_btn.pressed.connect(func() -> void: exit_pressed.emit())
	for btn: Button in [_continue_btn, _new_game_btn, _settings_btn, _exit_btn]:
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not LocalizationManager.language_changed.is_connected(_apply_locale):
		LocalizationManager.language_changed.connect(_apply_locale)
	_apply_locale()
	refresh_continue_visibility()


func show_menu() -> void:
	_apply_locale()
	refresh_continue_visibility()
	visible = true
	move_to_front()


func hide_menu() -> void:
	visible = false


func refresh_continue_visibility() -> void:
	var can_continue: bool = GameManager.is_session_active
	_continue_btn.visible = can_continue
	_continue_btn.disabled = not can_continue


func _apply_locale(_locale: String = "") -> void:
	_title.text = "FRAMEWRACK"
	_tagline.text = tr("KEY_MAIN_MENU_TAGLINE")
	_continue_btn.text = tr("KEY_CONTINUE")
	_new_game_btn.text = tr("KEY_NEW_GAME")
	_settings_btn.text = tr("KEY_SETTINGS")
	_exit_btn.text = tr("KEY_EXIT")
	refresh_continue_visibility()
