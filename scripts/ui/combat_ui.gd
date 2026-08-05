extends Control
## Combat HUD: enemies (click to select), intentions, AP/HP/Block, log, End Turn.
## Item activation happens via inventory clicks (Backpack Hero model).

signal end_turn_pressed
signal target_selected(index: int)
signal continue_pressed

const ENEMY_INSPECT_SCENE := preload("res://scenes/UI/enemy_inspect_ui.tscn")
const ENEMY_CARD_SCENE := preload("res://scenes/UI/enemy_card_ui.tscn")
const STATUS_EFFECTS_SCENE := preload("res://scenes/UI/status_effects_ui.tscn")
const INTENTION_STAGGER_DELAY := 0.15

const AP_FLASH_SPEND := Color(0.75, 0.95, 1.0)
const AP_FLASH_DENY := Color(1.0, 0.25, 0.25)
const BLOCK_FLASH_GAIN := Color("3498db")

var combat: Node  # CombatManager
var inventory: InventoryController
var _enemy_inspect: EnemyInspectUI
var _enemy_context_menu: EnemyContextMenuUI
var _intention_reveal_token: int = 0
var _dying_indices: Dictionary = {}  # index -> true while fade in progress
var _player_statuses_ui: StatusEffectsUI
var _player_hp_initialized: bool = false
var _last_ap: int = -1
var _last_block: int = -1
var _ap_base_color: Color = Color(0.95, 0.95, 0.97)
var _block_base_color: Color = Color(0.88, 0.88, 0.92)
var _ap_juice_tween: Tween
var _block_juice_tween: Tween

@onready var _enemy_row: HBoxContainer = %EnemyRow
@onready var _loot_stage: Control = %LootStage
@onready var _stats_enemy_gap: Control = %StatsEnemyGap
@onready var _enemy_actions_gap: Control = %EnemyActionsGap
@onready var _hp_label: Label = %HPLabel
@onready var _ap_label: Label = %APLabel
@onready var _block_label: Label = %BlockLabel
@onready var _turn_label: Label = %TurnLabel
@onready var _log: RichTextLabel = %CombatLog
@onready var _log_modal: Control = %CombatLogModal
@onready var _log_panel: PanelContainer = %LogPanel
@onready var _log_title: Label = %LogTitle
@onready var _close_log_btn: Button = %CloseLogButton
@onready var _end_turn_btn: Button = %EndTurnButton
@onready var _continue_btn: Button = %ContinueButton
@onready var _hint_label: Label = %CombatHint
@onready var _player_status_host: HBoxContainer = %PlayerStatuses
@onready var _player_hp_bar: GhostProgressBar = %PlayerHPBar
@onready var _stats_row: HBoxContainer = $VBox/StatsRow

var _reward_phase: bool = false
var _harmful_insertion_phase: bool = false


func _ready() -> void:
	_end_turn_btn.pressed.connect(func() -> void: end_turn_pressed.emit())
	_continue_btn.pressed.connect(func() -> void: continue_pressed.emit())
	_continue_btn.visible = false
	if _close_log_btn:
		_close_log_btn.pressed.connect(hide_combat_log)
		_close_log_btn.tooltip_text = tr("KEY_CLOSE")
		_close_log_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_log_panel()
	_configure_log_scroll()
	_style_action_buttons()
	hide_combat_log()
	EventBus.ap_changed.connect(_on_ap_changed)
	EventBus.ap_insufficient.connect(_on_ap_insufficient)
	EventBus.player_hp_changed.connect(_on_hp_changed)
	EventBus.block_changed.connect(_on_block_changed)
	EventBus.combat_log_message.connect(_on_log)
	EventBus.enemy_hp_changed.connect(_on_enemy_hp)
	EventBus.enemy_selected.connect(_on_enemy_selected)
	EventBus.enemy_roster_changed.connect(_rebuild_enemies)
	EventBus.combat_started.connect(_on_combat_started)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.enemy_combat_text.connect(_on_enemy_combat_text)
	EventBus.enemy_intention_changed.connect(_on_enemy_intention_changed)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.damage_popup_requested.connect(_on_damage_popup_requested)
	LocalizationManager.language_changed.connect(_on_language_changed)
	_apply_static_locale()
	_bind_damage_popup_manager()
	_prepare_stat_juice_hosts()


