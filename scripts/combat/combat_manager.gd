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
const WAR_MODULE_TEMP_DMG := 2

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
## Slimy parasite already in the grid when combat began — skip DoT on turn 1.
var _parasite_at_combat_start: bool = false
## Mid-enemy-turn pause while ForcedItemScreen is open.
var awaiting_forced_insertion: bool = false
## Presentation hooks bound by CombatUI (async Callables).
var _play_enemy_attack_fx: Callable
var _play_enemy_flee_fx: Callable
var _play_player_hit_fx: Callable
var _play_enemy_cast_fx: Callable
const ENEMY_ACTION_GAP := 0.25
const ENEMY_HEAL_BEAT := 0.4
const PLAYER_MULTI_SHOT_GAP := 0.22

## True while a multi-shot player resolution is awaiting presentation beats.
var _player_action_busy: bool = false


func setup(p_inventory: InventoryController, p_stats: PlayerStats = null) -> void:
	inventory = p_inventory
	if p_stats != null:
		player_stats = p_stats
	_ensure_ability_executor()


func bind_presentation(
	attack_fx: Callable,
	flee_fx: Callable,
	player_hit_fx: Callable,
	cast_fx: Callable = Callable()
) -> void:
	_play_enemy_attack_fx = attack_fx
	_play_enemy_flee_fx = flee_fx
	_play_player_hit_fx = player_hit_fx
	_play_enemy_cast_fx = cast_fx


func _ensure_ability_executor() -> void:
	if _ability_executor == null:
		_ability_executor = EnemyAbilityExecutor.new(self)
	else:
		_ability_executor.set_combat(self)


func is_player_turn_active() -> bool:
	return state == CombatState.PLAYER_TURN


func is_in_combat() -> bool:
	return state != CombatState.INACTIVE


func start_combat(enemy_datas: Array[EnemyData], max_attackers: int = -1) -> void:
	_ensure_ability_executor()
	_player_action_busy = false
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
	_reset_all_item_combat_uses()
	_parasite_at_combat_start = _has_item_in_grid(SLIMY_PARASITE_ID)
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
	_clear_temporary_weapon_bonuses()
	max_ap = inventory.get_max_ap()
	current_ap = max_ap
	player_turn_index += 1
	if player_turn_index == 1:
		current_ap += _eye_of_pale_maiden_turn1_ap_mod()
		current_ap = maxi(0, current_ap)
	_apply_slimy_parasite_ap_cap()
	_reset_all_item_turn_uses()
	_tick_all_item_cooldowns()
	## Passive spatial armor is previewed as (+N) during the player turn and
	## committed into real Block at the start of the enemy turn.


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
	## Parasite already lodged at combat start: first tick is turn 2 (grace on turn 1).
	if _parasite_at_combat_start and player_turn_index <= 1:
		return true
	var dealt := inventory.apply_damage(PARASITE_TURN_DAMAGE, 0)
	_request_player_popup(dealt if dealt > 0 else PARASITE_TURN_DAMAGE, "poison")
	if dealt > 0 or PARASITE_TURN_DAMAGE > 0:
		_trigger_player_hit_feedback(maxi(dealt, PARASITE_TURN_DAMAGE))
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
		_trigger_player_hit_feedback(maxi(dealt, dmg))
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
	_clear_temporary_weapon_bonuses()
	EventBus.inventory_changed.emit()


