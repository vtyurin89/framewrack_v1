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
var state: CombatState = CombatState.INACTIVE

## Runtime enemy instances: { data: EnemyData, hp: int, is_selected: bool }
var enemies: Array[Dictionary] = []

var current_ap: int = 0
var max_ap: int = 3
var current_block: int = 0
var target_index: int = 0


func setup(p_inventory: InventoryController) -> void:
	inventory = p_inventory


func is_player_turn_active() -> bool:
	return state == CombatState.PLAYER_TURN


func start_combat(enemy_datas: Array[EnemyData]) -> void:
	enemies.clear()
	for data: EnemyData in enemy_datas:
		enemies.append({"data": data, "hp": data.max_hp, "is_selected": false})
	current_block = 0
	_select_first_living_enemy()
	var ids: Array[String] = []
	for data: EnemyData in enemy_datas:
		ids.append(data.id)
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
	if int(enemies[index]["hp"]) <= 0:
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
		enemies[i]["is_selected"] = (i == index)
	target_index = index
	EventBus.enemy_selected.emit(index)


func can_activate_item(placed: PlacedItem) -> bool:
	if state != CombatState.PLAYER_TURN:
		return false
	if placed == null or placed.data == null:
		return false
	var data: ItemData = placed.data
	if not data.usable or data.ap_cost <= 0:
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
	elif not data.usable or data.ap_cost <= 0:
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
	var dmg := _calc_damage(placed)
	_deal_damage_to(target_index, dmg, placed.data.get_localized_name())


func _resolve_all_enemies(placed: PlacedItem) -> void:
	var dmg := _calc_damage(placed)
	var living := _living_enemy_indices()
	for idx: int in living:
		_deal_damage_to(idx, dmg, placed.data.get_localized_name())


func _resolve_self(placed: PlacedItem) -> void:
	var armor := placed.data.get_effective_armor()
	if armor <= 0 and placed.data.block_amount > 0:
		armor = placed.data.block_amount
	if armor > 0:
		current_block += armor
		EventBus.block_changed.emit(current_block)
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_BLOCK") % [placed.data.get_localized_name(), armor, current_block]
		)
	else:
		EventBus.combat_log_message.emit(tr("KEY_LOG_ACTIVATED") % placed.data.get_localized_name())


func _calc_damage(placed: PlacedItem) -> int:
	var adjacency_bonus: int = inventory.grid.get_adjacency_damage_bonus_for(placed)
	return placed.data.get_effective_damage() + adjacency_bonus


func _deal_damage_to(index: int, dmg: int, source_name: String) -> void:
	if index < 0 or index >= enemies.size():
		return
	var entry: Dictionary = enemies[index]
	if int(entry["hp"]) <= 0:
		return
	var adjacency_note := ""
	entry["hp"] = maxi(0, int(entry["hp"]) - dmg)
	enemies[index] = entry
	var ename: String = (entry["data"] as EnemyData).get_localized_name()
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_DAMAGE") % [source_name, dmg, adjacency_note, ename]
	)
	EventBus.enemy_hp_changed.emit(index, int(entry["hp"]), (entry["data"] as EnemyData).max_hp)
	if int(entry["hp"]) <= 0:
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
	for i in enemies.size():
		var entry: Dictionary = enemies[i]
		if int(entry["hp"]) <= 0:
			continue
		var data: EnemyData = entry["data"]
		_enemy_act(i, data)
		if inventory.is_dead():
			_lose()
			return

	inventory.grid.tick_corruption()

	if _all_enemies_dead():
		_win()
	else:
		_begin_player_turn()


func _enemy_act(index: int, data: EnemyData) -> void:
	var attack := data.choose_attack()
	match attack:
		EnemyData.AttackType.SPECIAL:
			_enemy_special(index, data)
		_:
			_enemy_basic(index, data)


func _enemy_basic(index: int, data: EnemyData) -> void:
	var dealt := inventory.apply_damage(data.basic_damage, current_block)
	current_block = maxi(0, current_block - data.basic_damage)
	EventBus.block_changed.emit(current_block)
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_ENEMY_STRIKE") % [data.get_localized_name(), data.basic_damage, dealt]
	)
	EventBus.enemy_hp_changed.emit(index, int(enemies[index]["hp"]), data.max_hp)


func _enemy_special(index: int, data: EnemyData) -> void:
	var dealt := inventory.apply_damage(data.special_damage, current_block)
	current_block = maxi(0, current_block - data.special_damage)
	EventBus.block_changed.emit(current_block)
	var cell := inventory.grid.corrupt_random_unlocked_cell(data.corruption_duration)
	var cell_txt := (
		tr("KEY_LOG_CELL_NAME") % [cell.x, cell.y] if cell.x >= 0 else tr("KEY_LOG_NO_CELL")
	)
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_CELL_CORRUPTED") % [
			data.get_localized_name(), dealt, cell_txt, data.corruption_duration
		]
	)
	EventBus.enemy_hp_changed.emit(index, int(enemies[index]["hp"]), data.max_hp)


func _living_enemy_indices() -> Array[int]:
	var result: Array[int] = []
	for i in enemies.size():
		if int(enemies[i]["hp"]) > 0:
			result.append(i)
	return result


func _all_enemies_dead() -> bool:
	return _living_enemy_indices().is_empty()


func _emit_enemy_hp() -> void:
	for i in enemies.size():
		var e: Dictionary = enemies[i]
		var d: EnemyData = e["data"]
		EventBus.enemy_hp_changed.emit(i, int(e["hp"]), d.max_hp)
	if target_index >= 0:
		EventBus.enemy_selected.emit(target_index)


func _win() -> void:
	_set_state(CombatState.VICTORY)
	EventBus.combat_log_message.emit(tr("KEY_LOG_VICTORY"))
	EventBus.combat_ended.emit(true)


func _lose() -> void:
	_set_state(CombatState.DEFEAT)
	EventBus.combat_log_message.emit(tr("KEY_LOG_DEFEAT"))
	EventBus.combat_ended.emit(false)