func setup(p_combat: Node, p_inventory: InventoryController) -> void:
	combat = p_combat
	inventory = p_inventory
	_log.clear()
	_reward_phase = false
	_harmful_insertion_phase = false
	if _loot_stage:
		_loot_stage.visible = false
	_continue_btn.visible = false
	_continue_btn.disabled = false
	_continue_btn.text = tr("KEY_CONTINUE")
	_end_turn_btn.visible = true
	_end_turn_btn.disabled = false
	_dying_indices.clear()
	_player_hp_initialized = false
	_apply_static_locale()
	_on_hp_changed(inventory.current_hp, inventory.max_hp)
	_ensure_player_statuses_ui()
	_bind_damage_popup_manager()
	_rebuild_enemies()


func _bind_damage_popup_manager() -> void:
	if DamagePopUpManager == null:
		return
	var anchor: Control = _player_hp_bar if _player_hp_bar != null else _stats_row
	if anchor == null:
		anchor = _hp_label
	DamagePopUpManager.set_player_anchor(anchor)
	DamagePopUpManager.set_enemy_resolver(Callable(self, "_resolve_enemy_popup_target"))


func _resolve_enemy_popup_target(enemy_index: int) -> Control:
	var card := _find_card_by_index(enemy_index)
	if card == null:
		return null
	## Prefer the card body (stable size) over the thin CombatTextHost strip.
	return card


func _on_damage_popup_requested(
	target_kind: String,
	enemy_index: int,
	amount: int,
	damage_type: String,
	is_crit: bool,
	is_miss: bool
) -> void:
	if target_kind == "enemy" and not is_miss:
		var card := _find_card_by_index(enemy_index)
		if card != null and card.has_method("play_hit_fx"):
			card.play_hit_fx(is_crit)
	if DamagePopUpManager == null:
		return
	match target_kind:
		"enemy":
			DamagePopUpManager.queue_enemy_damage(enemy_index, amount, damage_type, is_crit, is_miss)
		"player":
			## Player popups temporarily disabled (stub kept in DamagePopUpManager).
			DamagePopUpManager.queue_player_damage(amount, damage_type, is_crit, is_miss)


func _ensure_player_statuses_ui() -> void:
	if _player_status_host == null:
		return
	if _player_statuses_ui == null or not is_instance_valid(_player_statuses_ui):
		for child in _player_status_host.get_children():
			child.queue_free()
		_player_statuses_ui = STATUS_EFFECTS_SCENE.instantiate() as StatusEffectsUI
		_player_status_host.add_child(_player_statuses_ui)
	if combat != null and combat.get("player_statuses") != null:
		_player_statuses_ui.bind_controller(combat.player_statuses as StatusController)
	else:
		_player_statuses_ui.unbind()


func _on_language_changed(_locale: String) -> void:
	_apply_static_locale()
	if inventory:
		_on_hp_changed(inventory.current_hp, inventory.max_hp)
	if combat:
		_on_ap_changed(combat.current_ap, combat.max_ap)
		_on_block_changed(combat.current_block)
		_rebuild_enemies()
		if combat.state == combat.CombatState.PLAYER_TURN:
			_turn_label.text = tr("KEY_PLAYER_TURN")
		elif combat.state == combat.CombatState.ENEMY_TURN:
			_turn_label.text = tr("KEY_ENEMY_TURN")
		elif combat.state == combat.CombatState.VICTORY:
			_turn_label.text = tr("KEY_VICTORY")
			_continue_btn.text = tr("KEY_CONTINUE")
		elif combat.state == combat.CombatState.DEFEAT:
			_turn_label.text = tr("KEY_FRAME_FAILURE")
			_continue_btn.text = tr("KEY_RETURN_TO_MAP")


func _apply_static_locale() -> void:
	_end_turn_btn.text = tr("KEY_END_TURN")
	if _hint_label:
		_hint_label.text = tr("KEY_COMBAT_CLICK_HINT")
	if _log_title:
		_log_title.text = tr("KEY_COMBAT_LOG")
	if _close_log_btn:
		_close_log_btn.tooltip_text = tr("KEY_CLOSE")


func is_combat_log_open() -> bool:
	return _log_modal != null and _log_modal.visible