func end_player_turn() -> void:
	if state != CombatState.PLAYER_TURN:
		return
	if _player_action_busy:
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
	if _player_action_busy:
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
	if not data.can_use_this_combat():
		return false
	if data.is_on_cooldown():
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
	data.current_combat_uses += 1
	EventBus.ap_changed.emit(current_ap, max_ap)

	## Rust jam: AP already spent, effect skipped.
	if player_statuses != null and player_statuses.roll_rust_fail():
		EventBus.combat_log_message.emit(tr("KEY_LOG_RUST_JAM") % data.get_localized_name())
		_request_player_popup(0, "rust", false, true)
		_consume_charge_if_needed(placed)
		data.start_cooldown()
		EventBus.combat_item_availability_changed.emit()
		return true

	match data.target_type:
		ItemData.TargetType.SELF:
			_resolve_self(placed)
		ItemData.TargetType.ALL_ENEMIES:
			_resolve_all_enemies(placed)
		_:
			if _is_auto_scatter_weapon(data):
				_consume_charge_if_needed(placed)
				data.start_cooldown()
				EventBus.combat_item_availability_changed.emit()
				_resolve_auto_scatter_async(placed)
				return true
			_resolve_single_enemy(placed)

	_consume_charge_if_needed(placed)
	data.start_cooldown()
	EventBus.combat_item_availability_changed.emit()

	_finish_player_activation()
	return true


func _finish_player_activation() -> void:
	if inventory != null and inventory.is_dead():
		_lose()
		return
	if _all_enemies_dead():
		_win()


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
		if data.is_on_cooldown():
			EventBus.combat_log_message.emit(tr("KEY_LOG_ITEM_COOLDOWN") % data.get_localized_name())
		else:
			EventBus.combat_log_message.emit(tr("KEY_LOG_NO_USES"))
	elif not data.can_use_this_combat():
		EventBus.combat_log_message.emit(tr("KEY_LOG_NO_COMBAT_USES"))
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
	var killed := _deal_damage_to(target_index, dmg, data.get_localized_name())
	if killed:
		_apply_oracle_kill_bonus(placed, 1)
	_apply_on_hit_weapon_statuses(placed, target_index)
	_apply_armorless_adjacent_heal_on_hit(placed)


func _is_auto_scatter_weapon(data: ItemData) -> bool:
	return data != null and TraitManager.has_trait(data, "TRAIT_AUTO_SCATTER")


func _resolve_auto_scatter_async(placed: PlacedItem) -> void:
	## 3-shot scatter: shot 1 guaranteed on selected target; shots 2–3 random living enemies.
	if placed == null or placed.data == null:
		_finish_player_activation()
		return
	_player_action_busy = true
	EventBus.combat_item_availability_changed.emit()

	var data := placed.data
	var shot_count := maxi(1, TraitManager.get_trait_value(data, "TRAIT_AUTO_SCATTER", 3))
	var source_name := data.get_localized_name()
	var trait_bonus := _consume_attack_trait_bonus(placed)
	var killed_count := 0
	var any_hit := false

	for shot_i in shot_count:
		if state != CombatState.PLAYER_TURN:
			break
		if shot_i > 0:
			if _living_enemy_indices().is_empty():
				break
			await get_tree().create_timer(PLAYER_MULTI_SHOT_GAP).timeout
			if state != CombatState.PLAYER_TURN:
				break

		var idx := -1
		if shot_i == 0:
			_ensure_valid_selection()
			idx = target_index
			if idx < 0 or idx >= enemies.size() or not enemies[idx].is_alive():
				idx = _pick_random_living_enemy_index()
		else:
			idx = _pick_random_living_enemy_index()

		if idx < 0:
			break

		var dmg := _calc_damage(placed)
		if shot_i == 0:
			dmg += trait_bonus
		any_hit = true
		if _deal_damage_to(idx, dmg, source_name):
			killed_count += 1
		_apply_on_hit_weapon_statuses(placed, idx)

	if killed_count > 0:
		_apply_oracle_kill_bonus(placed, killed_count)
	if any_hit:
		_apply_armorless_adjacent_heal_on_hit(placed)

	_player_action_busy = false
	EventBus.combat_item_availability_changed.emit()
	_finish_player_activation()


func _pick_random_living_enemy_index() -> int:
	var living := _living_enemy_indices()
	if living.is_empty():
		return -1
	return living[randi() % living.size()]


