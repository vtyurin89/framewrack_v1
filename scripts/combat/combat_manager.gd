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
signal forced_insertion_requested(item_id: String)
signal forced_insertion_completed

const SLIMY_PARASITE_ID := "SLIMY_PARASITE"
const PARASITE_TURN_DAMAGE := 3
const PARASITE_AP_CAP := 3

var inventory: InventoryController
var player_stats: PlayerStats
var state: CombatState = CombatState.INACTIVE
## Player combat statuses (poison, rust, stun, …).
var player_statuses: StatusController = StatusController.new()

## Runtime enemy combatants (difficulty-scaled HP + ability AI).
var enemies: Array[EnemyInstance] = []
var _ability_executor: EnemyAbilityExecutor

var current_ap: int = 0
var max_ap: int = 3
var current_block: int = 0
var target_index: int = 0
## Group Intent Coordination (from EnemyGroup.max_attackers_per_turn).
var max_attackers_per_turn: int = 2
var _attacker_slots_used: int = 0
## Counts completed player turn starts this combat (1 = first turn).
var player_turn_index: int = 0
## Mid-enemy-turn pause while ForcedItemScreen is open.
var awaiting_forced_insertion: bool = false


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


func start_combat(enemy_datas: Array[EnemyData], max_attackers: int = -1) -> void:
	_ensure_ability_executor()
	if player_statuses == null:
		player_statuses = StatusController.new()
	player_statuses.clear_combat_statuses()
	enemies.clear()
	if max_attackers > 0:
		set_group_attack_cap(max_attackers)
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
	player_turn_index = 0
	_select_first_living_enemy()
	EventBus.combat_started.emit(ids)
	_begin_player_turn()


func set_group_attack_cap(cap: int) -> void:
	## Group Intent Coordination — how many heavy attackers may fire per enemy turn.
	max_attackers_per_turn = maxi(1, cap)
	_attacker_slots_used = 0


func reset_attacker_slots() -> void:
	_attacker_slots_used = 0


func try_reserve_attacker_slot() -> bool:
	## Returns true if this unit may commit an offensive main action.
	if _attacker_slots_used >= max_attackers_per_turn:
		return false
	_attacker_slots_used += 1
	return true


func has_attacker_slot() -> bool:
	return _attacker_slots_used < max_attackers_per_turn


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
	## Strict player turn pipeline.
	_reset_player_resources()
	if not _apply_slimy_parasite_turn_damage():
		return
	if not _player_pre_turn_phase():
		return
	_player_start_turn_phase()
	_ensure_valid_selection()
	EventBus.ap_changed.emit(current_ap, max_ap)
	EventBus.combat_item_availability_changed.emit()
	## Plan telegraphs before turn_started so the UI stagger reveals committed intents.
	_plan_all_intentions(true)
	_emit_enemy_hp()
	_set_state(CombatState.PLAYER_TURN)
	EventBus.combat_log_message.emit(tr("KEY_LOG_YOUR_TURN") % current_ap)
	## Action phase is interactive (activate_item / end_player_turn).


func _reset_player_resources() -> void:
	current_block = 0
	EventBus.block_changed.emit(current_block)
	max_ap = inventory.get_max_ap()
	current_ap = max_ap
	player_turn_index += 1
	if player_turn_index == 1:
		current_ap += _eye_of_pale_maiden_turn1_ap_mod()
		current_ap = maxi(0, current_ap)
	_apply_slimy_parasite_ap_cap()
	_reset_all_item_turn_uses()
	TraitManager.apply_passive_armor_from_spatial_traits(inventory.grid, Callable(self, "_gain_block"))


func _apply_slimy_parasite_ap_cap() -> void:
	if not _has_item_in_grid(SLIMY_PARASITE_ID):
		return
	max_ap = mini(max_ap, PARASITE_AP_CAP)
	current_ap = mini(current_ap, PARASITE_AP_CAP)


