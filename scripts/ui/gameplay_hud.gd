class_name GameplayHUD
extends HBoxContainer
## In-game top bar: HP · Neuro-Chips · Experience · Body Grid · Combat Log · Menu.

signal menu_pressed
signal body_grid_pressed
signal combat_log_pressed

const HEART_ICON := preload("res://assets/icons/ui/heart.png")
const GEAR_ICON := preload("res://assets/icons/ui/gear.png")
const CHIP_ICON := preload("res://assets/icons/ui/neuro_chip.png")

@onready var _hp_label: Label = %HpLabel
@onready var _heart_icon: TextureRect = %HeartIcon
@onready var _chip_label: Label = %ChipLabel
@onready var _chip_icon: TextureRect = %ChipIcon
@onready var _btn_body: Button = %ToggleInventoryButton
@onready var _btn_combat_log: Button = %CombatLogButton
@onready var _btn_debug_level_up: Button = %DebugLevelUpButton
@onready var _btn_menu: Button = %MenuButton
@onready var _level_label: Label = %LevelLabel
@onready var _xp_bar: ProgressBar = %XPBar

var _player_stats: PlayerStats


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_BEGIN
	if _heart_icon:
		_heart_icon.texture = HEART_ICON
		_heart_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_heart_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_heart_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _chip_icon:
		_chip_icon.texture = CHIP_ICON
		_chip_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_chip_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_chip_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_chip_icon.custom_minimum_size = Vector2(22, 22)
	if _chip_label:
		_chip_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _hp_label:
		_hp_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _btn_body:
		_btn_body.pressed.connect(func() -> void: body_grid_pressed.emit())
	if _btn_combat_log:
		_btn_combat_log.pressed.connect(func() -> void: combat_log_pressed.emit())
	# TODO: удалить на продакшене
	if _btn_debug_level_up:
		_btn_debug_level_up.add_to_group("debug_ui")
		_btn_debug_level_up.pressed.connect(_on_debug_level_up_pressed)
		_btn_debug_level_up.visible = not GameSettings.hide_debug_tools
	if _btn_menu:
		_btn_menu.pressed.connect(func() -> void: menu_pressed.emit())
		_btn_menu.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_configure_menu_button()
	if not LocalizationManager.language_changed.is_connected(_apply_locale):
		LocalizationManager.language_changed.connect(_apply_locale)
	if not EventBus.player_hp_changed.is_connected(_on_hp_changed):
		EventBus.player_hp_changed.connect(_on_hp_changed)
	if GameManager != null and not GameManager.chips_changed.is_connected(_on_chips_changed):
		GameManager.chips_changed.connect(_on_chips_changed)
		_on_chips_changed(GameManager.get_chips())
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


func bind_inventory(inventory: InventoryController) -> void:
	if inventory == null:
		_on_hp_changed(0, 0)
		return
	_on_hp_changed(inventory.current_hp, inventory.max_hp)
	if GameManager != null:
		_on_chips_changed(GameManager.get_chips())


func _configure_menu_button() -> void:
	if _btn_menu == null:
		return
	_btn_menu.text = ""
	_btn_menu.icon = GEAR_ICON
	_btn_menu.expand_icon = true
	_btn_menu.custom_minimum_size = Vector2(36, 32)
	_btn_menu.add_theme_constant_override("icon_max_width", 22)
	_btn_menu.flat = true
	_btn_menu.focus_mode = Control.FOCUS_NONE


func _apply_locale(_locale: String = "") -> void:
	if _btn_body:
		_btn_body.text = tr("KEY_BODY_GRID")
	if _btn_combat_log:
		_btn_combat_log.text = tr("KEY_COMBAT_LOG")
	if _btn_menu:
		_btn_menu.text = ""
		_btn_menu.tooltip_text = tr("KEY_MENU")
	if _btn_debug_level_up:
		_btn_debug_level_up.text = tr("KEY_DEBUG_LEVEL_UP")
	if _chip_label:
		_chip_label.tooltip_text = tr("KEY_NEURO_CHIPS")
	if _chip_icon:
		_chip_icon.tooltip_text = tr("KEY_NEURO_CHIPS")
	_refresh_level_xp()


func _on_hp_changed(current: int, maximum: int) -> void:
	if _hp_label == null:
		return
	_hp_label.text = "%d/%d" % [maxi(current, 0), maxi(maximum, 0)]


func _on_chips_changed(amount: int) -> void:
	if _chip_label == null:
		return
	_chip_label.text = str(maxi(amount, 0))


func _on_exp_changed(
	level: int,
	current_exp: int,
	level_start_exp: int,
	next_level_exp: int,
	max_level: int
) -> void:
	var exp_in_level := maxi(0, current_exp - level_start_exp)
	var needed_exp := maxi(1, next_level_exp - level_start_exp)
	if _level_label:
		if level >= max_level:
			_level_label.text = tr("KEY_EXPERIENCE_MAX")
		else:
			_level_label.text = tr("KEY_EXPERIENCE_FMT") % [exp_in_level, needed_exp]
	if _xp_bar:
		_xp_bar.min_value = 0.0
		_xp_bar.max_value = float(needed_exp)
		_xp_bar.value = float(exp_in_level)
		if level >= max_level:
			_xp_bar.value = _xp_bar.max_value


func _refresh_level_xp() -> void:
	if _player_stats == null:
		if _level_label:
			_level_label.text = tr("KEY_EXPERIENCE_FMT") % [0, 30]
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


func _on_debug_level_up_pressed() -> void:
	if _player_stats == null:
		return
	var needed_xp := _player_stats.max_exp - _player_stats.current_exp
	_player_stats.add_exp(maxi(needed_xp, 1))
