class_name GameplayHUD
extends HBoxContainer
## In-game top bar actions: Body Grid / Menu.
## Language lives in Settings — not here.

signal menu_pressed
signal body_grid_pressed

@onready var _btn_body: Button = %ToggleInventoryButton
@onready var _btn_menu: Button = %MenuButton
@onready var _level_label: Label = %LevelLabel
@onready var _xp_bar: ProgressBar = %XPBar

var _player_stats: PlayerStats


func _ready() -> void:
	if _btn_body:
		_btn_body.pressed.connect(func() -> void: body_grid_pressed.emit())
	if _btn_menu:
		_btn_menu.pressed.connect(func() -> void: menu_pressed.emit())
		_btn_menu.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not LocalizationManager.language_changed.is_connected(_apply_locale):
		LocalizationManager.language_changed.connect(_apply_locale)
	_apply_locale()
	_refresh_level_xp()


func bind_player_stats(stats: PlayerStats) -> void:
	if _player_stats != null and _player_stats.exp_changed.is_connected(_on_exp_changed):
		_player_stats.exp_changed.disconnect(_on_exp_changed)
	_player_stats = stats
	if _player_stats != null:
		_player_stats.exp_changed.connect(_on_exp_changed)
		_on_exp_changed(
			_player_stats.level,
			_player_stats.current_exp,
			_player_stats.get_current_level_start_exp(),
			_player_stats.get_next_level_exp(),
			PlayerStats.MAX_LEVEL
		)
	else:
		_refresh_level_xp()


func _apply_locale(_locale: String = "") -> void:
	if _btn_body:
		_btn_body.text = tr("KEY_BODY_GRID")
	if _btn_menu:
		_btn_menu.text = tr("KEY_MENU")
	_refresh_level_xp()


func _on_exp_changed(
	level: int,
	current_exp: int,
	level_start_exp: int,
	next_level_exp: int,
	max_level: int
) -> void:
	if _level_label:
		_level_label.text = tr("KEY_LEVEL_FMT") % [level, max_level]
	if _xp_bar:
		_xp_bar.min_value = float(level_start_exp)
		_xp_bar.max_value = float(maxi(next_level_exp, level_start_exp + 1))
		_xp_bar.value = float(current_exp)
		if level >= max_level:
			_xp_bar.value = _xp_bar.max_value


func _refresh_level_xp() -> void:
	if _player_stats == null:
		if _level_label:
			_level_label.text = tr("KEY_LEVEL_FMT") % [1, PlayerStats.MAX_LEVEL]
		if _xp_bar:
			_xp_bar.min_value = 0.0
			_xp_bar.max_value = 30.0
			_xp_bar.value = 0.0
		return
	_on_exp_changed(
		_player_stats.level,
		_player_stats.current_exp,
		_player_stats.get_current_level_start_exp(),
		_player_stats.get_next_level_exp(),
		PlayerStats.MAX_LEVEL
	)