func has_item_in_grid(item_id: String) -> bool:
	if inventory == null or inventory.grid == null:
		return false
	var needle := item_id.strip_edges().to_upper()
	for placed: PlacedItem in inventory.grid.items:
		if placed != null and placed.data != null and placed.data.id.strip_edges().to_upper() == needle:
			return true
	return false


func _has_item_in_grid(item_id: String) -> bool:
	return has_item_in_grid(item_id)


func _apply_slimy_parasite_turn_damage() -> bool:
	## Returns false if the player dies from parasite damage.
	if not _has_item_in_grid(SLIMY_PARASITE_ID) or inventory == null:
		return true
	var dealt := inventory.apply_damage(PARASITE_TURN_DAMAGE, 0)
	_request_player_popup(dealt if dealt > 0 else PARASITE_TURN_DAMAGE, "poison")
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_PARASITE_DAMAGE") % PARASITE_TURN_DAMAGE
	)
	EventBus.player_hp_changed.emit(inventory.current_hp, inventory.max_hp)
	if inventory.is_dead():
		_lose()
		return false
	return true


func _eye_of_pale_maiden_turn1_ap_mod() -> int:
	## +1 AP on turn 1, or -1 if the eye sits adjacent to any weapon.
	if inventory == null or inventory.grid == null:
		return 0
	for placed: PlacedItem in inventory.grid.items:
		if placed == null or placed.data == null:
			continue
		if not TraitManager.has_trait(placed.data, "TRAIT_EYE_OF_PALE_MAIDEN"):
			if placed.data.id.strip_edges().to_upper() != "EYE_OF_PALE_MAIDEN":
				continue
		var next_to_weapon := false
		for neighbour: PlacedItem in inventory.grid.get_adjacent_items(placed):
			if neighbour != null and neighbour.data != null and neighbour.data.is_weapon():
				next_to_weapon = true
				break
		return -1 if next_to_weapon else 1
	return 0


func _player_pre_turn_phase() -> bool:
	## Tick negative statuses. Returns false if turn should abort (death / stun skip handled).
	var result: Dictionary = player_statuses.tick_negative_statuses()
	var dmg: int = int(result.get("damage", 0))
	if dmg > 0:
		var dealt := inventory.apply_damage(dmg, 0)
		var dtype := _infer_status_dot_type(result)
		_request_player_popup(dealt if dealt > 0 else dmg, dtype)
		EventBus.combat_log_message.emit(tr("KEY_LOG_STATUS_DOT") % [tr("KEY_STATUS_DOT"), dmg, dealt])
		EventBus.player_hp_changed.emit(inventory.current_hp, inventory.max_hp)
		if inventory.is_dead():
			_lose()
			return false
	if bool(result.get("skip_turn", false)):
		EventBus.combat_log_message.emit(tr("KEY_LOG_STUNNED"))
		_player_post_turn_phase()
		_begin_enemy_turn()
		return false
	return true


func _player_start_turn_phase() -> void:
	var result: Dictionary = player_statuses.tick_positive_statuses()
	var heal_amt: int = _modify_player_healing(int(result.get("heal", 0)))
	if heal_amt > 0 and inventory != null:
		inventory.current_hp = mini(inventory.max_hp, inventory.current_hp + heal_amt)
		EventBus.player_hp_changed.emit(inventory.current_hp, inventory.max_hp)
		_request_player_popup(heal_amt, "heal")
		EventBus.combat_log_message.emit(tr("KEY_LOG_STATUS_HEAL") % heal_amt)


func _modify_player_healing(amount: int) -> int:
	## Dead Grip / healing_curse halves incoming heals.
	if amount <= 0:
		return 0
	if player_statuses != null and player_statuses.has_status("healing_curse"):
		return maxi(0, int(round(float(amount) * 0.5)))
	return amount


func _player_post_turn_phase() -> void:
	## End-of-turn hooks (duration POST_TURN statuses, etc.).
	player_statuses.tick_post_turn()


func end_player_turn() -> void:
	if state != CombatState.PLAYER_TURN:
		return
	_player_post_turn_phase()
	_begin_enemy_turn()


