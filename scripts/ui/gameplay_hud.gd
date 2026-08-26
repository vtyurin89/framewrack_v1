class_name GameplayHUD
extends HBoxContainer
## In-game top bar: HP · Neuro-Chips · Experience · Body Grid · Combat Log · Menu.

signal menu_pressed
signal body_grid_pressed
signal combat_log_pressed
signal debug_inventory_requested
signal debug_act_jump_requested(act_index: int)

const HEART_ICON := preload("res://assets/icons/ui/heart.png")
const GEAR_ICON := preload("res://assets/icons/ui/gear.png")
const CHIP_ICON := preload("res://assets/icons/ui/neuro_chip.png")
const STATUS_MODAL_SCENE := preload("res://scenes/UI/debug_status_modal.tscn")
const ITEMS_MODAL_SCENE := preload("res://scenes/UI/debug_items_modal.tscn")
const ACT_MODAL_SCENE := preload("res://scenes/UI/debug_act_modal.tscn")
const STAT_CHECK_ROLL_SCENE := preload("res://scenes/UI/stat_check_roll_modal.tscn")

@onready var _hp_label: Label = %HpLabel
@onready var _heart_icon: TextureRect = %HeartIcon
@onready var _chip_label: SmoothCounter = %ChipLabel
@onready var _chip_icon: TextureRect = %ChipIcon
@onready var _btn_body: Button = %ToggleInventoryButton
@onready var _btn_combat_log: Button = %CombatLogButton
@onready var _btn_debug_cell_damage: Button = %DebugCellDamageButton
@onready var _btn_debug_status: Button = %DebugStatusButton
@onready var _btn_debug_items: Button = %DebugItemsButton
@onready var _btn_debug_act: Button = %DebugActButton
@onready var _btn_debug_stat_check: Button = %DebugStatCheckButton
@onready var _btn_menu: Button = %MenuButton
@onready var _level_label: Label = %LevelLabel
@onready var _xp_bar: ProgressBar = %XPBar

var _player_stats: PlayerStats
var _combat: Node
var _inventory: InventoryController
var _inventory_ui: Control
var _chips_initialized: bool = false
var _last_hp: int = 0
var _last_max_hp: int = 0
var _bound_statuses: StatusController
var _status_modal: DebugStatusModal
var _items_modal: DebugItemsModal
var _act_modal: DebugActModal
var _stat_check_modal: StatCheckRollModal
var _stat_check_busy: bool = false


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_BEGIN
	if _heart_icon:
		_heart_icon.texture = HEART_ICON
		_heart_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_heart_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_heart_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_heart_icon.modulate = GamePalette.PHOSPHOR_ACTIVE
	if _chip_icon:
		_chip_icon.texture = CHIP_ICON
		_chip_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_chip_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_chip_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_chip_icon.custom_minimum_size = Vector2(22, 22)
		_chip_icon.modulate = GamePalette.COLOR_CYAN_SYSTEM
	if _chip_label:
		_chip_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		GamePalette.apply_label_value(_chip_label)
	if _hp_label:
		_hp_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		GamePalette.apply_label_value(_hp_label)
	if _level_label:
		GamePalette.apply_label_primary(_level_label)
	if _btn_body:
		_btn_body.pressed.connect(func() -> void: body_grid_pressed.emit())
		GamePalette.apply_button_theme(_btn_body, 13)
	if _btn_combat_log:
		_btn_combat_log.pressed.connect(func() -> void: combat_log_pressed.emit())
		GamePalette.apply_button_theme(_btn_combat_log, 13)
	# TODO: удалить на продакшене
	_wire_debug_button(_btn_debug_cell_damage, _on_debug_cell_damage_pressed)
	_wire_debug_button(_btn_debug_status, _on_debug_status_pressed)
	_wire_debug_button(_btn_debug_items, _on_debug_items_pressed)
	_wire_debug_button(_btn_debug_act, _on_debug_act_pressed)
	_wire_debug_button(_btn_debug_stat_check, _on_debug_stat_check_pressed)
	if _btn_menu:
		_btn_menu.pressed.connect(func() -> void: menu_pressed.emit())
		_btn_menu.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_configure_menu_button()
	if _xp_bar:
		_xp_bar.add_theme_stylebox_override("background", GamePalette.make_progress_bg_stylebox())
		_xp_bar.add_theme_stylebox_override("fill", GamePalette.make_progress_fill_stylebox())
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


