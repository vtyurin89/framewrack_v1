class_name EncounterManager
extends Node
## Owns the lifecycle of map / prologue encounters and routes to sub-systems.

signal encounter_started(data: EncounterData)
signal encounter_completed(rewards: Dictionary)
## Main / combat UI should start a fight with these EnemyData blueprints.
signal request_combat(enemy_datas: Array, encounter: EncounterData)
signal request_show_dialog(dialog: DialogEventData, encounter: EncounterData)
signal request_show_placeholder(encounter: EncounterData, message_key: String)
signal request_show_rest_site(encounter: EncounterData)
signal request_show_shop(encounter: EncounterData, price_multiplier: float)
signal request_show_chest_reward(encounter: EncounterData)
signal request_item_selection(item_pool: Array, title: String)
signal request_dialog_loot(items: Array, pick_count: int, title_key: String)
signal item_selection_resolved(item: ItemData)
signal request_post_combat_rewards(encounter: EncounterData)

## Explicit starting-god pool ids (directory scan also picks up any extra JSON).
const STARTING_GOD_IDS: Array[String] = ["sleeper_god", "mol_vagrit", "pale_maiden"]

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


func get_random_god_encounter() -> IntroEncounterData:
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


func load_random_starting_god() -> IntroEncounterData:
	## Public loader for the starting-god pool under data/encounters/gods/.
	return get_random_god_encounter()


func load_starting_god(god_id: String) -> IntroEncounterData:
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
	## Act-boss victory: full heal + purge harmful modules before loot.
	_apply_act_boss_victory_recovery()
	## Victory: open floating loot reward screen before completing the encounter.
	_pending_post_combat_finish = true
	request_post_combat_rewards.emit(active_encounter)


func _apply_act_boss_victory_recovery() -> void:
	## Mandatory post-fight effect for the act's final boss node.
	if active_encounter == null:
		return
	if active_encounter.type != EncounterData.EncounterType.COMBAT_BOSS:
		return
	if inventory != null:
		inventory.heal_full()
		EventBus.combat_log_message.emit(tr("KEY_LOG_BOSS_VICTORY_HEAL"))
		var removed := inventory.remove_all_harmful_items()
		if removed > 0:
			EventBus.combat_log_message.emit(tr("KEY_LOG_BOSS_VICTORY_PURGE") % removed)
			EventBus.inventory_changed.emit()


func complete_post_combat_rewards() -> void:
	## Called by Main after RewardScreen Continue.
	if not _pending_post_combat_finish:
		return
	_pending_post_combat_finish = false
	_finish_encounter(_pending_rewards)


## Drop the active encounter without encounter_completed (run ended mid-event).
func abort_active_encounter() -> void:
	active_encounter = null
	_awaiting_combat_resolution = false
	_awaiting_item_selection = false
	_pending_select_outcome = null
	_pending_post_combat_finish = false
	_pending_rewards.clear()


func _run_ended_mid_encounter() -> bool:
	return GameManager != null and GameManager.is_game_over()