func _plan_all_intentions(force_reroll: bool = true) -> void:
	## Plan in roster order so attacker-slot reservation is deterministic.
	reset_attacker_slots()
	for i in enemies.size():
		var enemy: EnemyInstance = enemies[i]
		if enemy == null or not enemy.is_alive():
			if enemy != null:
				enemy.clear_intention()
				EventBus.enemy_intention_changed.emit(i, enemy.current_intention)
			continue
		if force_reroll:
			enemy.evaluate_intention({"block": current_block}, self)
		else:
			enemy.reevaluate_intention(false, self)
		EventBus.enemy_intention_changed.emit(i, enemy.current_intention)


func reevaluate_enemy_intention(index: int) -> void:
	if index < 0 or index >= enemies.size():
		return
	var enemy: EnemyInstance = enemies[index]
	if enemy == null or not enemy.is_alive():
		return
	## Full replan so group attacker caps stay consistent with telegraphs.
	_plan_all_intentions(true)


func plan_intentions_for_living(force_reroll: bool = true) -> void:
	_plan_all_intentions(force_reroll)


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

	## Rust jam: AP already spent, effect skipped.
	if player_statuses != null and player_statuses.roll_rust_fail():
		EventBus.combat_log_message.emit(tr("KEY_LOG_RUST_JAM") % data.get_localized_name())
		_request_player_popup(0, "rust", false, true)
		_consume_charge_if_needed(placed)
		EventBus.combat_item_availability_changed.emit()
		return true

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
		EventBus.ap_insufficient.emit()
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
	_apply_on_hit_weapon_statuses(placed, target_index)


func _resolve_all_enemies(placed: PlacedItem) -> void:
	var dmg := _calc_damage(placed)
	var trait_bonus := _consume_attack_trait_bonus(placed)
	dmg += trait_bonus
	var living := _living_enemy_indices()
	for idx: int in living:
		_deal_damage_to(idx, dmg, placed.data.get_localized_name())
		_apply_on_hit_weapon_statuses(placed, idx)


func _resolve_self(placed: PlacedItem) -> void:
	if placed != null and placed.data != null and placed.data.is_harmful:
		_perform_harmful_surgery(placed)
		return

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


func _perform_harmful_surgery(placed: PlacedItem) -> void:
	## Spend AP (already deducted) to cut a harmful module out of the frame.
	if placed == null or placed.data == null or inventory == null or inventory.grid == null:
		return
	var item_name := placed.data.get_localized_name()
	inventory.grid.remove_item(placed, true)
	EventBus.combat_log_message.emit(tr("KEY_LOG_HARMFUL_SURGERY") % item_name)
	EventBus.inventory_changed.emit()
	EventBus.combat_item_availability_changed.emit()
	## Recalc AP cap after parasite removal mid-turn (does not refund AP).
	if not _has_item_in_grid(SLIMY_PARASITE_ID):
		max_ap = inventory.get_max_ap()
		EventBus.ap_changed.emit(current_ap, max_ap)


func _calc_damage(placed: PlacedItem) -> int:
	var adjacency_bonus: int = inventory.grid.get_adjacency_damage_bonus_for(placed)
	var raw: int = placed.data.roll_damage(player_stats) + adjacency_bonus
	if player_statuses != null:
		return player_statuses.modify_outgoing_damage(raw)
	return raw


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