func _resolve_all_enemies(placed: PlacedItem) -> void:
	var data := placed.data
	var dmg := _calc_damage(placed)
	var trait_bonus := _consume_attack_trait_bonus(placed)
	dmg += trait_bonus
	var living := _living_enemy_indices()
	var damage_type := "burn" if _item_applies_burn(data) else "physical"
	var killed_count := 0
	for idx: int in living:
		if _deal_damage_to(idx, dmg, data.get_localized_name(), true, damage_type):
			killed_count += 1
		_apply_on_hit_weapon_statuses(placed, idx)
	if killed_count > 0:
		_apply_oracle_kill_bonus(placed, killed_count)
	_apply_armorless_adjacent_heal_on_hit(placed)


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
	if data.item_type != null and data.item_type.id.to_upper() in ["CONSUMABLE", "ACTIVE_MODULE"]:
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
) -> bool:
	if index < 0 or index >= enemies.size():
		return false
	var enemy: EnemyInstance = enemies[index]
	if not enemy.is_alive():
		return false
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
		return false
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
		return true
	elif state == CombatState.PLAYER_TURN:
		reevaluate_enemy_intention(index)
	return false


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
		current_ap += TraitManager.get_trait_value(data, "TRAIT_GIVE_AP", 1)
		EventBus.ap_changed.emit(current_ap, max_ap)
	if TraitManager.has_trait(data, "TRAIT_NEURO_STIM"):
		current_ap += TraitManager.get_trait_value(data, "TRAIT_NEURO_STIM", 2)
		EventBus.ap_changed.emit(current_ap, max_ap)
	if TraitManager.has_trait(data, "TRAIT_SYNAPSE_BOOSTER"):
		current_ap += TraitManager.get_trait_value(data, "TRAIT_SYNAPSE_BOOSTER", 4)
		EventBus.ap_changed.emit(current_ap, max_ap)
	if TraitManager.has_trait(data, "TRAIT_PERM_STRENGTH"):
		var str_amt := TraitManager.get_trait_value(data, "TRAIT_PERM_STRENGTH", 1)
		if player_stats != null and str_amt != 0:
			player_stats.add_stat_bonus("strength", str_amt)
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_PERM_STAT_GAIN") % [data.get_localized_name(), tr("KEY_STR"), str_amt]
			)
	if TraitManager.has_trait(data, "TRAIT_PERM_INTELLIGENCE"):
		var int_amt := TraitManager.get_trait_value(data, "TRAIT_PERM_INTELLIGENCE", 1)
		if player_stats != null and int_amt != 0:
			player_stats.add_stat_bonus("intelligence", int_amt)
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_PERM_STAT_GAIN") % [data.get_localized_name(), tr("KEY_INT"), int_amt]
			)
	if TraitManager.has_trait(data, "TRAIT_PERM_ENDURANCE"):
		var end_amt := TraitManager.get_trait_value(data, "TRAIT_PERM_ENDURANCE", 1)
		if player_stats != null and end_amt != 0:
			player_stats.add_stat_bonus("endurance", end_amt)
			if inventory != null:
				inventory.apply_actor_stats(player_stats)
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_PERM_STAT_GAIN") % [data.get_localized_name(), tr("KEY_END"), end_amt]
			)
	if TraitManager.has_trait(data, "TRAIT_CLEANSE_DEBUFFS"):
		if player_statuses != null:
			player_statuses.clear_debuffs()
		inventory.grid.clear_all_corruption()
	if TraitManager.has_trait(data, "TRAIT_NEURON_AMP") or data.is_neuron_amplifier():
		## Combat allows fatal self-use (current_hp may drop to 0).
		var cost := inventory.get_neuron_amplifier_hp_cost()
		inventory.pay_neuron_amplifier_hp(true)
		var ap_gain := TraitManager.get_trait_value(data, "TRAIT_NEURON_AMP", 1)
		if ap_gain <= 0:
			ap_gain = 1
		current_ap += ap_gain
		EventBus.ap_changed.emit(current_ap, max_ap)
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_NEURON_AMP") % [data.get_localized_name(), cost, ap_gain]
		)
	if TraitManager.has_trait(data, "TRAIT_WAR_MODULE"):
		var affected := _apply_war_module_adjacency_buff(placed)
		if affected > 0:
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_WAR_MODULE_BUFF") % [data.get_localized_name(), affected, WAR_MODULE_TEMP_DMG]
			)
			EventBus.inventory_changed.emit()


