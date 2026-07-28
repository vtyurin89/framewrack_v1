extends Node
## Turn-based combat — Backpack Hero style.
## Player activates body-grid modules by clicking them; only End Turn remains in the HUD.

enum CombatState {
	INACTIVE,
	PLAYER_TURN,
	ENEMY_TURN,
	VICTORY,
	DEFEAT,
}

signal state_changed(new_state: CombatState)

var inventory: InventoryController
var player_stats: PlayerStats
var state: CombatState = CombatState.INACTIVE

## Runtime enemy combatants (difficulty-scaled HP + ability AI).
var enemies: Array[EnemyInstance] = []
var _ability_executor: EnemyAbilityExecutor

var current_ap: int = 0
var max_ap: int = 3
var current_block: int = 0
var target_index: int = 0
var _player_poison_stacks: int = 0
var _player_rust_stacks: int = 0
var _player_burn_stacks: int = 0


func setup(p_inventory: InventoryController, p_stats: PlayerStats = null) -> void:
	inventory = p_inventory
	if p_stats != null:
		player_stats = p_stats
	_ensure_ability_executor()


func _ensure_ability_executor() -> void:
	if _ability_executor == null:
		_ability_executor = EnemyAbilityExecutor.new(self)
	else:
		_ability_executor.set_combat(self)


func is_player_turn_active() -> bool:
	return state == CombatState.PLAYER_TURN


func start_combat(enemy_datas: Array[EnemyData]) -> void:
	_ensure_ability_executor()
	enemies.clear()
	var ids: Array[String] = []
	for data: EnemyData in enemy_datas:
		if data == null:
			continue
		var instance := EnemyDatabase.create_instance_from_data(data)
		if instance == null:
			instance = EnemyInstance.new()
			instance.setup(data)
		enemies.append(instance)
		ids.append(data.id)
	current_block = 0
	_select_first_living_enemy()
	EventBus.combat_started.emit(ids)
	_begin_player_turn()


func _set_state(next: CombatState) -> void:
	state = next
	state_changed.emit(next)
	match next:
		CombatState.PLAYER_TURN:
			EventBus.game_state_changed.emit(GameFlowState.State.PLAYER_TURN)
			EventBus.turn_started.emit(true)
		CombatState.ENEMY_TURN:
			EventBus.game_state_changed.emit(GameFlowState.State.ENEMY_TURN)
			EventBus.turn_started.emit(false)
		CombatState.VICTORY:
			EventBus.game_state_changed.emit(GameFlowState.State.VICTORY)
		CombatState.DEFEAT:
			EventBus.game_state_changed.emit(GameFlowState.State.GAME_OVER)
		_:
			pass


func _begin_player_turn() -> void:
	current_block = 0
	EventBus.block_changed.emit(current_block)
	max_ap = inventory.get_max_ap()
	current_ap = max_ap
	_reset_all_item_turn_uses()
	TraitManager.apply_passive_armor_from_spatial_traits(inventory.grid, Callable(self, "_gain_block"))
	_ensure_valid_selection()
	EventBus.ap_changed.emit(current_ap, max_ap)
	EventBus.combat_item_availability_changed.emit()
	_set_state(CombatState.PLAYER_TURN)
	EventBus.combat_log_message.emit(tr("KEY_LOG_YOUR_TURN") % current_ap)
	_emit_enemy_hp()


func end_player_turn() -> void:
	if state != CombatState.PLAYER_TURN:
		return
	_begin_enemy_turn()


func set_target(index: int) -> void:
	if index < 0 or index >= enemies.size():
		return
	if not enemies[index].is_alive():
		return
	_apply_selection(index)


func _select_first_living_enemy() -> void:
	var living := _living_enemy_indices()
	if living.is_empty():
		target_index = -1
		return
	_apply_selection(living[0])


func _ensure_valid_selection() -> void:
	var living := _living_enemy_indices()
	if living.is_empty():
		target_index = -1
		return
	if target_index not in living:
		_apply_selection(living[0])


func _apply_selection(index: int) -> void:
	for i in enemies.size():
		enemies[i].is_selected = (i == index)
	target_index = index
	EventBus.enemy_selected.emit(index)


func can_activate_item(placed: PlacedItem) -> bool:
	if state != CombatState.PLAYER_TURN:
		return false
	if placed == null or placed.data == null:
		return false
	var data: ItemData = placed.data
	if not data.usable:
		return false
	if not inventory.grid.is_item_functional(placed):
		return false
	if current_ap < data.ap_cost:
		return false
	if not data.can_use_this_turn():
		return false
	if not data.has_charges_remaining():
		return false
	return true