func apply_dialog_outcome(outcome: DialogOutcomeData) -> bool:
	## Returns false when HP/humanity death aborted the encounter mid-flow.
	if active_encounter == null:
		return true
	if outcome == null:
		_finish_encounter(_pending_rewards)
		return not _run_ended_mid_encounter()
	## Compound story rewards (multi-stat / mixed) are fully applied here once.
	var compound_applied := (
		outcome.payload_effects is Array and not outcome.payload_effects.is_empty()
	)
	_apply_outcome_side_effects(outcome)
	if _run_ended_mid_encounter():
		abort_active_encounter()
		return false
	_apply_outcome_buff(outcome)
	if _run_ended_mid_encounter():
		abort_active_encounter()
		return false
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
			if _run_ended_mid_encounter():
				abort_active_encounter()
				return false
			if not outcome.message_key.is_empty():
				_pending_rewards["message_key"] = outcome.message_key
			_pending_rewards["healed"] = outcome.heal_amount
			if outcome.next_node_id.is_empty():
				_finish_encounter(_pending_rewards)
		DialogOutcomeData.OutcomeKind.DAMAGE:
			_apply_damage(outcome.damage_amount)
			if _run_ended_mid_encounter():
				abort_active_encounter()
				return false
			if not outcome.message_key.is_empty():
				_pending_rewards["message_key"] = outcome.message_key
			_pending_rewards["damage_taken"] = outcome.damage_amount
			if outcome.next_node_id.is_empty():
				_finish_encounter(_pending_rewards)
		DialogOutcomeData.OutcomeKind.GRANT_ITEM:
			if not compound_applied:
				_grant_item(outcome.item_id, outcome.item_amount)
			if _run_ended_mid_encounter():
				abort_active_encounter()
				return false
			if not outcome.message_key.is_empty():
				_pending_rewards["message_key"] = outcome.message_key
			_pending_rewards["item_id"] = outcome.item_id
			_pending_rewards["item_amount"] = outcome.item_amount
			if outcome.next_node_id.is_empty():
				_finish_encounter(_pending_rewards)
		DialogOutcomeData.OutcomeKind.GRANT_STAT:
			if not compound_applied:
				_grant_stat(outcome.stat_name, outcome.stat_amount)
				if _run_ended_mid_encounter():
					abort_active_encounter()
					return false
			if not outcome.message_key.is_empty():
				_pending_rewards["message_key"] = outcome.message_key
			_pending_rewards["stat_name"] = outcome.stat_name
			_pending_rewards["stat_amount"] = outcome.stat_amount
			if outcome.next_node_id.is_empty():
				_finish_encounter(_pending_rewards)
		DialogOutcomeData.OutcomeKind.SELECT_ITEM:
			if not outcome.message_key.is_empty():
				_pending_rewards["message_key"] = outcome.message_key
			if _try_open_dialog_loot(outcome):
				return not _run_ended_mid_encounter()
			if _try_resolve_direct_item_pool(outcome, false):
				return not _run_ended_mid_encounter()
			_begin_item_selection(outcome, false)
		DialogOutcomeData.OutcomeKind.COMBAT:
			if not outcome.message_key.is_empty():
				_pending_rewards["message_key"] = outcome.message_key
			if outcome.elite_rewards and active_encounter != null:
				active_encounter.payload["force_elite_rewards"] = true
			_start_combat_from_ids(outcome.enemy_ids, outcome.faction, null)
		DialogOutcomeData.OutcomeKind.SHOP:
			if not outcome.message_key.is_empty():
				_pending_rewards["message_key"] = outcome.message_key
			var mult := outcome.price_multiplier
			if mult <= 0.0:
				mult = 1.0
			_pending_rewards["shop_price_multiplier"] = mult
			request_show_shop.emit(active_encounter, mult)
	return not _run_ended_mid_encounter()


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


func complete_dialog_loot() -> void:
	## Called by Main after dialog RewardScreen Continue (items already placed).
	if not _awaiting_item_selection:
		return
	_awaiting_item_selection = false
	var pending := _pending_select_outcome
	_pending_select_outcome = null
	item_selection_resolved.emit(null)
	if pending != null and pending.next_node_id.is_empty():
		_finish_encounter(_pending_rewards)


func open_item_selection(item_pool: Array, title: String = "Выберите награду") -> void:
	## Public helper for external callers (dialog / rewards).
	request_item_selection.emit(item_pool, title)


func resolve_stat_check(
	stat_name: String,
	required_successes: int = 1,
	consumed_ap: int = 0,
	pool_bonus: int = 0
) -> StatCheckManager.CheckResult:
	var stat_value := maxi(1, _get_player_stat(stat_name) + pool_bonus)
	return StatCheckManager.perform_check(stat_value, required_successes, consumed_ap)


