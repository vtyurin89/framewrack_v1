class_name EncounterManager
extends Node
## Owns the lifecycle of map / prologue encounters and routes to sub-systems.

signal encounter_started(data: EncounterData)
signal encounter_completed(rewards: Dictionary)
## Main / combat UI should start a fight with these EnemyData blueprints.
signal request_combat(enemy_datas: Array, encounter: EncounterData)
signal request_show_dialog(dialog: DialogEventData, encounter: EncounterData)
signal request_show_placeholder(encounter: EncounterData, message_key: String)
signal request_item_selection(item_pool: Array, title: String)
signal item_selection_resolved(item: ItemData)

## Explicit starting-god pool ids (directory scan also picks up any extra JSON).
const STARTING_GOD_IDS: Array[String] = ["sleeper_god", "mol_vagrit"]

const UNKNOWN_RESOLVE_POOL: Array[EncounterData.EncounterType] = [
	EncounterData.EncounterType.COMBAT_NORMAL,
	EncounterData.EncounterType.EVENT,
	EncounterData.EncounterType.CHEST,
	EncounterData.EncounterType.REST_SITE,
]

var inventory: InventoryController
var player_stats: PlayerStats
var combat: Node
var active_encounter: EncounterData
var _awaiting_combat_resolution: bool = false
var _pending_rewards: Dictionary = {}
var _awaiting_item_selection: bool = false
var _pending_select_outcome: DialogOutcomeData
var _pending_post_combat_finish: bool = false
## Mol-Vagrit buff: next N normal battles start enemies at 1 HP.
var crippled_foe_battles_remaining: int = 0


func setup(
	p_inventory: InventoryController, p_player_stats: PlayerStats, p_combat: Node
) -> void:
	inventory = p_inventory
	player_stats = p_player_stats
	combat = p_combat
	crippled_foe_battles_remaining = 0
	_awaiting_item_selection = false
	_pending_select_outcome = null
	_pending_post_combat_finish = false


func has_active_encounter() -> bool:
	return active_encounter != null


func is_prologue_active() -> bool:
	return (
		active_encounter != null
		and bool(active_encounter.payload.get("prologue", false))
	)


func start_prologue() -> void:
	## Pick a random starting god from res://data/encounters/gods/.
	var god_encounter := load_random_starting_god()
	if god_encounter == null:
		push_warning("EncounterManager: no starting god available")
		encounter_completed.emit({"prologue": true, "failed": true})
		return
	start_encounter(god_encounter)


func get_random_god_encounter() -> MainStoryEncounterData:
	## Prefer the curated starting pool; fall back to full gods directory.
	var pool: Array[String] = []
	for god_id in STARTING_GOD_IDS:
		if FileAccess.file_exists("%s%s.json" % [StartingGodRegistry.GODS_DIR, god_id]):
			pool.append(god_id)
	if pool.is_empty():
		return StartingGodRegistry.pick_random_god_encounter()
	var pick: String = pool[randi() % pool.size()]
	var encounter := StartingGodRegistry.load_god_encounter(pick)
	if encounter == null:
		return StartingGodRegistry.pick_random_god_encounter()
	return encounter


func load_random_starting_god() -> MainStoryEncounterData:
	## Public loader for the starting-god pool under data/encounters/gods/.
	return get_random_god_encounter()


func load_starting_god(god_id: String) -> MainStoryEncounterData:
	return StartingGodRegistry.load_god_encounter(god_id)


func start_encounter(data: EncounterData) -> void:
	if data == null:
		push_warning("EncounterManager: start_encounter called with null data")
		return
	var resolved := data.duplicate_resolved()
	if resolved.type == EncounterData.EncounterType.UNKNOWN:
		resolved.type = _resolve_unknown_type()
		_apply_unknown_defaults(resolved)
	active_encounter = resolved
	_pending_rewards = {"encounter_id": resolved.id, "type": resolved.type}
	_awaiting_combat_resolution = false
	_awaiting_item_selection = false
	_pending_select_outcome = null
	_pending_post_combat_finish = false
	encounter_started.emit(resolved)
	_launch_by_type(resolved)


func start_from_map_node(node: Dictionary) -> void:
	start_encounter(EncounterCatalog.from_map_node(node))


