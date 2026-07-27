class_name MainMenuUI
extends Control
## Simple main menu overlay: Start Game / Exit.

signal start_pressed
signal exit_pressed

@onready var _title: Label = %TitleLabel
@onready var _tagline: Label = %TaglineLabel
@onready var _start_btn: Button = %StartButton
@onready var _exit_btn: Button = %ExitButton


func _ready() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_start_btn.pressed.connect(func() -> void: start_pressed.emit())
	_exit_btn.pressed.connect(func() -> void: exit_pressed.emit())
	_start_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_exit_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not LocalizationManager.language_changed.is_connected(_apply_locale):
		LocalizationManager.language_changed.connect(_apply_locale)
	_apply_locale()


func show_menu() -> void:
	_apply_locale()
	visible = true
	move_to_front()


func hide_menu() -> void:
	visible = false


func _apply_locale(_locale: String = "") -> void:
	_title.text = "FRAMEWRACK"
	_tagline.text = tr("KEY_MAIN_MENU_TAGLINE")
	_start_btn.text = tr("KEY_START_GAME")
	_exit_btn.text = tr("KEY_EXIT")