func _resolve_consumable_enemy(placed: PlacedItem, enemy_index: int) -> void:
	var data := placed.data
	if TraitManager.has_trait(data, "TRAIT_DOT_MULTIPLIER"):
		_apply_dot_multiplier_to_enemy(enemy_index, TraitManager.get_trait_value(data, "TRAIT_DOT_MULTIPLIER", 3))
		return
	var dealt := 0
	if TraitManager.has_trait(data, "TRAIT_BURN_DAMAGE"):
		## Damage comes from the item roll; the trait only applies Burn.
		var burn_hit: int = data.roll_damage(player_stats)
		if burn_hit <= 0:
			burn_hit = TraitManager.get_trait_value(data, "TRAIT_BURN_DAMAGE", 9)
		_deal_damage_to(enemy_index, burn_hit, data.get_localized_name(), true, "burn")
		dealt = burn_hit
		if enemy_index >= 0 and enemy_index < enemies.size():
			var stacks := _dot_stacks_with_amplify(placed, TraitManager.BURN_APPLY_STACKS)
			apply_status_to_enemy(enemy_index, BurnStatus.STATUS_ID, stacks)
	if dealt == 0:
		_deal_damage_to(enemy_index, data.roll_damage(player_stats), data.get_localized_name())


func _reset_all_item_turn_uses() -> void:
	if inventory == null or inventory.grid == null:
		return
	for placed: PlacedItem in inventory.grid.items:
		if placed != null and placed.data != null:
			placed.data.reset_turn_uses()


func _reset_all_item_combat_uses() -> void:
	if inventory == null or inventory.grid == null:
		return
	for placed: PlacedItem in inventory.grid.items:
		if placed != null and placed.data != null:
			placed.data.reset_combat_uses()


func _clear_temporary_weapon_bonuses() -> void:
	if inventory == null or inventory.grid == null:
		return
	for placed: PlacedItem in inventory.grid.items:
		if placed == null or placed.data == null:
			continue
		if placed.data.temp_flat_damage_bonus == 0:
			continue
		placed.data.clear_temporary_combat_bonuses()


func _tick_all_item_cooldowns() -> void:
	if inventory == null or inventory.grid == null:
		return
	for placed: PlacedItem in inventory.grid.items:
		if placed != null and placed.data != null:
			placed.data.tick_cooldown()
	EventBus.combat_item_availability_changed.emit()


func _begin_enemy_turn() -> void:
	## Hide (+N) preview first, then fold it into Block for a single number.
	_set_state(CombatState.ENEMY_TURN)
	_commit_passive_armor_into_block()
	EventBus.combat_log_message.emit(tr("KEY_LOG_ENEMY_TURN"))
	## Re-open attacker budget for the act phase (matches telegraphed plans).
	reset_attacker_slots()
	await _run_enemy_actions()


func _commit_passive_armor_into_block() -> void:
	if inventory == null or inventory.grid == null:
		return
	var passive := TraitManager.calc_total_spatial_passive_armor(inventory.grid, false)
	if passive > 0:
		_gain_block(passive, tr("KEY_PASSIVE"))
	elif passive < 0:
		var before := current_block
		current_block = maxi(0, current_block + passive)
		if current_block != before:
			EventBus.block_changed.emit(current_block)
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_BLOCK") % [tr("KEY_PASSIVE"), passive, current_block]
			)