func start_from_map_node_data(node_data: MapNodeData) -> void:
	if node_data == null:
		return
	if node_data.encounter_data != null:
		start_encounter(node_data.encounter_data)
		return
	var fallback := EncounterData.new()
	fallback.id = node_data.id
	fallback.type = EncounterData.EncounterType.UNKNOWN
	fallback.payload = {"map_node_id": node_data.id}
	start_encounter(fallback)


func notify_combat_finished(victory: bool) -> void:
	## Called by Main when a combat that this manager requested has ended.
	if not _awaiting_combat_resolution:
		return
	_awaiting_combat_resolution = false
	_pending_rewards["combat_victory"] = victory
	if not victory:
		_pending_rewards["failed"] = true
		_finish_encounter(_pending_rewards)
		return
	## Victory: route loot choice through SelectItemUI stub before completing.
	_offer_post_combat_item_choice()


func apply_dialog_outcome(outcome: DialogOutcomeData) -> void:
	if active_encounter == null:
		return
	if outcome == null:
		_finish_encounter(_pending_rewards)
		return
	_apply_outcome_buff(outcome)
	match outcome.kind:
		DialogOutcomeData.OutcomeKind.END, DialogOutcomeData.OutcomeKind.SKIP:
			if not outcome.message_key.is_empty():
				_pending_rewards["message_key"] = outcome.message_key
			_finish_encounter(_pending_rewards)
		DialogOutcomeData.OutcomeKind.CONTINUE:
			## Dialog UI handles node jumps; nothing to finish here.
			if not outcome.message_key.is_empty():
				_pending_rewards["message_key"] = outcome.message_key
		DialogOutcomeData.OutcomeKind.HEAL:
			_apply_heal(outcome.heal_amount)
			if not outcome.message_key.is_empty():
				_pending_rewards["message_key"] = outcome.message_key
			_pending_rewards["healed"] = outcome.heal_amount
			if outcome.next_node_id.is_empty():
				_finish_encounter(_pending_rewards)
		DialogOutcomeData.OutcomeKind.DAMAGE:
			_apply_damage(outcome.damage_amount)
			if not outcome.message_key.is_empty():
				_pending_rewards["message_key"] = outcome.message_key
			_pending_rewards["damage_taken"] = outcome.damage_amount
			if outcome.next_node_id.is_empty():
				_finish_encounter(_pending_rewards)
		DialogOutcomeData.OutcomeKind.GRANT_ITEM:
			_grant_item(outcome.item_id, outcome.item_amount)
			if not outcome.message_key.is_empty():
				_pending_rewards["message_key"] = outcome.message_key
			_pending_rewards["item_id"] = outcome.item_id
			_pending_rewards["item_amount"] = outcome.item_amount
			if outcome.next_node_id.is_empty():
				_finish_encounter(_pending_rewards)
		DialogOutcomeData.OutcomeKind.GRANT_STAT:
			_grant_stat(outcome.stat_name, outcome.stat_amount)
			if not outcome.message_key.is_empty():
				_pending_rewards["message_key"] = outcome.message_key
			_pending_rewards["stat_name"] = outcome.stat_name
			_pending_rewards["stat_amount"] = outcome.stat_amount
			if outcome.next_node_id.is_empty():
				_finish_encounter(_pending_rewards)
		DialogOutcomeData.OutcomeKind.SELECT_ITEM:
			if not outcome.message_key.is_empty():
				_pending_rewards["message_key"] = outcome.message_key
			_begin_item_selection(outcome, false)
		DialogOutcomeData.OutcomeKind.COMBAT:
			if not outcome.message_key.is_empty():
				_pending_rewards["message_key"] = outcome.message_key
			_start_combat_from_ids(outcome.enemy_ids, outcome.faction, null)


func resolve_item_selection(selected_item: ItemData) -> void:
	## Called by Main / SelectItemUI after the player confirms a choice.
	if not _awaiting_item_selection:
		return
	_awaiting_item_selection = false
	if selected_item != null:
		_grant_item_data(selected_item)
		_pending_rewards["item_id"] = selected_item.id
		_pending_rewards["item_amount"] = 1
	var pending := _pending_select_outcome
	_pending_select_outcome = null
	item_selection_resolved.emit(selected_item)
	if _pending_post_combat_finish:
		_pending_post_combat_finish = false
		_finish_encounter(_pending_rewards)
		return
	if pending != null and pending.next_node_id.is_empty():
		_finish_encounter(_pending_rewards)