func _deal_damage_to(
	index: int,
	dmg: int,
	source_name: String,
	allow_crit: bool = true,
	damage_type: String = "physical"
) -> void:
	if index < 0 or index >= enemies.size():
		return
	var enemy: EnemyInstance = enemies[index]
	if not enemy.is_alive():
		return
	var final_dmg := dmg
	## Enemy vulnerability amplifies incoming hits.
	if enemy.statuses != null:
		final_dmg = enemy.statuses.modify_incoming_damage(final_dmg)
	var is_crit := false
	if allow_crit and _roll_player_crit():
		is_crit = true
		var crit_mult := EnemyInstance.CRIT_DAMAGE_MULT
		if player_statuses != null:
			crit_mult = player_statuses.get_crit_damage_multiplier(crit_mult)
		final_dmg = roundi(float(final_dmg) * crit_mult)
	var adjacency_note := ""
	var had_evasion := (
		enemy.statuses != null
		and enemy.statuses.has_status("evasion")
		and enemy.statuses.get_stacks("evasion") > 0
	)
	var hp_before := enemy.current_hp
	var block_before := enemy.current_block
	enemy.apply_incoming_damage(final_dmg)
	var dealt := maxi(0, hp_before - enemy.current_hp)
	if (
		had_evasion
		and dealt <= 0
		and enemy.current_block == block_before
		and final_dmg > 0
	):
		_request_enemy_popup(index, 0, damage_type, false, true)
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_EVASION_NEGATE_ENEMY") % enemy.get_localized_name()
		)
		EventBus.enemy_hp_changed.emit(index, enemy.current_hp, enemy.max_hp)
		return
	_request_enemy_popup(index, dealt if dealt > 0 else final_dmg, damage_type, is_crit, false)
	## Thorns on enemy reflect to player.
	if enemy.statuses != null:
		var thorns := enemy.statuses.get_thorns_reflect()
		if thorns > 0:
			var thorns_dealt := apply_enemy_damage_to_player(thorns)
			_request_player_popup(thorns_dealt if thorns_dealt > 0 else thorns, "physical")
			EventBus.combat_log_message.emit(tr("KEY_LOG_THORNS") % [enemy.get_localized_name(), thorns])
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
		enemy.clear_intention()
		EventBus.enemy_intention_changed.emit(index, enemy.current_intention)
		_on_enemy_defeated(enemy, index)
		EventBus.enemy_died.emit(index)
		_ensure_valid_selection()
	elif state == CombatState.PLAYER_TURN:
		reevaluate_enemy_intention(index)


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
		var heal_amt := _modify_player_healing(8)
		inventory.current_hp = mini(inventory.max_hp, inventory.current_hp + heal_amt)
		EventBus.player_hp_changed.emit(inventory.current_hp, inventory.max_hp)
	if TraitManager.has_trait(data, "TRAIT_GIVE_AP"):
		current_ap += 2
		EventBus.ap_changed.emit(current_ap, max_ap)
	if TraitManager.has_trait(data, "TRAIT_CLEANSE_DEBUFFS"):
		if player_statuses != null:
			player_statuses.clear_debuffs()
		inventory.grid.clear_all_corruption()


func _resolve_consumable_enemy(placed: PlacedItem, enemy_index: int) -> void:
	var data := placed.data
	var dealt := 0
	if TraitManager.has_trait(data, "TRAIT_BURN_DAMAGE"):
		## Damage comes from the item roll; the trait only applies Burn.
		var burn_hit: int = data.roll_damage(player_stats)
		if burn_hit <= 0:
			burn_hit = TraitManager.get_trait_value(data, "TRAIT_BURN_DAMAGE", 9)
		_deal_damage_to(enemy_index, burn_hit, data.get_localized_name(), true, "burn")
		dealt = burn_hit
		if enemy_index >= 0 and enemy_index < enemies.size():
			apply_status_to_enemy(enemy_index, "burn", TraitManager.BURN_APPLY_STACKS)
	if dealt == 0:
		_deal_damage_to(enemy_index, data.roll_damage(player_stats), data.get_localized_name())


func _reset_all_item_turn_uses() -> void:
	if inventory == null:
		return
	for placed: PlacedItem in inventory.grid.items:
		if placed != null and placed.data != null:
			placed.data.reset_turn_uses()


func _begin_enemy_turn() -> void:
	_set_state(CombatState.ENEMY_TURN)
	EventBus.combat_log_message.emit(tr("KEY_LOG_ENEMY_TURN"))
	## Re-open attacker budget for the act phase (matches telegraphed plans).
	reset_attacker_slots()
	await _run_enemy_actions()