func bind_combat(combat: Node) -> void:
	_unbind_player_statuses()
	_combat = combat
	_bind_player_statuses()
	if not EventBus.combat_started.is_connected(_on_combat_started_for_hud):
		EventBus.combat_started.connect(_on_combat_started_for_hud)
	if not EventBus.combat_ended.is_connected(_on_combat_ended_for_hud):
		EventBus.combat_ended.connect(_on_combat_ended_for_hud)
	_refresh_hp_label()


func _on_combat_started_for_hud(_enemy_ids: Array) -> void:
	## player_statuses may be created/replaced at combat start.
	_unbind_player_statuses()
	_bind_player_statuses()
	_refresh_hp_label()


func _on_combat_ended_for_hud(_victory: bool) -> void:
	_refresh_hp_label()


func bind_inventory_ui(ui: Control) -> void:
	_inventory_ui = ui


func bind_inventory(inventory: InventoryController) -> void:
	_inventory = inventory
	if inventory == null:
		_on_hp_changed(0, 0)
		return
	_on_hp_changed(inventory.current_hp, inventory.max_hp)
	if GameManager != null:
		_on_chips_changed(GameManager.get_chips())


func _bind_player_statuses() -> void:
	if _combat == null:
		return
	var statuses = _combat.get("player_statuses")
	if statuses == null or not (statuses is StatusController):
		return
	_bound_statuses = statuses as StatusController
	if not _bound_statuses.statuses_updated.is_connected(_on_player_statuses_updated):
		_bound_statuses.statuses_updated.connect(_on_player_statuses_updated)


func _unbind_player_statuses() -> void:
	if _bound_statuses != null and is_instance_valid(_bound_statuses):
		if _bound_statuses.statuses_updated.is_connected(_on_player_statuses_updated):
			_bound_statuses.statuses_updated.disconnect(_on_player_statuses_updated)
	_bound_statuses = null


func _on_player_statuses_updated(_active_statuses: Array) -> void:
	_refresh_hp_label()


func _is_player_hacked() -> bool:
	if _combat == null:
		return false
	var statuses = _combat.get("player_statuses")
	if statuses == null:
		return false
	return statuses.has_method("has_status") and bool(statuses.has_status("hacked"))


func _refresh_hp_label() -> void:
	if _hp_label == null:
		return
	if _is_player_hacked():
		_hp_label.text = "?/?"
	else:
		_hp_label.text = "%d/%d" % [maxi(_last_hp, 0), maxi(_last_max_hp, 0)]


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
	_btn_menu.modulate = GamePalette.CRT_TEXT_MAIN


func _apply_debug_button_theme(btn: Button) -> void:
	## Phosphor CTA: bright outline, dark fill, muted-green hover.
	if btn == null:
		return
	var bright := GamePalette.PHOSPHOR_BRIGHT
	var fill := GamePalette.PANEL_BG_ALT
	var hover_fill := GamePalette.MUTED_GREEN
	var pressed_fill := GamePalette.INACTIVE_ELEMENT
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", GamePalette.PHOSPHOR_ACTIVE)
	btn.add_theme_color_override("font_hover_color", bright)
	btn.add_theme_color_override("font_pressed_color", bright)
	btn.add_theme_color_override("font_focus_color", bright)
	btn.add_theme_color_override("font_disabled_color", GamePalette.INACTIVE_ELEMENT)
	btn.add_theme_stylebox_override("normal", _make_level_up_style(fill, bright, false))
	btn.add_theme_stylebox_override("hover", _make_level_up_style(hover_fill, bright, true))
	btn.add_theme_stylebox_override("pressed", _make_level_up_style(pressed_fill, bright, false))
	btn.add_theme_stylebox_override("focus", _make_level_up_style(hover_fill, bright, true))
	btn.add_theme_stylebox_override(
		"disabled",
		_make_level_up_style(Color(fill.r, fill.g, fill.b, 0.85), GamePalette.INACTIVE_ELEMENT, false)
	)
	GamePalette.apply_phosphor_glow(btn, true)