func toggle_combat_log() -> void:
	if is_combat_log_open():
		hide_combat_log()
	else:
		show_combat_log()


func show_combat_log() -> void:
	if _log_modal == null:
		return
	_log_modal.visible = true
	_scroll_log_to_end()


func hide_combat_log() -> void:
	if _log_modal == null:
		return
	_log_modal.visible = false


func _style_log_panel() -> void:
	if _log_panel == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.96)
	style.set_border_width_all(1)
	style.border_color = Color(0.42, 0.42, 0.48, 1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 8
	_log_panel.add_theme_stylebox_override("panel", style)


func _configure_log_scroll() -> void:
	if _log == null:
		return
	_log.bbcode_enabled = true
	_log.fit_content = false
	_log.scroll_active = true
	_log.scroll_following = true
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.custom_minimum_size.y = 160.0


func _style_action_buttons() -> void:
	_apply_primary_action_style(_end_turn_btn)
	_apply_primary_action_style(_continue_btn)


func _apply_primary_action_style(btn: Button) -> void:
	if btn == null:
		return
	btn.custom_minimum_size = Vector2(220, 52)
	btn.add_theme_font_size_override("font_size", 18)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.1, 0.12, 1)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.92, 0.55, 0.18, 1)
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(10)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16, 0.14, 0.12, 1)
	hover.border_color = Color(1.0, 0.7, 0.28, 1)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.08, 0.08, 0.09, 1)
	pressed.border_color = Color(0.75, 0.42, 0.12, 1)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.08, 0.08, 0.09, 0.7)
	disabled.border_color = Color(0.4, 0.35, 0.28, 0.8)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", hover)


func _ensure_enemy_inspect() -> void:
	if _enemy_inspect != null and is_instance_valid(_enemy_inspect):
		return
	_enemy_inspect = ENEMY_INSPECT_SCENE.instantiate() as EnemyInspectUI
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	host.add_child(_enemy_inspect)


func _rebuild_enemies() -> void:
	_intention_reveal_token += 1
	_dying_indices.clear()
	for child in _enemy_row.get_children():
		child.queue_free()
	if combat == null:
		return
	## Only show living enemies — corpses are purged after death fade.
	for i in combat.enemies.size():
		var enemy: EnemyInstance = combat.enemies[i]
		if enemy == null or not enemy.is_alive():
			continue
		var card: EnemyCardUI = ENEMY_CARD_SCENE.instantiate() as EnemyCardUI
		_enemy_row.add_child(card)
		card.setup(enemy, i, enemy.is_selected)
		card.card_gui_input.connect(_on_enemy_panel_input)
		card.death_fade_finished.connect(_on_card_death_fade_finished)
		if combat.state == combat.CombatState.ENEMY_TURN:
			card.set_intentions_hidden(true)
		elif enemy.current_intention != null:
			card.set_intention(enemy.current_intention)


func _find_card_by_index(index: int) -> EnemyCardUI:
	for child in _enemy_row.get_children():
		var card := child as EnemyCardUI
		if card != null and card.enemy_index == index and is_instance_valid(card):
			return card
	## Fallback: positional match while indices still align with row order.
	if index >= 0 and index < _enemy_row.get_child_count():
		return _enemy_row.get_child(index) as EnemyCardUI
	return null


func _find_card_by_enemy(enemy: EnemyInstance) -> EnemyCardUI:
	if enemy == null:
		return null
	for child in _enemy_row.get_children():
		var card := child as EnemyCardUI
		if card != null and card.get_enemy() == enemy:
			return card
	return null


func _sync_card_indices() -> void:
	if combat == null:
		return
	for child in _enemy_row.get_children():
		var card := child as EnemyCardUI
		if card == null:
			continue
		var enemy := card.get_enemy()
		if enemy == null:
			continue
		card.enemy_index = combat.enemies.find(enemy)


func _on_enemy_panel_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _enemy_context_menu and _enemy_context_menu.is_open():
				_enemy_context_menu.close()
			target_selected.emit(index)
			_on_log(tr("KEY_LOG_TARGETING") % (index + 1))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_open_enemy_context_menu(index, event.global_position)