func _run_enemy_actions() -> void:
	for i in enemies.size():
		var enemy: EnemyInstance = enemies[i]
		if enemy == null or not enemy.is_alive():
			continue
		if not _enemy_pre_turn_phase(i, enemy):
			continue
		_enemy_start_turn_phase(i, enemy)
		if not enemy.is_alive():
			continue
		_enemy_pre_action_phase(i, enemy)
		_enemy_main_action_phase(i, enemy)
		if awaiting_forced_insertion:
			await forced_insertion_completed
		if inventory.is_dead():
			_lose()
			return
		_enemy_post_turn_phase(i, enemy)

	inventory.grid.tick_corruption()

	if _all_enemies_dead():
		_win()
	else:
		_begin_player_turn()


func request_forced_item_insertion(item_id: String) -> void:
	## Called by EffectForceInsert mid-enemy-turn; Main opens ForcedItemScreen.
	var id := item_id.strip_edges()
	if id.is_empty():
		id = SLIMY_PARASITE_ID
	awaiting_forced_insertion = true
	forced_insertion_requested.emit(id)


func complete_forced_item_insertion() -> void:
	if not awaiting_forced_insertion:
		return
	awaiting_forced_insertion = false
	forced_insertion_completed.emit()


func _enemy_pre_turn_phase(index: int, enemy: EnemyInstance) -> bool:
	## Returns false if enemy dies or is stunned (skip rest of act).
	if enemy.statuses == null:
		enemy.statuses = StatusController.new()
	var result: Dictionary = enemy.statuses.tick_negative_statuses()
	var dmg: int = int(result.get("damage", 0))
	if dmg > 0:
		var hp_before := enemy.current_hp
		enemy.apply_incoming_damage(dmg)
		var dealt := maxi(0, hp_before - enemy.current_hp)
		var dtype := _infer_status_dot_type(result)
		_request_enemy_popup(index, dealt if dealt > 0 else dmg, dtype)
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_ENEMY_STATUS_DOT") % [enemy.get_localized_name(), dmg]
		)
		EventBus.enemy_hp_changed.emit(index, enemy.current_hp, enemy.max_hp)
		if not enemy.is_alive():
			enemy.clear_intention()
			EventBus.enemy_intention_changed.emit(index, enemy.current_intention)
			_on_enemy_defeated(enemy, index)
			EventBus.enemy_died.emit(index)
			return false
	if bool(result.get("skip_turn", false)):
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_ENEMY_STUNNED") % enemy.get_localized_name()
		)
		enemy.begin_enemy_turn()
		enemy.clear_intention()
		EventBus.enemy_intention_changed.emit(index, enemy.current_intention)
		enemy.end_enemy_turn()
		return false
	## FLEEING: escape at the start of this turn before acting.
	if enemy.statuses != null and enemy.statuses.has_status("fleeing"):
		EffectFlee.new().apply(enemy, self, [])
		return false
	return true


func _enemy_start_turn_phase(index: int, enemy: EnemyInstance) -> void:
	if enemy.statuses == null:
		return
	var result: Dictionary = enemy.statuses.tick_positive_statuses()
	var heal_amt: int = int(result.get("heal", 0))
	if heal_amt > 0:
		enemy.heal(heal_amt)
		EventBus.enemy_hp_changed.emit(index, enemy.current_hp, enemy.max_hp)
		_request_enemy_popup(index, heal_amt, "heal")
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_ENEMY_HEAL") % [enemy.get_localized_name(), heal_amt]
		)


func _enemy_pre_action_phase(index: int, enemy: EnemyInstance) -> void:
	enemy.begin_enemy_turn()
	var pre: Dictionary = EnemyAI.trigger_pre_action_phase(enemy)
	if bool(pre.get("triggered", false)):
		var pre_ability: EnemyAbility = pre.get("ability") as EnemyAbility
		if pre_ability != null:
			_ability_executor.execute(enemy, index, pre_ability)


