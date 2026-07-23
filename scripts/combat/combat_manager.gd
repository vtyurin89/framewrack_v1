extends Node
## Turn-based combat state machine.
## Player spends AP activating equipped modules; enemies attack or corrupt cells.

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

## Runtime enemy instances: { data: EnemyData, hp: int }
var enemies: Array[Dictionary] = []

var current_ap: int = 0
var max_ap: int = 3
var current_block: int = 0

## Optional: which enemy is targeted (index into enemies).
var target_index: int = 0


func setup(p_inventory: InventoryController) -> void:
	inventory = p_inventory


func start_combat(enemy_datas: Array[EnemyData]) -> void:
	enemies.clear()
	for data: EnemyData in enemy_datas:
		enemies.append({"data": data, "hp": data.max_hp})
	current_block = 0
	target_index = 0
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
	EventBus.ap_changed.emit(current_ap, max_ap)
	_set_state(CombatState.PLAYER_TURN)
	EventBus.combat_log_message.emit("— Your turn — (%d AP)" % current_ap)
	_emit_enemy_hp()


func end_player_turn() -> void:
	if state != CombatState.PLAYER_TURN:
		return
	_begin_enemy_turn()


func set_target(index: int) -> void:
	if index >= 0 and index < enemies.size():
		target_index = index


func activate_item(placed: PlacedItem) -> bool:
	## Spend AP to fire a weapon or raise a shield.
	if state != CombatState.PLAYER_TURN:
		return false
	if placed == null or placed.data == null:
		return false
	if not inventory.grid.is_item_functional(placed):
		EventBus.combat_log_message.emit("%s is offline (corrupted cells)." % placed.data.display_name)
		return false
	var cost: int = placed.data.ap_cost
	if cost <= 0:
		EventBus.combat_log_message.emit("%s is passive." % placed.data.display_name)
		return false
	if current_ap < cost:
		EventBus.combat_log_message.emit("Not enough AP.")
		return false

	current_ap -= cost
	EventBus.ap_changed.emit(current_ap, max_ap)

	if placed.data.is_weapon():
		return _resolve_weapon(placed)
	if placed.data.is_shield():
		return _resolve_shield(placed)

	EventBus.combat_log_message.emit("Activated %s." % placed.data.display_name)
	return true


func _resolve_weapon(placed: PlacedItem) -> bool:
	var living := _living_enemy_indices()
	if living.is_empty():
		return false
	if target_index not in living:
		target_index = living[0]

	var bonus: int = inventory.grid.get_adjacency_damage_bonus_for(placed)
	var dmg: int = placed.data.damage + bonus
	var entry: Dictionary = enemies[target_index]
	entry["hp"] = maxi(0, int(entry["hp"]) - dmg)
	enemies[target_index] = entry

	var ename: String = (entry["data"] as EnemyData).display_name
	var bonus_txt := " (+%d reactor)" % bonus if bonus > 0 else ""
	EventBus.combat_log_message.emit(
		"%s deals %d damage%s to %s." % [placed.data.display_name, dmg, bonus_txt, ename]
	)
	EventBus.enemy_hp_changed.emit(target_index, int(entry["hp"]), (entry["data"] as EnemyData).max_hp)

	if _all_enemies_dead():
		_win()
	return true


func _resolve_shield(placed: PlacedItem) -> bool:
	current_block += placed.data.block_amount
	EventBus.block_changed.emit(current_block)
	EventBus.combat_log_message.emit(
		"%s raises %d Block (total %d)." % [placed.data.display_name, placed.data.block_amount, current_block]
	)
	return true


func _begin_enemy_turn() -> void:
	_set_state(CombatState.ENEMY_TURN)
	EventBus.combat_log_message.emit("— Enemy turn —")
	# Process sequentially with a short delay feel via await if in tree.
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

	# Corruption ticks down once per full enemy phase.
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
		"%s strikes for %d (you take %d)." % [data.display_name, data.basic_damage, dealt]
	)
	EventBus.enemy_hp_changed.emit(index, int(enemies[index]["hp"]), data.max_hp)


func _enemy_special(index: int, data: EnemyData) -> void:
	var dealt := inventory.apply_damage(data.special_damage, current_block)
	current_block = maxi(0, current_block - data.special_damage)
	EventBus.block_changed.emit(current_block)
	var cell := inventory.grid.corrupt_random_unlocked_cell(data.corruption_duration)
	var cell_txt := "cell (%d,%d)" % [cell.x, cell.y] if cell.x >= 0 else "no cell"
	EventBus.combat_log_message.emit(
		"%s unleashes corruption! %d damage; %s locked %d turns." % [
			data.display_name, dealt, cell_txt, data.corruption_duration
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


func _win() -> void:
	_set_state(CombatState.VICTORY)
	EventBus.combat_log_message.emit("Hostiles neutralized.")
	EventBus.combat_ended.emit(true)


func _lose() -> void:
	_set_state(CombatState.DEFEAT)
	EventBus.combat_log_message.emit("Frame integrity critical. Shutdown.")
	EventBus.combat_ended.emit(false)