func _open_enemy_context_menu(index: int, global_pos: Vector2) -> void:
	if combat == null or index < 0 or index >= combat.enemies.size():
		return
	var enemy: EnemyInstance = combat.enemies[index]
	if enemy == null or not enemy.is_alive():
		return
	_ensure_enemy_context_menu()
	if _enemy_context_menu:
		_enemy_context_menu.open_for_enemy(enemy, global_pos)


func _ensure_enemy_context_menu() -> void:
	if _enemy_context_menu != null and is_instance_valid(_enemy_context_menu):
		return
	_enemy_context_menu = EnemyContextMenuUI.new()
	_enemy_context_menu.name = "EnemyContextMenuUI"
	_enemy_context_menu.inspect_pressed.connect(_on_enemy_context_inspect_pressed)
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	host.add_child(_enemy_context_menu)


func _on_enemy_context_inspect_pressed(enemy: EnemyInstance) -> void:
	if enemy == null:
		return
	_ensure_enemy_inspect()
	if _enemy_inspect:
		_enemy_inspect.open_enemy(enemy)


func _open_enemy_inspect(index: int) -> void:
	if combat == null or index < 0 or index >= combat.enemies.size():
		return
	_on_enemy_context_inspect_pressed(combat.enemies[index])


func _on_enemy_selected(index: int) -> void:
	if combat == null:
		return
	for child in _enemy_row.get_children():
		var card: EnemyCardUI = child as EnemyCardUI
		if card == null:
			continue
		card.set_selected(card.enemy_index == index)


func _on_ap_changed(current: int, maximum: int) -> void:
	_ap_label.text = tr("KEY_AP_FMT") % [tr("KEY_AP"), current, maximum]
	var previous := _last_ap
	_last_ap = current
	if previous < 0:
		_reset_ap_visuals()
		return
	if current < previous:
		_play_ap_spend_juice()


func _on_ap_insufficient() -> void:
	_play_ap_deny_juice()


func _on_hp_changed(current: int, maximum: int) -> void:
	_hp_label.text = tr("KEY_FRAME_HP_FMT") % [tr("KEY_FRAME_HP"), current, maximum]
	if _player_hp_bar:
		_player_hp_bar.show_label = false
		_player_hp_bar.bar_min_size = Vector2(200, 16)
		_player_hp_bar.custom_minimum_size = Vector2(0, 16)
		_player_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_player_hp_bar.set_hp(current, maximum, _player_hp_initialized)
		_player_hp_initialized = true


func _on_block_changed(amount: int) -> void:
	_block_label.text = tr("KEY_BLOCK_FMT") % [tr("KEY_BLOCK"), amount]
	var previous := _last_block
	_last_block = amount
	if previous < 0:
		_reset_block_visuals(amount)
		return
	if amount > previous:
		_play_block_gain_juice(amount - previous)
	elif amount < previous:
		_play_block_hit_juice()
		if amount <= 0:
			_play_block_expire_juice()
	elif amount <= 0:
		_reset_block_visuals(0)


func _prepare_stat_juice_hosts() -> void:
	if _ap_label:
		_ap_base_color = _ap_label.get_theme_color("font_color")
		_ap_label.pivot_offset = _ap_label.size * 0.5
	if _block_label:
		_block_base_color = _block_label.get_theme_color("font_color")
		_block_label.pivot_offset = _block_label.size * 0.5
		_block_label.modulate.a = 1.0 if _last_block > 0 else 0.7


func _kill_tween(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()


func _reset_ap_visuals() -> void:
	if _ap_label == null:
		return
	_ap_label.scale = Vector2.ONE
	_ap_label.rotation_degrees = 0.0
	_ap_label.modulate = Color.WHITE
	_ap_label.add_theme_color_override("font_color", _ap_base_color)


func _reset_block_visuals(amount: int) -> void:
	if _block_label == null:
		return
	_block_label.scale = Vector2.ONE
	_block_label.rotation_degrees = 0.0
	_block_label.modulate = Color(1, 1, 1, 1.0 if amount > 0 else 0.7)
	_block_label.add_theme_color_override("font_color", _block_base_color)


func _play_ap_spend_juice() -> void:
	if _ap_label == null:
		return
	_kill_tween(_ap_juice_tween)
	_reset_ap_visuals()
	_ap_label.pivot_offset = _ap_label.size * 0.5
	_ap_label.add_theme_color_override("font_color", AP_FLASH_SPEND)
	_ap_juice_tween = create_tween()
	_ap_juice_tween.tween_property(_ap_label, "scale", Vector2(1.2, 1.2), 0.075).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	_ap_juice_tween.tween_property(_ap_label, "scale", Vector2.ONE, 0.075).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN)
	_ap_juice_tween.tween_callback(
		func() -> void: _ap_label.add_theme_color_override("font_color", _ap_base_color)
	)