func open_item_selection(item_pool: Array, title: String = "Выберите награду") -> void:
	## Public helper for external callers (dialog / rewards).
	request_item_selection.emit(item_pool, title)


func resolve_stat_check(stat_name: String, dc: int) -> bool:
	if player_stats == null or dc <= 0:
		return true
	var stat_value := _get_player_stat(stat_name)
	## Simple roll: stat + d6 vs DC.
	var roll := stat_value + randi_range(1, 6)
	return roll >= dc


func _launch_by_type(data: EncounterData) -> void:
	match data.type:
		EncounterData.EncounterType.COMBAT_NORMAL, \
		EncounterData.EncounterType.COMBAT_ELITE, \
		EncounterData.EncounterType.COMBAT_BOSS:
			_start_combat_from_encounter(data)
		EncounterData.EncounterType.EVENT:
			var dialog := data.get_dialog_event()
			if dialog != null:
				request_show_dialog.emit(dialog, data)
			else:
				## Legacy map EVENT stub: loot + small heal.
				_grant_item(str(data.payload.get("item_id", "REBEL_CLEAVER")))
				_apply_heal(int(data.payload.get("heal_amount", 10)))
				_pending_rewards["message_key"] = "KEY_STATUS_EVENT"
				_finish_encounter(_pending_rewards)
		EncounterData.EncounterType.MAIN_STORY:
			var story_dialog := data.get_dialog_event()
			if story_dialog != null:
				request_show_dialog.emit(story_dialog, data)
			elif bool(data.payload.get("act_finale", false)):
				## Post-boss chapter beat — no starting-god re-roll.
				_pending_rewards["message_key"] = "KEY_TYPE_MAIN_STORY"
				request_show_placeholder.emit(data, "KEY_TYPE_MAIN_STORY")
				_finish_encounter(_pending_rewards)
			else:
				var picked := get_random_god_encounter()
				if picked != null:
					start_encounter(picked)
				else:
					_finish_encounter(_pending_rewards)
		EncounterData.EncounterType.REST_SITE:
			if inventory:
				inventory.grid.clear_all_corruption()
				inventory.heal_full()
			_pending_rewards["message_key"] = "KEY_STATUS_REPAIR"
			_finish_encounter(_pending_rewards)
		EncounterData.EncounterType.CHEST:
			_grant_item(str(data.payload.get("item_id", "BIO_GEL")))
			_pending_rewards["message_key"] = "KEY_STATUS_CHEST"
			request_show_placeholder.emit(data, "KEY_STATUS_CHEST")
			_finish_encounter(_pending_rewards)
		EncounterData.EncounterType.SHOP:
			request_show_placeholder.emit(data, "KEY_STATUS_SHOP")
			_finish_encounter(_pending_rewards)
		EncounterData.EncounterType.STAIRS:
			_pending_rewards["message_key"] = "KEY_STATUS_STAIRS"
			request_show_placeholder.emit(data, "KEY_STATUS_STAIRS")
			_finish_encounter(_pending_rewards)
		_:
			_finish_encounter(_pending_rewards)


func get_encounter_for_node(node_layer: int, is_elite: bool = false) -> EnemyGroup:
	## Public API: hand-crafted group pick for map combat nodes.
	return EnemyManager.get_encounter_for_node(node_layer, is_elite)


func _start_combat_from_encounter(data: EncounterData) -> void:
	var ids := data.get_enemy_ids()
	var faction := str(data.payload.get("faction", ""))
	var layer := int(data.payload.get("layer", data.payload.get("node_layer", 1)))
	var is_elite := data.type == EncounterData.EncounterType.COMBAT_ELITE
	var group: EnemyGroup = null
	## Prefer an authored group when the encounter has no fixed enemy_ids.
	if ids.is_empty() and data.type != EncounterData.EncounterType.COMBAT_BOSS:
		group = get_encounter_for_node(layer, is_elite)
		if group != null:
			data.payload["enemy_group_id"] = group.group_id
			data.payload["max_attackers_per_turn"] = group.max_attackers_per_turn
	_start_combat_from_ids(ids, faction, group)


