class_name GameplayHUD
extends HBoxContainer
## In-game top bar actions: Body Grid / Mutate / New Run / Menu.
## Language lives in Settings — not here.

signal menu_pressed
signal body_grid_pressed
signal mutate_pressed
signal new_run_pressed

@onready var _btn_body: Button = %ToggleInventoryButton
@onready var _btn_mutate: Button = %ExpandGridButton
@onready var _btn_new_run: Button = %NewRunButton
@onready var _btn_menu: Button = %MenuButton


func _ready() -> void:
	if _btn_body:
		_btn_body.pressed.connect(func() -> void: body_grid_pressed.emit())
	if _btn_mutate:
		_btn_mutate.pressed.connect(func() -> void: mutate_pressed.emit())
	if _btn_new_run:
		_btn_new_run.pressed.connect(func() -> void: new_run_pressed.emit())
	if _btn_menu:
		_btn_menu.pressed.connect(func() -> void: menu_pressed.emit())
		_btn_menu.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not LocalizationManager.language_changed.is_connected(_apply_locale):
		LocalizationManager.language_changed.connect(_apply_locale)
	_apply_locale()


func _apply_locale(_locale: String = "") -> void:
	if _btn_body:
		_btn_body.text = tr("KEY_BODY_GRID")
	if _btn_mutate:
		_btn_mutate.text = tr("KEY_MUTATE_CELLS")
	if _btn_new_run:
		_btn_new_run.text = tr("KEY_NEW_RUN")
	if _btn_menu:
		_btn_menu.text = tr("KEY_MENU")