func _play_ap_deny_juice() -> void:
	if _ap_label == null:
		return
	_kill_tween(_ap_juice_tween)
	_ap_label.scale = Vector2.ONE
	_ap_label.rotation_degrees = 0.0
	_ap_label.pivot_offset = _ap_label.size * 0.5
	_ap_label.add_theme_color_override("font_color", AP_FLASH_DENY)
	## Horizontal shake via rotation — safe inside HBoxContainer layout.
	_ap_juice_tween = create_tween()
	var angles: Array[float] = [-7.0, 7.0, -5.0, 5.0, -2.0, 0.0]
	for angle in angles:
		_ap_juice_tween.tween_property(_ap_label, "rotation_degrees", angle, 0.033).set_trans(
			Tween.TRANS_SINE
		)
	_ap_juice_tween.tween_callback(
		func() -> void:
			_ap_label.rotation_degrees = 0.0
			_ap_label.add_theme_color_override("font_color", _ap_base_color)
	)


func _play_block_gain_juice(gained: int) -> void:
	if _block_label == null:
		return
	_kill_tween(_block_juice_tween)
	_block_label.modulate = Color.WHITE
	_block_label.scale = Vector2.ONE
	_block_label.pivot_offset = _block_label.size * 0.5
	_block_label.add_theme_color_override("font_color", BLOCK_FLASH_GAIN)
	_block_juice_tween = create_tween()
	_block_juice_tween.tween_property(_block_label, "scale", Vector2(1.35, 1.35), 0.1).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_OUT)
	_block_juice_tween.tween_property(_block_label, "scale", Vector2.ONE, 0.1).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_OUT)
	_block_juice_tween.tween_callback(
		func() -> void: _block_label.add_theme_color_override("font_color", _block_base_color)
	)
	if gained > 0:
		_spawn_block_float_text(tr("KEY_FLOAT_BLOCK_GAIN") % gained)


func _play_block_hit_juice() -> void:
	if _block_label == null:
		return
	_kill_tween(_block_juice_tween)
	_block_label.rotation_degrees = 0.0
	_block_label.pivot_offset = _block_label.size * 0.5
	_block_juice_tween = create_tween()
	var angles: Array[float] = [-5.0, 5.0, -3.0, 3.0, 0.0]
	for angle in angles:
		_block_juice_tween.tween_property(_block_label, "rotation_degrees", angle, 0.03).set_trans(
			Tween.TRANS_SINE
		)
	_block_juice_tween.tween_callback(
		func() -> void: _block_label.rotation_degrees = 0.0
	)


func _play_block_expire_juice() -> void:
	if _block_label == null:
		return
	var expire := create_tween()
	expire.set_parallel(true)
	expire.tween_property(_block_label, "modulate:a", 0.55, 0.18).set_trans(Tween.TRANS_SINE)
	expire.tween_property(_block_label, "scale", Vector2(0.88, 0.88), 0.18).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN)
	expire.chain().tween_property(_block_label, "scale", Vector2.ONE, 0.08)


func _spawn_block_float_text(text: String) -> void:
	var host: Control = _block_label if _block_label != null else _stats_row
	if host == null or text.is_empty():
		return
	_spawn_floating_combat_text(host, text, "block")


func _on_combat_started(_enemy_ids: Array) -> void:
	_dying_indices.clear()
	_player_hp_initialized = false
	_last_ap = -1
	_last_block = -1
	_kill_tween(_ap_juice_tween)
	_kill_tween(_block_juice_tween)
	_reset_ap_visuals()
	_reset_block_visuals(0)
	if _log:
		_log.clear()
	hide_combat_log()
	_ensure_player_statuses_ui()
	_bind_damage_popup_manager()
	if DamagePopUpManager:
		DamagePopUpManager.clear_queue()
	if inventory:
		_on_hp_changed(inventory.current_hp, inventory.max_hp)
	_rebuild_enemies()