func _run_enemy_actions() -> void:
	## Sequential enemy acts with awaited attack/flee presentation.
	for i in enemies.size():
		var enemy: EnemyInstance = enemies[i]
		if enemy == null or not enemy.is_alive():
			continue
		## 1. Pre-turn (DoT / Stun / Flee check)
		var pre := await _enemy_pre_turn_phase_async(i, enemy)
		if not pre:
			if inventory != null and inventory.is_dead():
				_lose()
				return
			await get_tree().create_timer(ENEMY_ACTION_GAP).timeout
			continue
		_enemy_start_turn_phase(i, enemy)
		if not enemy.is_alive():
			await get_tree().create_timer(ENEMY_ACTION_GAP).timeout
			continue
		_enemy_pre_action_phase(i, enemy)
		## 2-3. Attack presentation (if offensive), then resolve intent/effects.
		await _enemy_main_action_phase_async(i, enemy)
		if awaiting_forced_insertion:
			await forced_insertion_completed
		if inventory != null and inventory.is_dead():
			_lose()
			return
		_enemy_post_turn_phase(i, enemy)
		## 4. Short pause between enemy turns.
		await get_tree().create_timer(ENEMY_ACTION_GAP).timeout

	## 5. End of enemy turn checks & corruption tick.
	if inventory != null and inventory.grid != null:
		inventory.grid.tick_corruption()

	if _all_enemies_dead():
		_win()
	else:
		_begin_player_turn()


func _enemy_pre_turn_phase_async(index: int, enemy: EnemyInstance) -> bool:
	## Returns false if enemy dies, is stunned, or flees (skip rest of act).
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
		enemy.clear_intention()
		EventBus.enemy_intention_changed.emit(index, enemy.current_intention)
		enemy.end_enemy_turn()
		return false
	## FLEEING: play flee animation, then mark escaped.
	if enemy.statuses != null and enemy.statuses.has_status("fleeing"):
		await _await_enemy_flee_fx(index)
		EffectFlee.new().apply(enemy, self, [])
		return false
	return true


func _enemy_main_action_phase_async(index: int, enemy: EnemyInstance) -> void:
	var action: Dictionary = EnemyAI.resolve_main_action(enemy, self)
	var ability: EnemyAbility = action.get("ability") as EnemyAbility
	enemy.consume_planned_ability()
	enemy.clear_intention()
	EventBus.enemy_intention_changed.emit(index, enemy.current_intention)

	var is_heal := _ability_is_heal(ability)
	var offensive := _ability_is_offensive(ability)

	## Support / mass heal: cast pulse, then resolve (heal FX via notify_enemy_healed).
	if is_heal:
		await _await_enemy_cast_fx(index)
		if enemy.statuses != null and enemy.statuses.roll_rust_fail():
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_RUST_MISS") % enemy.get_localized_name()
			)
			_request_player_popup(0, "rust", false, true)
			return
		if ability != null:
			_ability_executor.execute(enemy, index, ability)
		await get_tree().create_timer(ENEMY_HEAL_BEAT).timeout
		return

	## Offensive: telegraph lunge, then resolve damage / hit feedback.
	if offensive:
		await _await_enemy_attack_fx(index)

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


func _ability_is_heal(ability: EnemyAbility) -> bool:
	if ability == null:
		return false
	if ability.type == EnemyAbility.AbilityType.HEAL:
		return true
	return ability.infer_main_effect() == "heal"


func _ability_is_offensive(ability: EnemyAbility) -> bool:
	if ability == null:
		## Legacy fallback strike.
		return true
	var effect := ability.main_effect.strip_edges().to_lower()
	if effect in ["damage", "multi_hit", "steal_chips", "force_insert"]:
		return true
	match ability.type:
		EnemyAbility.AbilityType.DAMAGE, EnemyAbility.AbilityType.MULTI_HIT:
			return true
		_:
			return ability.target_type.strip_edges().to_lower() == "player" and effect == "status"


func _await_enemy_attack_fx(index: int) -> void:
	if _play_enemy_attack_fx.is_valid():
		await _play_enemy_attack_fx.call(index)


func _await_enemy_flee_fx(index: int) -> void:
	if _play_enemy_flee_fx.is_valid():
		await _play_enemy_flee_fx.call(index)