func activate_item(placed: PlacedItem) -> bool:
	## Direct inventory click activation (Backpack Hero model).
	if not can_activate_item(placed):
		_log_activation_failure(placed)
		return false

	var data: ItemData = placed.data
	current_ap -= data.ap_cost
	data.current_turn_uses += 1
	EventBus.ap_changed.emit(current_ap, max_ap)

	match data.target_type:
		ItemData.TargetType.SELF:
			_resolve_self(placed)
		ItemData.TargetType.ALL_ENEMIES:
			_resolve_all_enemies(placed)
		_:
			_resolve_single_enemy(placed)

	_consume_charge_if_needed(placed)
	EventBus.combat_item_availability_changed.emit()

	if _all_enemies_dead():
		_win()
	return true


func _log_activation_failure(placed: PlacedItem) -> void:
	if state != CombatState.PLAYER_TURN:
		return
	if placed == null or placed.data == null:
		return
	var data: ItemData = placed.data
	if not inventory.grid.is_item_functional(placed):
		EventBus.combat_log_message.emit(tr("KEY_LOG_OFFLINE") % data.get_localized_name())
	elif not data.usable:
		EventBus.combat_log_message.emit(tr("KEY_LOG_PASSIVE") % data.get_localized_name())
	elif current_ap < data.ap_cost:
		EventBus.combat_log_message.emit(tr("KEY_LOG_NOT_ENOUGH_AP"))
	elif not data.can_use_this_turn():
		EventBus.combat_log_message.emit(tr("KEY_LOG_NO_USES"))
	elif not data.has_charges_remaining():
		EventBus.combat_log_message.emit(tr("KEY_LOG_NO_CHARGES"))


func _resolve_single_enemy(placed: PlacedItem) -> void:
	_ensure_valid_selection()
	if target_index < 0:
		return
	var data := placed.data
	if data.item_type != null and data.item_type.id.to_upper() == "CONSUMABLE":
		_resolve_consumable_enemy(placed, target_index)
		return
	var dmg := _calc_damage(placed)
	var trait_bonus := _consume_attack_trait_bonus(placed)
	dmg += trait_bonus
	_deal_damage_to(target_index, dmg, data.get_localized_name())


func _resolve_all_enemies(placed: PlacedItem) -> void:
	var dmg := _calc_damage(placed)
	var trait_bonus := _consume_attack_trait_bonus(placed)
	dmg += trait_bonus
	var living := _living_enemy_indices()
	for idx: int in living:
		_deal_damage_to(idx, dmg, placed.data.get_localized_name())


func _resolve_self(placed: PlacedItem) -> void:
	if TraitManager.has_trait(placed.data, "TRAIT_ARMOR_CORE_TRIGGER"):
		TraitManager.activate_armor_core(
			placed,
			inventory.grid,
			Callable(self, "_gain_block"),
			_armor_stat_bonus(placed.data)
		)
		return

	var data := placed.data
	if data.item_type != null and data.item_type.id.to_upper() == "CONSUMABLE":
		_apply_self_use_traits(placed)
		return

	var armor := data.get_scaled_armor(player_stats)
	if armor <= 0 and data.block_amount > 0:
		armor = data.block_amount + _armor_stat_bonus(data)
	if armor > 0:
		_gain_block(armor, data.get_localized_name())
	else:
		EventBus.combat_log_message.emit(tr("KEY_LOG_ACTIVATED") % data.get_localized_name())

	_apply_self_use_traits(placed)


func _calc_damage(placed: PlacedItem) -> int:
	var adjacency_bonus: int = inventory.grid.get_adjacency_damage_bonus_for(placed)
	return placed.data.get_scaled_damage(player_stats) + adjacency_bonus


func _armor_stat_bonus(data: ItemData) -> int:
	if data == null:
		return 0
	return data.get_armor_stat_bonus(player_stats)


func _roll_player_crit() -> bool:
	if player_stats == null:
		return false
	var chance := player_stats.get_crit_chance()
	if chance <= 0.0:
		return false
	return randf() < chance


func _deal_damage_to(index: int, dmg: int, source_name: String, allow_crit: bool = true) -> void:
	if index < 0 or index >= enemies.size():
		return
	var enemy: EnemyInstance = enemies[index]
	if not enemy.is_alive():
		return
	var final_dmg := dmg
	var is_crit := false
	if allow_crit and _roll_player_crit():
		is_crit = true
		final_dmg = roundi(float(dmg) * EnemyInstance.CRIT_DAMAGE_MULT)
	var adjacency_note := ""
	enemy.apply_incoming_damage(final_dmg)
	if is_crit:
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_ENEMY_CRIT_HIT") % [source_name, final_dmg]
		)
	else:
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_DAMAGE") % [source_name, final_dmg, adjacency_note, enemy.get_localized_name()]
		)
	EventBus.enemy_hp_changed.emit(index, enemy.current_hp, enemy.max_hp)
	if not enemy.is_alive():
		_ensure_valid_selection()