func _on_turn_started(is_player: bool) -> void:
	_turn_label.text = tr("KEY_PLAYER_TURN") if is_player else tr("KEY_ENEMY_TURN")
	_end_turn_btn.disabled = not is_player
	## Ensure cards exist if combat started before the HUD was ready.
	if combat != null and _enemy_row.get_child_count() == 0 and not combat.enemies.is_empty():
		_rebuild_enemies()
	_sync_card_indices()
	if is_player:
		for child in _enemy_row.get_children():
			var card: EnemyCardUI = child as EnemyCardUI
			if card == null:
				continue
			card.set_intentions_hidden(false)
			if combat != null and card.enemy_index >= 0 and card.enemy_index < combat.enemies.size():
				var enemy: EnemyInstance = combat.enemies[card.enemy_index]
				if enemy != null:
					card.set_intention(enemy.current_intention)
		_play_staggered_intention_reveal()
	else:
		_intention_reveal_token += 1
		for child in _enemy_row.get_children():
			var card: EnemyCardUI = child as EnemyCardUI
			if card == null:
				continue
			card.set_intentions_hidden(true)


func _play_staggered_intention_reveal() -> void:
	_intention_reveal_token += 1
	var token := _intention_reveal_token
	## Left-to-right pop-in across living cards.
	var cards: Array[EnemyCardUI] = []
	for child in _enemy_row.get_children():
		var card := child as EnemyCardUI
		if card != null and is_instance_valid(card):
			cards.append(card)
	for i in cards.size():
		if token != _intention_reveal_token:
			return
		var card := cards[i]
		if not is_instance_valid(card):
			continue
		card.play_intention_pop()
		if i < cards.size() - 1:
			await get_tree().create_timer(INTENTION_STAGGER_DELAY).timeout


func _on_enemy_intention_changed(index: int, intention: RefCounted) -> void:
	if _dying_indices.get(index, false):
		return
	var card := _find_card_by_index(index)
	if card == null:
		return
	var typed := intention as CombatIntention
	## Reactive mid-turn updates use the thinking transition; turn-start uses stagger pop.
	if (
		combat != null
		and combat.state == combat.CombatState.PLAYER_TURN
		and typed != null
		and not typed.is_empty()
	):
		card.set_intentions_hidden(false)
		card.play_intention_reevaluate(typed)
	else:
		card.set_intention(typed)


func _on_enemy_died(index: int) -> void:
	if _dying_indices.get(index, false):
		return
	var card := _find_card_by_index(index)
	if card == null:
		return
	_dying_indices[index] = true
	card.play_death_fade()


func _on_card_death_fade_finished(card: EnemyCardUI) -> void:
	if card == null or combat == null:
		return
	var enemy := card.get_enemy()
	var old_index := card.enemy_index
	_dying_indices.erase(old_index)
	## Quiet remove — card already queue_free's itself; avoid full roster rebuild.
	if enemy != null and combat.has_method("remove_enemy_instance"):
		combat.remove_enemy_instance(enemy, false)
	elif combat.has_method("remove_enemy_at"):
		combat.remove_enemy_at(old_index, false)
	_sync_card_indices()
	if combat.target_index >= 0:
		_on_enemy_selected(combat.target_index)


func _on_enemy_hp(index: int, current: int, maximum: int) -> void:
	if _dying_indices.get(index, false):
		return
	var card := _find_card_by_index(index)
	if card == null:
		return
	card.set_hp(current, maximum)


func _on_log(text: String) -> void:
	if _log == null:
		return
	_log.append_text(text + "\n")
	_scroll_log_to_end()


func _scroll_log_to_end() -> void:
	await get_tree().process_frame
	if is_instance_valid(_log):
		_log.scroll_to_line(_log.get_line_count())


func set_reward_phase(active: bool) -> void:
	## Swap the enemy stage for floating loot; keep the existing Continue button.
	_reward_phase = active
	if active:
		_harmful_insertion_phase = false
	_apply_space_stage_layout(active, tr("KEY_REWARD_SELECT_UP_TO_3"))