func _launch_by_type(data: EncounterData) -> void:
	match data.type:
		EncounterData.EncounterType.COMBAT_NORMAL, \
		EncounterData.EncounterType.COMBAT_ELITE, \
		EncounterData.EncounterType.COMBAT_BOSS:
			_start_combat_from_encounter(data)
		EncounterData.EncounterType.EVENT:
			var story_event_id := str(data.payload.get("story_event_id", data.id)).strip_edges()
			if StoryEventManager != null:
				StoryEventManager.notify_event_started(story_event_id)
			var dialog := data.get_dialog_event()
			if dialog != null:
				request_show_dialog.emit(dialog, data)
			else:
				## Legacy map EVENT stub: loot + small heal.
				_grant_item(str(data.payload.get("item_id", "REBEL_CLEAVER")))
				_apply_heal(int(data.payload.get("heal_amount", 10)))
				_pending_rewards["message_key"] = "KEY_STATUS_EVENT"
				_finish_encounter(_pending_rewards)
		EncounterData.EncounterType.INTRO:
			## Starting-god / prologue dialogs — same UI path as MAIN_STORY.
			var intro_dialog := data.get_dialog_event()
			if intro_dialog != null:
				request_show_dialog.emit(intro_dialog, data)
			else:
				var picked := get_random_god_encounter()
				if picked != null:
					start_encounter(picked)
				else:
					_finish_encounter(_pending_rewards)
		EncounterData.EncounterType.MAIN_STORY:
			var story_dialog := data.get_dialog_event()
			if story_dialog != null:
				request_show_dialog.emit(story_dialog, data)
			elif bool(data.payload.get("act_finale", false)):
				## Post-boss chapter beat — placeholder until authored.
				_pending_rewards["message_key"] = "KEY_TYPE_MAIN_STORY"
				request_show_placeholder.emit(data, "KEY_TYPE_MAIN_STORY")
				_finish_encounter(_pending_rewards)
			else:
				## Opening MAIN_STORY without dialog: try act stub, else placeholder.
				var act := int(data.payload.get("act", 1))
				var stub := MainStoryRegistry.load_opening_for_act(act)
				if stub != null and stub.get_dialog_event() != null:
					stub.payload["map_node_id"] = str(data.payload.get("map_node_id", ""))
					start_encounter(stub)
				else:
					_pending_rewards["message_key"] = "KEY_TYPE_MAIN_STORY"
					request_show_placeholder.emit(data, "KEY_TYPE_MAIN_STORY")
					_finish_encounter(_pending_rewards)
		EncounterData.EncounterType.REST_SITE:
			request_show_rest_site.emit(data)
		EncounterData.EncounterType.CHEST:
			request_show_chest_reward.emit(data)
		EncounterData.EncounterType.SHOP:
			var act := int(data.payload.get("act", 1))
			var dialog := MerchantEncounter.build_dialog(maxi(1, act), null, inventory)
			data.encounter_payload = dialog
			request_show_dialog.emit(dialog, data)
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
			## Act 1 finale: Elder Vaeron flanked by both Stasis Pods.
			if act <= 1:
				var vaeron_ids: Array[String] = [
					"stasis_pod_left",
					"elder_vaeron",
					"stasis_pod_right",
				]
				for vid: String in vaeron_ids:
					if EnemyDatabase != null and EnemyDatabase.has_enemy(vid):
						var bp := EnemyDatabase.create_blueprint(vid)
						if bp != null:
							datas.append(bp)
			if datas.is_empty():
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
	## Vaeron trio needs three attack slots so pods can support every turn.
	if datas.size() >= 3:
		var has_vaeron := false
		for d: EnemyData in datas:
			if d != null and d.id == "elder_vaeron":
				has_vaeron = true
				break
		if has_vaeron:
			max_attackers = maxi(max_attackers, 3)

	datas = _apply_cripple_buff_to_enemies(datas)
	if StoryEventManager != null:
		var act_index := 1
		if active_encounter != null:
			act_index = maxi(1, int(active_encounter.payload.get("act", 1)))
		datas = StoryEventManager.maybe_inject_faceless_lady(datas, act_index)
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
			if not copy.trait_ids.has("war_god_corruption"):
				copy.trait_ids.append("war_god_corruption")
			out.append(copy)
		else:
			out.append(data)
	crippled_foe_battles_remaining = maxi(0, crippled_foe_battles_remaining - 1)
	_pending_rewards["cripple_buff_applied"] = true
	return out