func _consume_charge_if_needed(placed: PlacedItem) -> void:
	var data: ItemData = placed.data
	if not data.consumable:
		return
	data.current_charges = maxi(0, data.current_charges - 1)
	EventBus.inventory_changed.emit()
	if data.current_charges <= 0 and data.destroy_on_empty:
		inventory.grid.remove_item(placed, false)
		EventBus.item_removed.emit(data.id)
		EventBus.inventory_changed.emit()
		EventBus.combat_log_message.emit(tr("KEY_LOG_ITEM_DESTROYED") % data.get_localized_name())
	if player_stats != null and inventory != null:
		player_stats.recalculate_from_equipment(inventory.grid)


func _gain_block(amount: int, source_name: String) -> void:
	if amount <= 0:
		return
	current_block += amount
	EventBus.block_changed.emit(current_block)
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_BLOCK") % [source_name, amount, current_block]
	)


func _consume_attack_trait_bonus(placed: PlacedItem) -> int:
	## Extra damage from consumable / weapon traits that should apply per-use.
	if placed == null or placed.data == null:
		return 0
	var bonus := 0
	if TraitManager.has_trait(placed.data, "TRAIT_BURN_DAMAGE"):
		bonus += 4
	return bonus


func _apply_self_use_traits(placed: PlacedItem) -> void:
	## Self-targeted trait effects (consumables and special self modules).
	if placed == null or placed.data == null:
		return
	var data := placed.data
	if TraitManager.has_trait(data, "TRAIT_BIO_GEL_HEAL"):
		inventory.current_hp = mini(inventory.max_hp, inventory.current_hp + 8)
		EventBus.player_hp_changed.emit(inventory.current_hp, inventory.max_hp)
	if TraitManager.has_trait(data, "TRAIT_GIVE_AP"):
		current_ap += 2
		EventBus.ap_changed.emit(current_ap, max_ap)
	if TraitManager.has_trait(data, "TRAIT_CLEANSE_DEBUFFS"):
		_clear_player_negative_statuses()
		inventory.grid.clear_all_corruption()


func _resolve_consumable_enemy(placed: PlacedItem, enemy_index: int) -> void:
	var data := placed.data
	var dealt := 0
	if TraitManager.has_trait(data, "TRAIT_BURN_DAMAGE"):
		var burn_hit := TraitManager.get_trait_value(data, "TRAIT_BURN_DAMAGE", 18)
		_deal_damage_to(enemy_index, burn_hit, data.get_localized_name())
		dealt = burn_hit
		if enemy_index >= 0 and enemy_index < enemies.size():
			enemies[enemy_index].burn += TraitManager.BURN_APPLY_STACKS
	if dealt == 0:
		_deal_damage_to(enemy_index, data.base_damage, data.get_localized_name())


func _reset_all_item_turn_uses() -> void:
	if inventory == null:
		return
	for placed: PlacedItem in inventory.grid.items:
		if placed != null and placed.data != null:
			placed.data.reset_turn_uses()


func _begin_enemy_turn() -> void:
	_set_state(CombatState.ENEMY_TURN)
	EventBus.combat_log_message.emit(tr("KEY_LOG_ENEMY_TURN"))
	_run_enemy_actions()


func _run_enemy_actions() -> void:
	_tick_enemy_burn()
	for i in enemies.size():
		var enemy: EnemyInstance = enemies[i]
		if not enemy.is_alive():
			continue
		_enemy_act(i, enemy)
		if inventory.is_dead():
			_lose()
			return

	inventory.grid.tick_corruption()

	if _all_enemies_dead():
		_win()
	else:
		_begin_player_turn()


func _enemy_act(index: int, enemy: EnemyInstance) -> void:
	## 1) Pre-action phase (e.g. Rebel Enemy Study luck buff via modify_stat).
	var pre: Dictionary = EnemyAI.trigger_pre_action_phase(enemy)
	if bool(pre.get("triggered", false)):
		var pre_ability: EnemyAbility = pre.get("ability") as EnemyAbility
		if pre_ability != null:
			_ability_executor.execute(enemy, index, pre_ability)

	## 2) Main action through AbilityEffect handlers.
	var action: Dictionary = EnemyAI.resolve_main_action(enemy)
	var ability: EnemyAbility = action.get("ability") as EnemyAbility
	if ability != null:
		_ability_executor.execute(enemy, index, ability)
	else:
		_enemy_act_legacy_fallback(index, enemy)

	enemy.end_enemy_turn()