func _await_enemy_cast_fx(index: int) -> void:
	if _play_enemy_cast_fx.is_valid():
		await _play_enemy_cast_fx.call(index)


func _enemy_pre_turn_phase(index: int, enemy: EnemyInstance) -> bool:
	## Sync wrapper kept for legacy callers; prefer async path in enemy turn.
	## FLEEING without animation (legacy).
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
		enemy.clear_intention()
		EventBus.enemy_intention_changed.emit(index, enemy.current_intention)
		enemy.end_enemy_turn()
		return false
	if enemy.statuses != null and enemy.statuses.has_status("fleeing"):
		EffectFlee.new().apply(enemy, self, [])
		return false
	return true


func _enemy_main_action_phase(index: int, enemy: EnemyInstance) -> void:
	## Sync legacy path (no presentation waits).
	var action: Dictionary = EnemyAI.resolve_main_action(enemy, self)
	var ability: EnemyAbility = action.get("ability") as EnemyAbility
	enemy.consume_planned_ability()
	enemy.clear_intention()
	EventBus.enemy_intention_changed.emit(index, enemy.current_intention)

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


func _enemy_start_turn_phase(index: int, enemy: EnemyInstance) -> void:
	if enemy.statuses == null:
		return
	var result: Dictionary = enemy.statuses.tick_positive_statuses()
	var heal_amt: int = int(result.get("heal", 0))
	if heal_amt > 0:
		var healed := enemy.heal(heal_amt)
		notify_enemy_healed(enemy, healed)
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_ENEMY_HEAL") % [enemy.get_localized_name(), healed]
		)


func _enemy_pre_action_phase(index: int, enemy: EnemyInstance) -> void:
	enemy.begin_enemy_turn()
	var pre: Dictionary = EnemyAI.trigger_pre_action_phase(enemy)
	if bool(pre.get("triggered", false)):
		var pre_ability: EnemyAbility = pre.get("ability") as EnemyAbility
		if pre_ability != null:
			_ability_executor.execute(enemy, index, pre_ability)


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
		_trigger_player_hit_feedback(dealt)
	return dealt


func _trigger_player_hit_feedback(dealt: int) -> void:
	if _play_player_hit_fx.is_valid():
		_play_player_hit_fx.call(dealt)


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


func notify_enemy_healed(enemy: EnemyInstance, amount: int) -> void:
	## Called from EffectHeal after each healed subject (self / ally / mass heal).
	var idx := enemies.find(enemy)
	if idx < 0:
		return
	EventBus.enemy_hp_changed.emit(idx, enemy.current_hp, enemy.max_hp)
	EventBus.enemy_healed.emit(idx, maxi(amount, 0))
	if amount > 0:
		_request_enemy_popup(idx, amount, "heal")


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
	## Pocket thief: return stolen Neuro-Chips on death (raw restore, no bonus).
	if enemy.stolen_chips > 0:
		var refunded: int = 0
		if GameManager != null:
			refunded = GameManager.restore_chips(enemy.stolen_chips)
		if refunded > 0:
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_CHIPS_RECOVERED") % [enemy.get_localized_name(), refunded]
			)
		enemy.stolen_chips = 0
	## Faceless Lady: permanent removal from spawn pools once slain.
	if enemy.data != null and enemy.data.id.strip_edges().to_lower() == "faceless_lady":
		if StoryEventManager != null:
			StoryEventManager.mark_faceless_lady_defeated()
	## Summoned creatures break and prepare to flee when their master dies.
	_break_summons_of(enemy)


func _apply_on_hit_weapon_statuses(placed: PlacedItem, enemy_index: int) -> void:
	if placed == null or placed.data == null:
		return
	if TraitManager.has_trait(placed.data, "TRAIT_FANG_POISON"):
		var stacks := TraitManager.get_trait_value(placed.data, "TRAIT_FANG_POISON", 3)
		apply_status_to_enemy(enemy_index, "poison", _dot_stacks_with_amplify(placed, maxi(1, stacks)))
	var burn_stacks := _burn_stacks_from_item(placed.data)
	if burn_stacks > 0:
		apply_status_to_enemy(
			enemy_index,
			BurnStatus.STATUS_ID,
			_dot_stacks_with_amplify(placed, burn_stacks)
		)