func _enemy_main_action_phase(index: int, enemy: EnemyInstance) -> void:
	var action: Dictionary = EnemyAI.resolve_main_action(enemy, self)
	var ability: EnemyAbility = action.get("ability") as EnemyAbility
	enemy.consume_planned_ability()
	enemy.clear_intention()
	EventBus.enemy_intention_changed.emit(index, enemy.current_intention)

	## Rust miss: skip damaging effects.
	if enemy.statuses != null and enemy.statuses.roll_rust_fail():
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_RUST_MISS") % enemy.get_localized_name()
		)
		_request_player_popup(0, "rust", false, true)
		return

	if ability != null:
		_ability_executor.execute(enemy, index, ability)
	else:
		_enemy_act_legacy_fallback(index, enemy)


func _enemy_post_turn_phase(_index: int, enemy: EnemyInstance) -> void:
	if enemy.statuses != null:
		enemy.statuses.tick_post_turn()
	enemy.end_enemy_turn()


func _enemy_act(index: int, enemy: EnemyInstance) -> void:
	## Legacy entry retained for any external callers — routes through phased pipeline.
	if not _enemy_pre_turn_phase(index, enemy):
		return
	_enemy_start_turn_phase(index, enemy)
	if not enemy.is_alive():
		return
	_enemy_pre_action_phase(index, enemy)
	_enemy_main_action_phase(index, enemy)
	_enemy_post_turn_phase(index, enemy)


func remove_enemy_at(index: int, emit_roster: bool = true) -> void:
	## Called after death fade so the roster no longer holds a corpse slot.
	if index < 0 or index >= enemies.size():
		return
	enemies.remove_at(index)
	_ensure_valid_selection()
	if emit_roster:
		EventBus.enemy_roster_changed.emit()


func purge_dead_enemies() -> void:
	## Remove all HP<=0 combatants (highest index first). Prefer remove_enemy_at after UI fade.
	for i in range(enemies.size() - 1, -1, -1):
		if enemies[i] == null or not enemies[i].is_alive():
			enemies.remove_at(i)
	_ensure_valid_selection()
	EventBus.enemy_roster_changed.emit()


func _enemy_act_legacy_fallback(index: int, enemy: EnemyInstance) -> void:
	var data := enemy.data
	var dmg := data.basic_damage if data else 5
	if enemy.statuses != null:
		dmg = enemy.statuses.modify_outgoing_damage(dmg)
	if GameSettings != null:
		dmg = int(round(float(dmg) * GameSettings.get_enemy_damage_multiplier()))
	var dealt := apply_enemy_damage_to_player(dmg)
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_ENEMY_STRIKE") % [enemy.get_localized_name(), dmg, dealt]
	)
	EventBus.enemy_hp_changed.emit(index, enemy.current_hp, enemy.max_hp)


## --- AbilityEffect combat hooks ---------------------------------------------

func apply_enemy_damage_to_player(damage: int) -> int:
	var incoming := damage
	## Player evasion (if ever applied) negates the hit fully.
	if player_statuses != null and player_statuses.try_consume_evasion():
		EventBus.combat_log_message.emit(tr("KEY_LOG_EVASION_NEGATE"))
		_request_player_popup(0, "physical", false, true)
		return 0
	if player_statuses != null:
		incoming = player_statuses.modify_incoming_damage(incoming)
	var dealt := inventory.apply_damage(incoming, current_block)
	current_block = maxi(0, current_block - incoming)
	EventBus.block_changed.emit(current_block)
	if dealt > 0:
		_request_player_popup(dealt, "physical")
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
	if state == CombatState.PLAYER_TURN:
		var idx := enemies.size() - 1
		instance.evaluate_intention({"block": current_block}, self)
		EventBus.enemy_intention_changed.emit(idx, instance.current_intention)


func remove_enemy_instance(enemy: EnemyInstance, emit_roster: bool = true) -> void:
	## Preferred death cleanup — stable even when other fades shift indices.
	var index := enemies.find(enemy)
	if index < 0:
		return
	remove_enemy_at(index, emit_roster)