func _enemy_act_legacy_fallback(index: int, enemy: EnemyInstance) -> void:
	var data := enemy.data
	var dmg := data.basic_damage if data else 5
	if GameSettings != null:
		dmg = int(round(float(dmg) * GameSettings.get_enemy_damage_multiplier()))
	var dealt := apply_enemy_damage_to_player(dmg)
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_ENEMY_STRIKE") % [enemy.get_localized_name(), dmg, dealt]
	)
	EventBus.enemy_hp_changed.emit(index, enemy.current_hp, enemy.max_hp)


## --- AbilityEffect combat hooks ---------------------------------------------

func apply_enemy_damage_to_player(damage: int) -> int:
	var dealt := inventory.apply_damage(damage, current_block)
	current_block = maxi(0, current_block - damage)
	EventBus.block_changed.emit(current_block)
	return dealt


func is_player_defeated() -> bool:
	return inventory != null and inventory.is_dead()


func get_random_living_ally(exclude: EnemyInstance) -> EnemyInstance:
	var living: Array[EnemyInstance] = []
	for enemy: EnemyInstance in enemies:
		if enemy != null and enemy.is_alive() and enemy != exclude:
			living.append(enemy)
	if living.is_empty():
		return null
	return living[randi() % living.size()]


func emit_enemy_hp_for(enemy: EnemyInstance) -> void:
	var idx := enemies.find(enemy)
	if idx < 0:
		return
	EventBus.enemy_hp_changed.emit(idx, enemy.current_hp, enemy.max_hp)


func add_summoned_enemy(instance: EnemyInstance) -> void:
	if instance == null:
		return
	enemies.append(instance)
	EventBus.enemy_roster_changed.emit()
	_emit_enemy_hp()


func apply_player_status(status_id: String, potency: int) -> void:
	var amount := maxi(1, potency)
	match status_id.strip_edges().to_lower():
		"poison":
			_player_poison_stacks += amount
		"burn":
			_player_burn_stacks += amount
		"rust":
			_player_rust_stacks += amount
		_:
			pass


func _tick_enemy_burn() -> void:
	for i in enemies.size():
		var enemy: EnemyInstance = enemies[i]
		if not enemy.is_alive():
			continue
		var burn := enemy.burn
		if burn <= 0:
			continue
		enemy.current_hp = maxi(0, enemy.current_hp - burn)
		enemy.burn = maxi(0, burn - 1)
		EventBus.combat_log_message.emit("%s burns for %d." % [enemy.get_localized_name(), burn])
		EventBus.enemy_hp_changed.emit(i, enemy.current_hp, enemy.max_hp)


func _clear_player_negative_statuses() -> void:
	_player_poison_stacks = 0
	_player_rust_stacks = 0
	_player_burn_stacks = 0


func _living_enemy_indices() -> Array[int]:
	var result: Array[int] = []
	for i in enemies.size():
		if enemies[i].is_alive():
			result.append(i)
	return result


func _all_enemies_dead() -> bool:
	return _living_enemy_indices().is_empty()


func _emit_enemy_hp() -> void:
	for i in enemies.size():
		var enemy: EnemyInstance = enemies[i]
		EventBus.enemy_hp_changed.emit(i, enemy.current_hp, enemy.max_hp)
	if target_index >= 0:
		EventBus.enemy_selected.emit(target_index)


func _win() -> void:
	_set_state(CombatState.VICTORY)
	EventBus.combat_log_message.emit(tr("KEY_LOG_VICTORY"))
	EventBus.combat_ended.emit(true)


func _lose() -> void:
	## Abort combat and hand control to the global GAME_OVER state.
	_set_state(CombatState.DEFEAT)
	EventBus.combat_log_message.emit(tr("KEY_LOG_DEFEAT"))
	EventBus.combat_ended.emit(false)
	GameManager.trigger_game_over()


func abort_combat() -> void:
	## Hard stop without emitting a second game-over (used when already dying).
	if state == CombatState.INACTIVE or state == CombatState.DEFEAT or state == CombatState.VICTORY:
		state = CombatState.INACTIVE
		return
	state = CombatState.INACTIVE
	enemies.clear()
	current_ap = 0
	current_block = 0
	target_index = -1
	state_changed.emit(state)