func _start_combat_from_ids(
	enemy_ids: Array, faction: String = "", group: EnemyGroup = null
) -> void:
	var datas: Array[EnemyData] = []
	for eid in enemy_ids:
		var id_str := str(eid).strip_edges()
		if id_str.is_empty():
			continue
		if EnemyDatabase != null and EnemyDatabase.has_enemy(id_str):
			var bp := EnemyDatabase.create_blueprint(id_str)
			if bp != null:
				datas.append(bp)

	if datas.is_empty() and group != null:
		datas = group.resolve_enemy_datas()

	if datas.is_empty() and active_encounter != null:
		if active_encounter.type == EncounterData.EncounterType.COMBAT_BOSS:
			var act := int(active_encounter.payload.get("act", 1))
			var resolved_faction := faction.strip_edges().to_lower()
			if resolved_faction.is_empty():
				resolved_faction = _default_faction_for_act(act)
			var boss: EnemyData = null
			if not resolved_faction.is_empty():
				boss = EnemyDatabase.get_random_boss_for_faction(resolved_faction)
			if boss == null:
				boss = EnemyDatabase.get_random_boss()
			if boss != null:
				datas.append(boss)
		else:
			## Last-resort group pick when payload lacked layer / ids.
			var layer := int(active_encounter.payload.get("layer", 1))
			var is_elite := active_encounter.type == EncounterData.EncounterType.COMBAT_ELITE
			var fallback := get_encounter_for_node(layer, is_elite)
			if fallback != null:
				group = fallback
				datas = fallback.resolve_enemy_datas()
				active_encounter.payload["enemy_group_id"] = fallback.group_id
				active_encounter.payload["max_attackers_per_turn"] = fallback.max_attackers_per_turn

	if datas.is_empty():
		push_warning("EncounterManager: no enemies resolved for combat")
		_finish_encounter(_pending_rewards)
		return

	var max_attackers := 2
	if group != null:
		max_attackers = maxi(1, group.max_attackers_per_turn)
	elif active_encounter != null:
		max_attackers = maxi(1, int(active_encounter.payload.get("max_attackers_per_turn", 2)))

	datas = _apply_cripple_buff_to_enemies(datas)
	_awaiting_combat_resolution = true
	if combat != null and combat.has_method("set_group_attack_cap"):
		combat.call("set_group_attack_cap", max_attackers)
	request_combat.emit(datas, active_encounter)


func _default_faction_for_act(act: int) -> String:
	match act:
		2:
			return "synthet"
		3:
			return "chimera"
		_:
			return "human"


func _apply_cripple_buff_to_enemies(datas: Array[EnemyData]) -> Array[EnemyData]:
	## Mol-Vagrit gift: next N normal battles start with enemies at 1 HP.
	if crippled_foe_battles_remaining <= 0:
		return datas
	if active_encounter == null:
		return datas
	if active_encounter.type != EncounterData.EncounterType.COMBAT_NORMAL:
		return datas
	var out: Array[EnemyData] = []
	for data in datas:
		if data == null:
			continue
		var copy := data.duplicate(true) as EnemyData
		if copy != null:
			copy.base_hp = 1
			copy.max_hp = 1
			out.append(copy)
		else:
			out.append(data)
	crippled_foe_battles_remaining = maxi(0, crippled_foe_battles_remaining - 1)
	_pending_rewards["cripple_buff_applied"] = true
	return out


func _begin_item_selection(outcome: DialogOutcomeData, post_combat: bool) -> void:
	_awaiting_item_selection = true
	_pending_select_outcome = outcome
	_pending_post_combat_finish = post_combat
	var pool: Array = _build_item_pool_from_outcome(outcome)
	var title := "Выберите награду"
	if post_combat:
		title = "Награда за бой"
	request_item_selection.emit(pool, title)


func _offer_post_combat_item_choice() -> void:
	var outcome := DialogOutcomeData.make_select_item("combat_loot")
	_begin_item_selection(outcome, true)


func _build_item_pool_from_outcome(outcome: DialogOutcomeData) -> Array:
	var pool: Array = []
	if outcome == null:
		return pool
	for item_id in outcome.item_pool_ids:
		if ItemDatabase != null and ItemDatabase.has_item(item_id):
			pool.append(ItemDatabase.get_item(item_id))
	if pool.is_empty() and ItemDatabase != null:
		pool = ItemDatabase.build_choice_pool(outcome.item_pool_id)
	return pool