func _try_open_dialog_loot(outcome: DialogOutcomeData) -> bool:
	if outcome == null or RewardManager == null:
		return false
	var pool_key := outcome.item_pool_id.strip_edges().to_lower()
	var pick_count := maxi(1, outcome.loot_pick_count)
	var loot: Array[ItemData] = []
	match pool_key:
		"rare_pick_3", "rare_item_pick_3":
			loot = RewardManager.generate_rare_offer(3)
			pick_count = 1
		"rare_weapon", "collector_weapon":
			var weapon := RewardManager.generate_rare_weapon()
			if weapon != null:
				loot.append(weapon)
			pick_count = 1
		"rare_module", "collector_module":
			var module := RewardManager.generate_rare_module()
			if module != null:
				loot.append(module)
			pick_count = 1
		"rare_weapon_and_module", "collector_both":
			var w := RewardManager.generate_rare_weapon()
			var m := RewardManager.generate_rare_module()
			if w != null:
				loot.append(w)
			if m != null:
				loot.append(m)
			pick_count = maxi(2, loot.size())
		_:
			return false
	if loot.is_empty():
		return false
	_awaiting_item_selection = true
	_pending_select_outcome = outcome
	_pending_post_combat_finish = false
	_pending_rewards["dialog_loot"] = true
	_pending_rewards["loot_pick_count"] = pick_count
	request_dialog_loot.emit(loot, pick_count, "KEY_REWARD_SELECT_ONE")
	return true


func _apply_outcome_side_effects(outcome: DialogOutcomeData) -> void:
	if outcome == null:
		return
	if outcome.spend_chips > 0 and GameManager != null:
		GameManager.spend_chips(outcome.spend_chips)
		_pending_rewards["spent_chips"] = outcome.spend_chips
	if outcome.exp_amount > 0 and player_stats != null:
		player_stats.add_exp(outcome.exp_amount)
		_pending_rewards["exp"] = outcome.exp_amount


func _begin_item_selection(outcome: DialogOutcomeData, post_combat: bool) -> void:
	_awaiting_item_selection = true
	_pending_select_outcome = outcome
	_pending_post_combat_finish = post_combat
	var pool: Array = _build_item_pool_from_outcome(outcome)
	var title := "Выберите награду"
	if post_combat:
		title = "Награда за бой"
	request_item_selection.emit(pool, title)


func _try_resolve_direct_item_pool(outcome: DialogOutcomeData, post_combat: bool) -> bool:
	if outcome == null:
		return false
	var pool_key := outcome.item_pool_id.strip_edges().to_lower()
	if pool_key not in ["grenade", "grenades", "uncommon_weapon"]:
		return false
	var pool: Array = _build_item_pool_from_outcome(outcome)
	if pool.is_empty():
		return false
	var picked := pool[randi() % pool.size()] as ItemData
	if picked == null:
		return false
	_grant_item_data(picked)
	_pending_rewards["item_id"] = picked.id
	_pending_rewards["item_amount"] = 1
	_awaiting_item_selection = false
	_pending_select_outcome = null
	_pending_post_combat_finish = post_combat
	item_selection_resolved.emit(picked)
	if _pending_post_combat_finish:
		_pending_post_combat_finish = false
		_finish_encounter(_pending_rewards)
	elif outcome.next_node_id.is_empty():
		_finish_encounter(_pending_rewards)
	return true


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
	if outcome == null:
		return
	## Compound story effects (Pale Maiden Option 1 multi-stat, etc.).
	if outcome.payload_effects is Array and not outcome.payload_effects.is_empty():
		_apply_payload_effects(outcome.payload_effects)
	if outcome.buff_id.is_empty():
		return
	match outcome.buff_id.strip_edges().to_lower():
		"enemies_start_1hp", "cripple_foes":
			crippled_foe_battles_remaining = maxi(outcome.buff_amount, 1)
			_pending_rewards["buff_id"] = outcome.buff_id
			_pending_rewards["buff_amount"] = crippled_foe_battles_remaining
		"pale_maiden_pact":
			if StoryEventManager != null:
				StoryEventManager.mark_pale_maiden_pact()
			_pending_rewards["buff_id"] = outcome.buff_id
		_:
			pass