func set_harmful_insertion_phase(active: bool) -> void:
	## Mid-combat forced placement of a harmful item into the Body Grid.
	_harmful_insertion_phase = active
	if active:
		_reward_phase = false
	_apply_space_stage_layout(active, tr("KEY_FORCED_INSERT_BANNER"))
	if _continue_btn:
		if active:
			_continue_btn.text = tr("KEY_CONTINUE")
			_continue_btn.visible = true
			_continue_btn.disabled = true  ## Enabled by ForcedItemScreen when placed.
		else:
			## Resume enemy/player turn — Continue belongs only to end-of-combat / rewards.
			_continue_btn.visible = _reward_phase or _is_combat_ended()
			if not _continue_btn.visible:
				_continue_btn.disabled = false


func _is_combat_ended() -> bool:
	if combat == null:
		return false
	var s: Variant = combat.get("state")
	if s == null:
		return false
	## CombatManager.CombatState.VICTORY / DEFEAT
	return int(s) == 3 or int(s) == 4


func set_continue_enabled(enabled: bool) -> void:
	if _continue_btn:
		_continue_btn.disabled = not enabled


func is_harmful_insertion_phase() -> bool:
	return _harmful_insertion_phase


func _apply_space_stage_layout(active: bool, hint_text: String) -> void:
	if _loot_stage:
		_loot_stage.visible = active
		if active:
			_loot_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _enemy_row:
		_enemy_row.visible = not active
	if _stats_enemy_gap:
		_stats_enemy_gap.visible = not active
	if _enemy_actions_gap:
		_enemy_actions_gap.visible = true
		_enemy_actions_gap.custom_minimum_size = Vector2(0, 8 if active else 24)
		_enemy_actions_gap.size_flags_vertical = (
			Control.SIZE_SHRINK_BEGIN if active else Control.SIZE_EXPAND_FILL
		)
	if _end_turn_btn:
		_end_turn_btn.visible = not active
		if active:
			_end_turn_btn.disabled = true
	## Continue visibility is owned by set_reward_phase / set_harmful_insertion_phase /
	## _on_combat_ended — only force-show while a space-stage overlay is active.
	if _continue_btn and active:
		_continue_btn.visible = true
	if _hint_label:
		if active:
			_hint_label.visible = true
			_hint_label.text = hint_text
			_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			_hint_label.visible = false
			_hint_label.text = tr("KEY_COMBAT_CLICK_HINT")
			_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


func get_loot_stage() -> Control:
	return _loot_stage


func is_reward_phase() -> bool:
	return _reward_phase


func _on_combat_ended(victory: bool) -> void:
	if _enemy_context_menu and _enemy_context_menu.is_open():
		_enemy_context_menu.close()
	_end_turn_btn.disabled = true
	## During reward phase Continue stays visible from set_reward_phase; otherwise show it now.
	if not _reward_phase:
		_continue_btn.visible = true
		_end_turn_btn.visible = true
	_continue_btn.text = tr("KEY_CONTINUE") if victory else tr("KEY_RETURN_TO_MAP")
	_turn_label.text = tr("KEY_VICTORY") if victory else tr("KEY_FRAME_FAILURE")
	_intention_reveal_token += 1
	for child in _enemy_row.get_children():
		var card: EnemyCardUI = child as EnemyCardUI
		if card:
			card.set_intentions_hidden(true)


func _on_enemy_combat_text(enemy_index: int, text: String, kind: String) -> void:
	if text.is_empty():
		return
	var card := _find_card_by_index(enemy_index)
	if card == null:
		return
	var host: Control = card.get_combat_text_host()
	if host == null:
		host = card
	_spawn_floating_combat_text(host, text, kind)


func _spawn_floating_combat_text(host: Control, text: String, kind: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 80
	label.add_theme_font_size_override("font_size", 15 if kind == "crit" else 14)
	match kind:
		"crit":
			label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		"pre_action":
			label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
		"multi_hit":
			label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
		"block":
			label.add_theme_color_override("font_color", BLOCK_FLASH_GAIN)
		_:
			label.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	host.add_child(label)
	await get_tree().process_frame
	if not is_instance_valid(label):
		return
	var host_w := maxf(host.size.x, 80.0)
	var label_w := label.get_minimum_size().x
	label.position = Vector2((host_w - label_w) * 0.5, -4.0)
	var start_y := label.position.y
	var tween := host.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", start_y - 36.0, 0.85).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_OUT
	)
	tween.tween_property(label, "modulate:a", 0.0, 0.85).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)