func _apply_outcome_buff(outcome: DialogOutcomeData) -> void:
	if outcome == null or outcome.buff_id.is_empty():
		return
	match outcome.buff_id.strip_edges().to_lower():
		"enemies_start_1hp", "cripple_foes":
			crippled_foe_battles_remaining = maxi(outcome.buff_amount, 1)
			_pending_rewards["buff_id"] = outcome.buff_id
			_pending_rewards["buff_amount"] = crippled_foe_battles_remaining
		_:
			pass


func _grant_item_data(item: ItemData) -> void:
	if inventory == null or item == null:
		return
	var instance := item
	## Prefer a fresh instance from the catalog when we only have a prototype.
	if ItemDatabase != null and ItemDatabase.has_item(item.id):
		instance = ItemDatabase.create_instance(item.id)
	if instance == null:
		return
	if instance.is_stackable:
		inventory.add_stackable_item(instance.id, maxi(instance.current_stack, 1))
		return
	inventory.try_place_anywhere(instance)


func _finish_encounter(rewards: Dictionary) -> void:
	var finished := active_encounter
	active_encounter = null
	_awaiting_combat_resolution = false
	var out := rewards.duplicate(true)
	if finished != null:
		out["encounter_id"] = finished.id
		out["prologue"] = bool(finished.payload.get("prologue", false))
		out["map_node_id"] = str(finished.payload.get("map_node_id", ""))
	encounter_completed.emit(out)


func _resolve_unknown_type() -> EncounterData.EncounterType:
	return UNKNOWN_RESOLVE_POOL[randi() % UNKNOWN_RESOLVE_POOL.size()]


func _apply_unknown_defaults(data: EncounterData) -> void:
	match data.type:
		EncounterData.EncounterType.COMBAT_NORMAL:
			if data.get_enemy_ids().is_empty():
				data.payload["faction"] = "human"
				data.payload["layer"] = int(data.payload.get("layer", 1))
		EncounterData.EncounterType.EVENT:
			if data.get_dialog_event() == null:
				data.payload["item_id"] = "REBEL_CLEAVER"
				data.payload["heal_amount"] = 10
		EncounterData.EncounterType.CHEST:
			data.payload["item_id"] = "BIO_GEL"
		_:
			pass


func _apply_heal(amount: int) -> void:
	if inventory == null or amount <= 0:
		return
	inventory.current_hp = mini(inventory.max_hp, inventory.current_hp + amount)
	EventBus.player_hp_changed.emit(inventory.current_hp, inventory.max_hp)


func _apply_damage(amount: int) -> void:
	if inventory == null or amount <= 0:
		return
	inventory.current_hp = maxi(0, inventory.current_hp - amount)
	EventBus.player_hp_changed.emit(inventory.current_hp, inventory.max_hp)
	if inventory.current_hp <= 0:
		EventBus.player_died.emit()


func _grant_item(item_id: String, amount: int = 1) -> void:
	var id_str := item_id.strip_edges()
	if inventory == null or id_str.is_empty() or ItemDatabase == null:
		return
	var qty := maxi(amount, 1)
	## Stackable currency (Neuro-Chips) merges into a single cell when possible.
	var prototype: ItemData = ItemDatabase.get_item(id_str)
	if prototype != null and prototype.is_stackable:
		inventory.add_stackable_item(id_str, qty)
		return
	for _i in qty:
		var item: ItemData = ItemDatabase.create_instance(id_str)
		if item != null:
			inventory.try_place_anywhere(item)


func _grant_stat(stat_name: String, amount: int) -> void:
	if player_stats == null or amount == 0:
		return
	player_stats.add_stat_bonus(stat_name, amount)
	## Endurance changes Max HP — keep inventory pool in sync.
	if inventory != null:
		inventory.apply_actor_stats(player_stats)


func _get_player_stat(stat_name: String) -> int:
	if player_stats == null:
		return 1
	match stat_name.strip_edges().to_upper():
		"STR", "STRENGTH":
			return player_stats.strength
		"AGI", "AGILITY":
			return player_stats.agility
		"END", "ENDURANCE":
			return player_stats.endurance
		"INT", "INTELLIGENCE":
			return player_stats.intelligence
		"LCK", "LUCK":
			return player_stats.luck
		"HUM", "HUMANITY":
			return player_stats.humanity
		_:
			return 1