func _make_level_up_style(bg: Color, border: Color, with_glow: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	if with_glow:
		style.shadow_color = Color(border.r, border.g, border.b, 0.35)
		style.shadow_size = 5
		style.shadow_offset = Vector2.ZERO
	else:
		style.shadow_size = 0
	return style


func _apply_locale(_locale: String = "") -> void:
	if _btn_body:
		_btn_body.text = tr("KEY_BODY_GRID")
	if _btn_combat_log:
		_btn_combat_log.text = tr("KEY_COMBAT_LOG")
	if _btn_menu:
		_btn_menu.text = ""
		_btn_menu.tooltip_text = tr("KEY_MENU")
	if _btn_debug_cell_damage:
		_btn_debug_cell_damage.text = tr("KEY_DEBUG_CELL_DAMAGE").to_upper()
	if _btn_debug_status:
		_btn_debug_status.text = tr("KEY_DEBUG_STATUS").to_upper()
	if _btn_debug_items:
		_btn_debug_items.text = tr("KEY_DEBUG_ITEMS").to_upper()
	if _btn_debug_act:
		_btn_debug_act.text = tr("KEY_DEBUG_ACT").to_upper()
	if _btn_debug_stat_check:
		_btn_debug_stat_check.text = tr("KEY_DEBUG_STAT_CHECK").to_upper()
	if _chip_label:
		_chip_label.tooltip_text = tr("KEY_NEURO_CHIPS")
	if _chip_icon:
		_chip_icon.tooltip_text = tr("KEY_NEURO_CHIPS")
	_refresh_level_xp()


func _on_hp_changed(current: int, maximum: int) -> void:
	_last_hp = maxi(current, 0)
	_last_max_hp = maxi(maximum, 0)
	_refresh_hp_label()


func _on_chips_changed(amount: int) -> void:
	if _chip_label == null:
		return
	var target := maxi(amount, 0)
	if not _chips_initialized:
		_chip_label.set_value_instant(target)
		_chips_initialized = true
		return
	_chip_label.set_value_animated(target)


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


func _wire_debug_button(btn: Button, handler: Callable) -> void:
	if btn == null:
		return
	btn.add_to_group("debug_ui")
	btn.pressed.connect(handler)
	btn.visible = not GameSettings.hide_debug_tools
	_apply_debug_button_theme(btn)


func _on_debug_cell_damage_pressed() -> void:
	if _combat == null or not _combat.has_method("apply_cell_damage"):
		return
	_combat.call("apply_cell_damage", Vector2i(-1, -1), ItemStatus.Type.OVERLOAD, 2)


func _on_debug_status_pressed() -> void:
	_ensure_status_modal()
	if _status_modal:
		_status_modal.open_for_combat(_combat)
		_unbind_player_statuses()
		_bind_player_statuses()
		_refresh_hp_label()


func _on_debug_items_pressed() -> void:
	_ensure_items_modal()
	if _items_modal:
		_items_modal.open_catalog(_inventory_ui)


func _on_debug_act_pressed() -> void:
	_ensure_act_modal()
	if _act_modal:
		_act_modal.open_picker()


func _on_debug_stat_check_pressed() -> void:
	if _stat_check_busy:
		return
	if StatCheckManager == null:
		return
	var dice := randi_range(2, 8)
	var threshold := randi_range(1, 4)
	var result := StatCheckManager.perform_check(dice, threshold, 0)
	var modal := _ensure_stat_check_modal()
	if modal == null or result == null:
		return
	_stat_check_busy = true
	await modal.present(result, "STR", threshold)
	_stat_check_busy = false


func _ensure_status_modal() -> void:
	if _status_modal != null and is_instance_valid(_status_modal):
		return
	_status_modal = STATUS_MODAL_SCENE.instantiate() as DebugStatusModal
	_status_modal.status_applied.connect(_on_debug_status_applied)
	UiOverlayLayer.mount(_status_modal, self)


func _on_debug_status_applied() -> void:
	_unbind_player_statuses()
	_bind_player_statuses()
	_refresh_hp_label()


func _ensure_items_modal() -> void:
	if _items_modal != null and is_instance_valid(_items_modal):
		return
	_items_modal = ITEMS_MODAL_SCENE.instantiate() as DebugItemsModal
	_items_modal.inventory_open_requested.connect(func() -> void: debug_inventory_requested.emit())
	UiOverlayLayer.mount(_items_modal, self)


func _ensure_act_modal() -> void:
	if _act_modal != null and is_instance_valid(_act_modal):
		return
	_act_modal = ACT_MODAL_SCENE.instantiate() as DebugActModal
	_act_modal.act_selected.connect(func(act_index: int) -> void: debug_act_jump_requested.emit(act_index))
	UiOverlayLayer.mount(_act_modal, self)


func _ensure_stat_check_modal() -> StatCheckRollModal:
	if _stat_check_modal != null and is_instance_valid(_stat_check_modal):
		return _stat_check_modal
	_stat_check_modal = STAT_CHECK_ROLL_SCENE.instantiate() as StatCheckRollModal
	_stat_check_modal.name = "DebugStatCheckRollModal"
	return _stat_check_modal