func _dot_stacks_with_amplify(placed: PlacedItem, base_stacks: int) -> int:
	## Adjacent amplifier modules with TRAIT_DOT_AMPLIFY add +1 stack each.
	var bonus := 0
	if inventory != null and inventory.grid != null:
		bonus = inventory.grid.get_adjacent_dot_amplify_bonus(placed)
	return maxi(1, base_stacks) + bonus


func _apply_armorless_adjacent_heal_on_hit(placed: PlacedItem) -> void:
	## Devourer-style sustain works only if no armor exists in the body grid.
	if placed == null or placed.data == null:
		return
	if not placed.data.is_weapon():
		return
	if inventory == null or inventory.grid == null:
		return
	if not inventory.get_equipped_items_by_type("armor").is_empty():
		return
	var heal_bonus := inventory.grid.get_adjacent_heal_on_hit_bonus(placed)
	if heal_bonus <= 0:
		return
	var before := inventory.current_hp
	inventory.current_hp = mini(inventory.max_hp, inventory.current_hp + heal_bonus)
	var healed := inventory.current_hp - before
	if healed <= 0:
		return
	EventBus.player_hp_changed.emit(inventory.current_hp, inventory.max_hp)
	_request_player_popup(healed, "heal")
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_ARMORLESS_HEAL_ON_HIT") % [placed.data.get_localized_name(), healed]
	)


func _apply_war_module_adjacency_buff(placed: PlacedItem) -> int:
	## Apply +2 temporary damage to adjacent functional weapons for this turn.
	if placed == null or placed.data == null or inventory == null or inventory.grid == null:
		return 0
	var count := 0
	for neighbour: PlacedItem in inventory.grid.get_adjacent_items(placed):
		if neighbour == null or neighbour.data == null:
			continue
		if not inventory.grid.is_item_functional(neighbour):
			continue
		if not neighbour.data.is_weapon():
			continue
		neighbour.data.temp_flat_damage_bonus += WAR_MODULE_TEMP_DMG
		count += 1
	return count


func _apply_oracle_kill_bonus(placed: PlacedItem, kills: int) -> void:
	if placed == null or placed.data == null or kills <= 0:
		return
	var data := placed.data
	if not TraitManager.has_trait(data, "TRAIT_ORACLE_KILL_SCALING"):
		return
	data.permanent_damage_bonus += kills
	EventBus.inventory_changed.emit()
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_ORACLE_KILL_BONUS") % kills
	)


func _apply_dot_multiplier_to_enemy(enemy_index: int, multiplier: int) -> void:
	if enemy_index < 0 or enemy_index >= enemies.size():
		return
	var enemy := enemies[enemy_index]
	if enemy == null or enemy.statuses == null:
		return
	var changed: Dictionary = enemy.statuses.multiply_dot_stacks(multiplier)
	if changed.is_empty():
		EventBus.combat_log_message.emit(tr("KEY_LOG_DOT_MULTIPLIER_NONE"))
		return
	var parts: PackedStringArray = []
	for sid_variant in changed.keys():
		var status_id := str(sid_variant)
		parts.append("%s x%d" % [status_id.capitalize(), int(changed[status_id])])
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_DOT_MULTIPLIER_APPLIED") % [enemy.get_localized_name(), ", ".join(parts)]
	)


func _has_functional_analyzer() -> bool:
	if inventory == null or inventory.grid == null:
		return false
	for placed: PlacedItem in inventory.grid.items:
		if placed == null or placed.data == null:
			continue
		if not inventory.grid.is_item_functional(placed):
			continue
		if TraitManager.has_trait(placed.data, "TRAIT_STATUS_ANALYZER"):
			return true
	return false