func _apply_payload_effects(effects: Array) -> void:
	for entry in effects:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var effect: Dictionary = entry
		var effect_type := str(effect.get("type", "")).strip_edges().to_lower()
		var amount := int(effect.get("amount", 0))
		match effect_type:
			"strength", "humanity", "endurance", "agility", "intelligence", "luck":
				_grant_stat(effect_type, amount if amount != 0 else 1)
			"item", "grant_item":
				_grant_item(str(effect.get("item_id", "")), maxi(1, amount if amount > 0 else 1))
			"neuro_chips", "neuro_chip", "neurochip":
				_grant_item("NEURO_CHIP", amount if amount > 0 else 10)
			"exp", "experience", "xp":
				if player_stats != null and amount > 0:
					player_stats.add_exp(amount)
					_pending_rewards["exp"] = int(_pending_rewards.get("exp", 0)) + amount
			"spend_chips", "cost_chips":
				var cost := amount if amount > 0 else maxi(0, int(effect.get("spend_chips", 0)))
				if cost > 0 and GameManager != null:
					GameManager.spend_chips(cost)
					_pending_rewards["spent_chips"] = int(_pending_rewards.get("spent_chips", 0)) + cost
			"damage":
				## Applied only when DAMAGE is not the primary outcome kind.
				pass
			"item_choice", "select_item", "loot", "loot_offer", "reward_loot", "combat", "fight":
				## Control-flow effects — handled by outcome.kind.
				pass
			"pale_maiden_pact":
				if StoryEventManager != null:
					StoryEventManager.mark_pale_maiden_pact()
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
	if _run_ended_mid_encounter():
		abort_active_encounter()
		return
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
			if not data.payload.has("locked"):
				data.payload["locked"] = randf() < 0.55
		_:
			pass


func apply_rest_heal(fraction: float = 0.3) -> int:
	## Rest-site option: restore a fraction of Max HP (clamped to full).
	if inventory == null:
		return 0
	var gained := inventory.heal_percent(fraction)
	_pending_rewards["message_key"] = "KEY_STATUS_REPAIR"
	_pending_rewards["healed"] = gained
	_pending_rewards["rest_choice"] = "heal"
	return gained


func apply_rest_remove_harmful() -> int:
	## Rest-site option: cut every harmful / parasitic module out of the frame.
	if inventory == null:
		return 0
	var removed := inventory.remove_all_harmful_items()
	if removed > 0 and player_stats != null and inventory.grid != null:
		player_stats.recalculate_from_equipment(inventory.grid)
	_pending_rewards["message_key"] = "KEY_STATUS_REPAIR"
	_pending_rewards["harmful_removed"] = removed
	_pending_rewards["rest_choice"] = "extract"
	return removed


func complete_rest_site() -> void:
	## Called by RestSiteUI after the player presses Continue.
	if active_encounter == null:
		return
	if active_encounter.type != EncounterData.EncounterType.REST_SITE:
		return
	if not _pending_rewards.has("message_key"):
		_pending_rewards["message_key"] = "KEY_STATUS_REPAIR"
	_finish_encounter(_pending_rewards)


func complete_shop_site() -> void:
	## Called by ShopScreen after the player presses Continue.
	if active_encounter == null:
		return
	if active_encounter.type != EncounterData.EncounterType.SHOP:
		return
	if not _pending_rewards.has("message_key"):
		_pending_rewards["message_key"] = "KEY_STATUS_SHOP"
	_finish_encounter(_pending_rewards)


func complete_chest_site(opened: bool = false) -> void:
	## Called by Main after leaving the chest / chest-loot flow.
	if active_encounter == null:
		return
	if active_encounter.type != EncounterData.EncounterType.CHEST:
		return
	if opened:
		_pending_rewards["message_key"] = "KEY_STATUS_CHEST_OPENED"
		_pending_rewards["chest_opened"] = true
	elif not _pending_rewards.has("message_key"):
		_pending_rewards["message_key"] = "KEY_STATUS_CHEST_LEFT"
		_pending_rewards["chest_opened"] = false
	_finish_encounter(_pending_rewards)


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
	if id_str.is_empty():
		return
	## Neuro-Chips are global currency, not body-grid stacks.
	if id_str.to_upper() == "NEURO_CHIP":
		if GameManager != null:
			var gained: int = GameManager.add_chips(maxi(amount, 1))
			_pending_rewards["neuro_chips"] = gained
		return
	if inventory == null or ItemDatabase == null:
		return
	var qty := maxi(amount, 1)
	## Stackable currency (legacy) merges into a single cell when possible.
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