func _on_enemy_defeated(enemy: EnemyInstance, _index: int) -> void:
	if enemy == null:
		return
	## Pocket thief: return stolen Neuro-Chips on death.
	if enemy.stolen_chips > 0:
		var refunded := NeuroChipItem.grant_to_inventory(inventory, enemy.stolen_chips)
		if refunded > 0:
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_CHIPS_RECOVERED") % [enemy.get_localized_name(), refunded]
			)
		enemy.stolen_chips = 0
	## Faceless Lady: permanent removal from spawn pools once slain.
	if enemy.data != null and enemy.data.id.strip_edges().to_lower() == "faceless_lady":
		if StoryEventManager != null:
			StoryEventManager.mark_faceless_lady_defeated()
	## Summoned creatures flee immediately when their master dies.
	_flee_summons_of(enemy)


func _apply_on_hit_weapon_statuses(placed: PlacedItem, enemy_index: int) -> void:
	if placed == null or placed.data == null:
		return
	if TraitManager.has_trait(placed.data, "TRAIT_FANG_POISON"):
		var stacks := TraitManager.get_trait_value(placed.data, "TRAIT_FANG_POISON", 3)
		apply_status_to_enemy(enemy_index, "poison", maxi(1, stacks))


func _flee_summons_of(master: EnemyInstance) -> void:
	if master == null:
		return
	var fleeing: Array[EnemyInstance] = []
	for other: EnemyInstance in enemies:
		if other == null or not other.is_alive() or other == master:
			continue
		if not other.is_summoned_creature():
			continue
		if other.get_summoner() == master or (
			other.get_summoner() == null and master.data != null and master.data.id == "slaver_master"
		):
			fleeing.append(other)
	for minion in fleeing:
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_SUMMON_FLED") % [minion.get_localized_name(), master.get_localized_name()]
		)
		minion.stolen_chips = 0
		if minion.statuses != null:
			minion.statuses.clear_combat_statuses()
		minion.current_hp = 0
		var idx := enemies.find(minion)
		if idx >= 0:
			minion.clear_intention()
			EventBus.enemy_intention_changed.emit(idx, minion.current_intention)
			EventBus.enemy_died.emit(idx)


func apply_player_status(status_id: String, potency: int) -> void:
	if player_statuses == null:
		player_statuses = StatusController.new()
	player_statuses.apply_status_by_id(status_id, maxi(1, potency))


func apply_status_to_enemy(index: int, status_id: String, amount: int = 1) -> void:
	if index < 0 or index >= enemies.size():
		return
	var enemy: EnemyInstance = enemies[index]
	if enemy == null:
		return
	if enemy.statuses == null:
		enemy.statuses = StatusController.new()
	enemy.statuses.apply_status_by_id(status_id, maxi(1, amount))


func apply_status_to_enemy_instance(enemy: EnemyInstance, status_id: String, amount: int = 1) -> void:
	if enemy == null:
		return
	if enemy.statuses == null:
		enemy.statuses = StatusController.new()
	enemy.statuses.apply_status_by_id(status_id, maxi(1, amount))


func _request_enemy_popup(
	index: int,
	amount: int,
	damage_type: String = "physical",
	is_crit: bool = false,
	is_miss: bool = false
) -> void:
	EventBus.damage_popup_requested.emit("enemy", index, amount, damage_type, is_crit, is_miss)


func _request_player_popup(
	amount: int,
	damage_type: String = "physical",
	is_crit: bool = false,
	is_miss: bool = false
) -> void:
	EventBus.damage_popup_requested.emit("player", -1, amount, damage_type, is_crit, is_miss)


func _infer_status_dot_type(tick_result: Dictionary) -> String:
	var logs: PackedStringArray = tick_result.get("logs", PackedStringArray()) as PackedStringArray
	for entry in logs:
		var s := str(entry)
		if s.begins_with("burn"):
			return "burn"
		if s.begins_with("poison"):
			return "poison"
	return "poison"


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
	if player_statuses != null:
		player_statuses.clear_combat_statuses()
	for enemy: EnemyInstance in enemies:
		if enemy != null and enemy.statuses != null:
			enemy.statuses.clear_combat_statuses()
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
	if player_statuses != null:
		player_statuses.clear_combat_statuses()
	state_changed.emit(state)