func _trigger_status_apply_direct_damage(enemy_index: int) -> void:
	if enemy_index < 0 or enemy_index >= enemies.size():
		return
	if not _has_functional_analyzer():
		return
	var enemy := enemies[enemy_index]
	if enemy == null or not enemy.is_alive():
		return
	enemy.current_hp = maxi(0, enemy.current_hp - 1)
	_request_enemy_popup(enemy_index, 1, "physical", false, false)
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_STATUS_ANALYZER_PING") % enemy.get_localized_name()
	)
	EventBus.enemy_hp_changed.emit(enemy_index, enemy.current_hp, enemy.max_hp)
	if not enemy.is_alive():
		enemy.clear_intention()
		EventBus.enemy_intention_changed.emit(enemy_index, enemy.current_intention)
		_on_enemy_defeated(enemy, enemy_index)
		EventBus.enemy_died.emit(enemy_index)
		_ensure_valid_selection()


func _item_applies_burn(data: ItemData) -> bool:
	return _burn_stacks_from_item(data) > 0


func _burn_stacks_from_item(data: ItemData) -> int:
	if data == null:
		return 0
	if TraitManager.has_trait(data, "TRAIT_FUEL_BURST"):
		return maxi(1, TraitManager.get_trait_value(data, "TRAIT_FUEL_BURST", 2))
	if TraitManager.has_trait(data, "TRAIT_APPLY_BURN"):
		return maxi(1, TraitManager.get_trait_value(data, "TRAIT_APPLY_BURN", 2))
	if TraitManager.has_trait(data, "TRAIT_BURN_DAMAGE"):
		return TraitManager.BURN_APPLY_STACKS
	return 0


func _break_summons_of(master: EnemyInstance) -> void:
	## Master down → minions get fleeing + flee intention; escape on their next act start.
	if master == null:
		return
	for other: EnemyInstance in enemies:
		if other == null or not other.is_alive() or other == master:
			continue
		if not other.is_summoned_creature():
			continue
		if other.get_summoner() != master and not (
			other.get_summoner() == null and master.data != null and master.data.id == "slaver_master"
		):
			continue
		if other.statuses != null and other.statuses.has_status(StatusEffect.FLEEING):
			continue
		other.mark_fleeing_next_turn()
		var idx := enemies.find(other)
		if idx >= 0:
			EventBus.enemy_intention_changed.emit(idx, other.current_intention)
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_SUMMON_FLED") % [other.get_localized_name(), master.get_localized_name()]
		)


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
	var applied := enemy.statuses.apply_status_by_id(status_id, maxi(1, amount))
	if applied != null:
		_trigger_status_apply_direct_damage(index)


func apply_status_to_enemy_instance(enemy: EnemyInstance, status_id: String, amount: int = 1) -> void:
	if enemy == null:
		return
	if enemy.statuses == null:
		enemy.statuses = StatusController.new()
	var applied := enemy.statuses.apply_status_by_id(status_id, maxi(1, amount))
	if applied != null:
		_trigger_status_apply_direct_damage(enemies.find(enemy))


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
	_player_action_busy = false
	if player_statuses != null:
		player_statuses.clear_combat_statuses()
	for enemy: EnemyInstance in enemies:
		if enemy != null and enemy.statuses != null:
			enemy.statuses.clear_combat_statuses()
	_run_on_combat_end_triggers()
	_set_state(CombatState.VICTORY)
	EventBus.combat_log_message.emit(tr("KEY_LOG_VICTORY"))
	EventBus.combat_ended.emit(true)


func _run_on_combat_end_triggers() -> void:
	## Passive implants / modules with on_combat_end hooks (victory only).
	if inventory == null or inventory.grid == null:
		return
	for placed: PlacedItem in inventory.grid.items:
		if placed == null or placed.data == null:
			continue
		if not inventory.grid.is_item_functional(placed):
			continue
		placed.data.on_combat_end(inventory)


func _lose() -> void:
	## Abort combat and hand control to the global GAME_OVER state.
	_player_action_busy = false
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
