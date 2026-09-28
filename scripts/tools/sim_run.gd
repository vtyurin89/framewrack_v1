extends Node
## Headless full-run simulator ("mock game").
##
## Boots a run without any UI: wires CombatManager / EncounterManager /
## RunFlowManager directly, then plays the map with a simple bot policy
## (random dialog choices, greedy item activations). Prints a per-run and
## aggregate summary.
##
## Usage:
##   godot --headless --path . res://scenes/tools/sim_run.tscn -- --runs=5 --seed=1
##   godot --headless --path . res://scenes/tools/sim_run.tscn -- --act=3 --verbose
##
## Flags (after the standalone `--`):
##   --runs=N     number of runs (default 1)
##   --seed=N     RNG seed (default random)
##   --act=N      start each run at act N via debug_jump_to_act
##   --verbose    log every node / combat / encounter
##   --max-steps=N safety cap on map nodes per run (default 400)

const CombatScript := preload("res://scripts/combat/combat_manager.gd")

const STARTING_ITEM_ID := "SCRAP_PIPE"
const STARTING_ARMOR_ID := "HEAVY_SCRAP_PLATE"
const STARTING_CONSUMABLE_ID := "BIO_GEL"

var _combat: Variant
var _enc: EncounterManager
var _run_flow: RunFlowManager

var inventory: InventoryController
var player_stats: PlayerStats

var _rng := RandomNumberGenerator.new()
var _verbose := false
var _runs_total := 1
var _base_seed := 0
var _start_act := 0
var _max_steps := 400
var _god := false
var _log_file: FileAccess

# --- per-run state -----------------------------------------------------------
var _finished := false
var _run_result := "incomplete"
var _steps := 0
var _encounters_done := 0
var _combats_seen := 0
var _combat_over := false
var _encounter_combat_active := false
var _last_enemy_datas: Array = []
var _first_combat_xp_granted := false
var _combat_turns := 0
const _MAX_COMBAT_TURNS := 60

# --- aggregate ---------------------------------------------------------------
var _agg_victories := 0
var _agg_defeats := 0
var _agg_incomplete := 0
var _agg_combats := 0
var _agg_nodes := 0

# --- watchdog ----------------------------------------------------------------
var _frames := 0
const _FRAME_CAP := 200000


func _ready() -> void:
	_parse_args()
	_apply_seed(_base_seed if _base_seed != 0 else int(Time.get_unix_time_from_system()))
	Engine.time_scale = 20.0
	Engine.max_fps = 0
	_build_managers()
	_wire_signals()
	call_deferred("_start_next_run")


func _process(_delta: float) -> void:
	_frames += 1
	if _frames > _FRAME_CAP:
		push_error("sim: watchdog tripped after %d frames" % _frames)
		get_tree().quit(3)


func _parse_args() -> void:
	for raw in OS.get_cmdline_user_args():
		var arg := str(raw)
		if arg.begins_with("--runs="):
			_runs_total = maxi(1, int(arg.trim_prefix("--runs=")))
		elif arg.begins_with("--seed="):
			_base_seed = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--act="):
			_start_act = maxi(0, int(arg.trim_prefix("--act=")))
		elif arg.begins_with("--max-steps="):
			_max_steps = maxi(1, int(arg.trim_prefix("--max-steps=")))
		elif arg.begins_with("--log="):
			_log_file = FileAccess.open(arg.trim_prefix("--log="), FileAccess.WRITE)
		elif arg == "--god":
			_god = true
		elif arg == "--verbose":
			_verbose = true


func _apply_seed(seed_value: int) -> void:
	_rng.seed = seed_value
	seed(seed_value)


func _build_managers() -> void:
	inventory = InventoryController.new()
	player_stats = PlayerStats.new()
	inventory.apply_actor_stats(player_stats)
	inventory.heal_full()

	_combat = CombatScript.new()
	_combat.name = "CombatManager"
	add_child(_combat)

	_enc = EncounterManager.new()
	_enc.name = "EncounterManager"
	add_child(_enc)

	_run_flow = RunFlowManager.new()
	_run_flow.name = "RunFlowManager"
	add_child(_run_flow)

	_combat.setup(inventory, player_stats)
	_enc.setup(inventory, player_stats, _combat)
	_run_flow.setup(_enc)


func _wire_signals() -> void:
	_enc.request_combat.connect(_on_request_combat)
	_enc.request_show_dialog.connect(_on_request_dialog)
	_enc.request_show_placeholder.connect(_on_placeholder)
	_enc.request_show_rest_site.connect(_on_request_rest_site)
	_enc.request_show_shop.connect(_on_request_shop)
	_enc.request_show_chest_reward.connect(_on_request_chest)
	_enc.request_item_selection.connect(_on_request_item_selection)
	_enc.request_dialog_loot.connect(_on_request_dialog_loot)
	_enc.request_post_combat_rewards.connect(_on_request_post_combat_rewards)
	_enc.encounter_completed.connect(_on_encounter_completed)
	_combat.forced_insertion_requested.connect(_on_forced_insertion_requested)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.run_ended.connect(_on_run_ended)
	_run_flow.map_changed.connect(_on_map_changed)
	_run_flow.run_state_changed.connect(_on_run_state_changed)


# ============================================================================
# Run lifecycle
# ============================================================================

func _start_next_run() -> void:
	_finished = false
	_run_result = "incomplete"
	_steps = 0
	_encounters_done = 0
	_combats_seen = 0
	_combat_over = false
	_encounter_combat_active = false
	_last_enemy_datas = []
	_first_combat_xp_granted = false
	_combat_turns = 0

	GameManager.begin_session()
	if GameManager.get_state() != GameManager.GameState.GAMEPLAY:
		GameManager.change_state(GameManager.GameState.GAMEPLAY)
	StoryEventManager.reset_run()
	_seed_starting_loadout()
	if _god:
		inventory.max_hp = 999
		inventory.current_hp = 999

	_log("=== run start (act %s) seed=%d ===" % [
		str(_start_act) if _start_act > 0 else "1..3", _rng.seed
	])
	if _start_act > 0:
		_run_flow.debug_jump_to_act(_start_act)
	else:
		_run_flow.start_new_run()


func _seed_starting_loadout() -> void:
	inventory.reset_run()
	GameManager.reset_currency()
	player_stats.reset_run()
	inventory.apply_actor_stats(player_stats)
	inventory.heal_full()
	var pipe: ItemData = ItemDatabase.create_instance(STARTING_ITEM_ID)
	if pipe != null:
		inventory.place_item(pipe, BodyGrid.STARTER_ORIGIN)
	var armor: ItemData = ItemDatabase.create_instance(STARTING_ARMOR_ID)
	if armor != null:
		inventory.try_place_anywhere(armor)
	var gel: ItemData = ItemDatabase.create_instance(STARTING_CONSUMABLE_ID)
	if gel != null:
		inventory.try_place_anywhere(gel)


func _on_map_changed(_map: MapData) -> void:
	if _finished:
		return
	if _run_flow.state == RunFlowManager.RunState.MAP_VIEW:
		call_deferred("_pick_next_node")


func _on_run_state_changed(_prev: int, new_state: int) -> void:
	if _finished:
		return
	match new_state:
		RunFlowManager.RunState.VICTORY:
			_finish_run("victory")
		RunFlowManager.RunState.GAME_OVER:
			_finish_run("defeat")


func _pick_next_node() -> void:
	if _finished or _run_flow.state != RunFlowManager.RunState.MAP_VIEW:
		return
	var map := _run_flow.get_map_data()
	if map == null:
		return
	var available: Array = map.get_available_nodes()
	if available.is_empty():
		return
	if _steps >= _max_steps:
		_finish_run("step-cap")
		return
	_steps += 1
	var node: MapNodeData = _choose_node(available)
	_log("node %s layer=%d type=%s" % [
		node.id, node.layer, _node_type_name(node.node_type)
	], true)
	_run_flow.select_node(node)


func _choose_node(available: Array) -> MapNodeData:
	# Heal when hurt; otherwise take the first forward node, preferring combat.
	var want_heal := inventory.current_hp < int(inventory.max_hp * 0.45)
	if want_heal:
		for node: MapNodeData in available:
			if node.node_type == MapNodeData.MapNodeType.REPAIR:
				return node
	available.sort_custom(func(a: MapNodeData, b: MapNodeData) -> bool:
		return _node_priority(a.node_type) < _node_priority(b.node_type)
	)
	return available[0]


func _node_priority(t: int) -> int:
	match t:
		MapNodeData.MapNodeType.ELITE:
			return 0
		MapNodeData.MapNodeType.COMBAT:
			return 1
		MapNodeData.MapNodeType.EVENT:
			return 2
		MapNodeData.MapNodeType.SHOP:
			return 3
		MapNodeData.MapNodeType.REWARD:
			return 4
		MapNodeData.MapNodeType.REPAIR:
			return 5
		_:
			return 6


func _on_encounter_completed(_rewards: Dictionary) -> void:
	_encounters_done += 1


func _on_run_ended(_victory: bool) -> void:
	_finish_run("victory")


func _finish_run(result: String) -> void:
	if _finished:
		return
	_finished = true
	_run_result = result
	match result:
		"victory":
			_agg_victories += 1
		"defeat":
			_agg_defeats += 1
		_:
			_agg_incomplete += 1
	_agg_combats += _combats_seen
	_agg_nodes += _steps
	_log("=== run end: %s | act=%d nodes=%d combats=%d hp=%d/%d level=%d chips=%d ===" % [
		result.to_upper(),
		_run_flow.current_act_index,
		_steps,
		_combats_seen,
		inventory.current_hp,
		inventory.max_hp,
		player_stats.level,
		GameManager.get_chips(),
	])
	if _agg_victories + _agg_defeats + _agg_incomplete < _runs_total:
		call_deferred("_start_next_run")
		return
	_print_aggregate()
	var exit_code := 0 if _agg_victories > 0 else 2
	get_tree().quit(exit_code)


# ============================================================================
# Combat
# ============================================================================

func _on_request_combat(enemy_datas: Array, encounter: EncounterData) -> void:
	_combats_seen += 1
	_combat_over = false
	_combat_turns = 0
	_encounter_combat_active = true
	var datas: Array[EnemyData] = []
	for entry in enemy_datas:
		if entry is EnemyData:
			datas.append(entry as EnemyData)
	if _god:
		var weak: Array[EnemyData] = []
		for d: EnemyData in datas:
			var copy := d.duplicate(true) as EnemyData
			if copy != null:
				copy.base_hp = 1
				copy.max_hp = 1
				weak.append(copy)
		datas = weak
	_last_enemy_datas = datas
	var cap := 2
	if encounter != null:
		cap = maxi(1, int(encounter.payload.get("max_attackers_per_turn", 2)))
	var names: PackedStringArray = []
	for d: EnemyData in datas:
		names.append(d.id)
	_log("combat #%d vs [%s] cap=%d" % [_combats_seen, ", ".join(names), cap], true)
	_combat.start_combat(datas, cap)
	_run_combat_loop()


func _run_combat_loop() -> void:
	while not _combat_over and _combat.is_in_combat():
		if _combat.is_player_turn_active():
			_take_player_turn()
		await get_tree().process_frame


func _take_player_turn() -> void:
	var safety := 0
	while _combat.is_player_turn_active() and not _combat_over and safety < 100:
		safety += 1
		var placed: PlacedItem = _choose_activation()
		_log("    PLAYER ap=%d pick=%s" % [
			int(_combat.current_ap),
			placed.data.id if placed != null else "<none>",
		], true)
		if placed == null:
			break
		if not _combat.activate_item(placed):
			_log("    activate failed: %s" % placed.data.id, true)
			break
	if _combat.is_player_turn_active() and not _combat_over:
		_combat.end_player_turn()
		_log("    end_player_turn -> state=%d player_turn=%s in_combat=%s" % [
			int(_combat.state),
			str(_combat.is_player_turn_active()),
			str(_combat.is_in_combat()),
		], true)


func _choose_activation() -> PlacedItem:
	var weapons: Array[PlacedItem] = []
	var others: Array[PlacedItem] = []
	for placed: PlacedItem in inventory.grid.items:
		if placed == null or placed.data == null:
			continue
		if not _combat.can_activate_item(placed):
			continue
		var data: ItemData = placed.data
		if data.is_harmful:
			continue
		if (
			data.target_type == ItemData.TargetType.SINGLE_ENEMY
			or data.target_type == ItemData.TargetType.ALL_ENEMIES
		):
			weapons.append(placed)
		else:
			others.append(placed)
	if not weapons.is_empty():
		return weapons[_rng.randi() % weapons.size()]
	if not others.is_empty():
		return others[_rng.randi() % others.size()]
	return null


func _on_forced_insertion_requested(item_id: String) -> void:
	## Enemy forced-insertion (chimera larva pounce) waits on UI in the real game.
	_combat.try_auto_insert_item(item_id)
	_combat.complete_forced_item_insertion()


func _on_turn_started(is_player: bool) -> void:
	if is_player:
		return
	_combat_turns += 1
	if _combat_turns >= _MAX_COMBAT_TURNS:
		_log("combat #%d STALLED after %d enemy turns (hp=%d/%d)" % [
			_combats_seen, _combat_turns, inventory.current_hp, inventory.max_hp
		])
		_combat_over = true
		_encounter_combat_active = false
		_combat.abort_combat()
		_finish_run("stall")


func _on_combat_ended(victory: bool) -> void:
	_combat_over = true
	if not _encounter_combat_active:
		return
	_encounter_combat_active = false
	if not victory:
		# `_lose()` emits combat_ended before GameManager.trigger_game_over(),
		# so don't rely on is_game_over() here.
		_finish_run("defeat")
		return
	if GameManager.is_game_over():
		_finish_run("defeat")
		return
	_grant_combat_exp()
	_award_level_ups()
	_enc.notify_combat_finished(true)


func _grant_combat_exp() -> void:
	var gained := 0
	if not _first_combat_xp_granted:
		_first_combat_xp_granted = true
		gained = ExpRewardResolver.resolve_exp(BalanceTypes.Tier.NONE, 30, 0.0, player_stats)
	else:
		gained = ExpRewardResolver.resolve_combat_exp(_last_enemy_datas, player_stats)
	if gained > 0:
		player_stats.add_exp(gained)


func _award_level_ups() -> void:
	# Bot spends pending level-ups round-robin across STR/END/AGI/LCK/INT.
	var order := ["strength", "endurance", "agility", "luck", "intelligence"]
	var i := 0
	while player_stats.consume_pending_level_up():
		player_stats.add_stat_bonus(order[i % order.size()], 1)
		i += 1
		inventory.apply_actor_stats(player_stats)


func _on_request_post_combat_rewards(encounter: EncounterData) -> void:
	_grant_post_combat_rewards(encounter)
	_enc.complete_post_combat_rewards()


func _grant_post_combat_rewards(encounter: EncounterData) -> void:
	var kind := "NORMAL"
	if encounter != null:
		if bool(encounter.payload.get("force_elite_rewards", false)):
			kind = "ELITE"
		else:
			match encounter.type:
				EncounterData.EncounterType.COMBAT_ELITE:
					kind = "ELITE"
				EncounterData.EncounterType.COMBAT_BOSS:
					kind = "BOSS"
				_:
					kind = "NORMAL"
	var depth := 1
	if _run_flow.current_map_data != null:
		var cur := _run_flow.current_map_data.get_node(_run_flow.current_map_data.current_node_id)
		if cur != null:
			depth = maxi(cur.layer, 0)
	var loot: Array[ItemData] = []
	var max_picks := RewardManager.MAX_PICKS
	if kind == "BOSS":
		loot = RewardManager.generate_boss_rewards()
		max_picks = RewardManager.BOSS_PICKS
	else:
		loot = RewardManager.generate_rewards(kind, depth)
		if kind == "ELITE":
			loot = RewardManager.ensure_at_least_one_rare(loot)
	if GameManager != null:
		GameManager.award_combat_chips(kind, depth)
	var taken := 0
	for item: ItemData in loot:
		if item == null or taken >= max_picks:
			continue
		var instance: ItemData = ItemDatabase.create_instance(item.id)
		if instance != null and inventory.try_place_anywhere(instance):
			taken += 1
	_log("  loot: %d/%d items taken (%s)" % [taken, loot.size(), kind], true)


# ============================================================================
# Dialogs
# ============================================================================

func _on_request_dialog(dialog: DialogEventData, _encounter: EncounterData) -> void:
	if dialog == null:
		_enc.apply_dialog_outcome(DialogOutcomeData.make_end())
		return
	_simulate_dialog(dialog)


func _simulate_dialog(dialog: DialogEventData) -> void:
	var visits: Dictionary = {}
	var used: Dictionary = {}
	var node_id := dialog.start_node_id
	var guard := 0
	_log("dialog %s (start=%s)" % [dialog.id, node_id], true)
	while guard < 500:
		guard += 1
		if GameManager.is_game_over():
			_log("  dlg abort: game over", true)
			return
		var node := dialog.get_node(node_id)
		if node == null:
			_log("  dlg node NULL -> end", true)
			_enc.apply_dialog_outcome(DialogOutcomeData.make_end())
			return
		_log("  dlg node=%s choices=%d branch=%s" % [
			node.id, node.choices.size(), str(node.has_branch())
		], true)
		if node.has_branch():
			var visit := int(visits.get(node.id, 0))
			visits[node.id] = visit + 1
			var escaped := _rng.randf() < node.get_branch_chance(visit)
			node_id = node.branch_success_node if escaped else node.branch_failure_node
			continue
		if node.choices.is_empty():
			_enc.apply_dialog_outcome(DialogOutcomeData.make_end())
			return
		var choice := _choose_choice(node, used)
		if choice == null:
			_enc.apply_dialog_outcome(DialogOutcomeData.make_end())
			return
		if not choice.choice_id.strip_edges().is_empty():
			used[choice.choice_id] = true
		var outcome := _resolve_choice(choice)
		var next_id := _apply_and_follow(outcome)
		if next_id.is_empty():
			return
		node_id = next_id
	if guard >= 500:
		_log("  dlg GUARD TRIPPED id=%s last=%s" % [dialog.id, node_id])
		_enc.apply_dialog_outcome(DialogOutcomeData.make_end())


func _choose_choice(node: DialogNodeData, used: Dictionary) -> DialogChoiceData:
	var candidates: Array[DialogChoiceData] = []
	for choice: DialogChoiceData in node.choices:
		if choice == null:
			continue
		if not choice.is_available(inventory):
			continue
		if (
			node.disable_used_choices
			and not choice.choice_id.strip_edges().is_empty()
			and used.has(choice.choice_id)
		):
			continue
		candidates.append(choice)
	if candidates.is_empty():
		return null
	return candidates[_rng.randi() % candidates.size()]


func _resolve_choice(choice: DialogChoiceData) -> DialogOutcomeData:
	if choice.has_stat_check():
		var result: StatCheckManager.CheckResult = _enc.resolve_choice_stat_check(choice, 0)
		var passed := result != null and result.is_success
		return choice.success_outcome if passed else choice.failure_outcome
	return choice.success_outcome


func _apply_and_follow(outcome: DialogOutcomeData) -> String:
	if outcome == null:
		_enc.apply_dialog_outcome(null)
		return ""
	var kind := outcome.kind
	if not _enc.apply_dialog_outcome(outcome):
		return ""
	if GameManager.is_game_over():
		return ""
	if outcome.force_insert_item and not outcome.item_id.is_empty():
		var item: ItemData = ItemDatabase.create_instance(outcome.item_id)
		if item != null:
			inventory.try_place_anywhere(item)
	match kind:
		DialogOutcomeData.OutcomeKind.END, \
		DialogOutcomeData.OutcomeKind.SKIP, \
		DialogOutcomeData.OutcomeKind.COMBAT, \
		DialogOutcomeData.OutcomeKind.SHOP:
			return ""
	var next_id := outcome.next_node_id.strip_edges()
	if not next_id.is_empty() and next_id != _end_encounter_id():
		return next_id
	# Terminal: the dialog walk is done. `apply_dialog_outcome` already closed
	# effect outcomes with no next node; a no-op END covers CONTINUE/select.
	_enc.apply_dialog_outcome(DialogOutcomeData.make_end(outcome.message_key))
	return ""


func _end_encounter_id() -> String:
	return "end_encounter"


func _on_request_item_selection(item_pool: Array, _title: String) -> void:
	var pick: ItemData = null
	if not item_pool.is_empty():
		var entry = item_pool[_rng.randi() % item_pool.size()]
		if entry is ItemData:
			pick = entry
	_enc.resolve_item_selection(pick)


func _on_request_dialog_loot(items: Array, pick_count: int, _title_key: String) -> void:
	var pool: Array[ItemData] = []
	for entry in items:
		if entry is ItemData:
			pool.append(entry as ItemData)
	for _i in maxi(1, pick_count):
		if pool.is_empty():
			break
		var pick: ItemData = pool[_rng.randi() % pool.size()]
		var instance: ItemData = ItemDatabase.create_instance(pick.id)
		if instance != null:
			inventory.try_place_anywhere(instance)
	_enc.complete_dialog_loot()


func _on_placeholder(_encounter: EncounterData, _message_key: String) -> void:
	pass


# ============================================================================
# Other nodes
# ============================================================================

func _on_request_rest_site(_encounter: EncounterData) -> void:
	if inventory.current_hp < int(inventory.max_hp * 0.7):
		_enc.apply_rest_heal(0.3)
	else:
		_enc.apply_rest_remove_harmful()
	_enc.complete_rest_site()


func _on_request_shop(_encounter: EncounterData, price_multiplier: float) -> void:
	var act := maxi(1, _run_flow.current_act_index)
	var stock: Array[ItemData] = ShopManager.generate_stock(act, ShopManager.STOCK_COUNT)
	ShopManager.begin_session(stock, price_multiplier)
	for item: ItemData in stock:
		if item == null:
			continue
		if ShopManager.can_purchase(item):
			ShopManager.try_purchase(item)
	ShopManager.clear_session()
	_enc.complete_shop_site()


func _on_request_chest(_encounter: EncounterData) -> void:
	_enc.complete_chest_site(true)


# ============================================================================
# Logging
# ============================================================================

func _log(msg: String, verbose_only: bool = false) -> void:
	if verbose_only and not _verbose:
		return
	print("[sim] %s" % msg)
	if _log_file != null:
		_log_file.store_line("[sim] %s" % msg)
		_log_file.flush()


func _node_type_name(t: int) -> String:
	match t:
		MapNodeData.MapNodeType.INTRO:
			return "INTRO"
		MapNodeData.MapNodeType.MAIN_STORY:
			return "STORY"
		MapNodeData.MapNodeType.COMBAT:
			return "COMBAT"
		MapNodeData.MapNodeType.EVENT:
			return "EVENT"
		MapNodeData.MapNodeType.REPAIR:
			return "REPAIR"
		MapNodeData.MapNodeType.SHOP:
			return "SHOP"
		MapNodeData.MapNodeType.ELITE:
			return "ELITE"
		MapNodeData.MapNodeType.BOSS:
			return "BOSS"
		MapNodeData.MapNodeType.STAIRS:
			return "STAIRS"
		MapNodeData.MapNodeType.REWARD:
			return "REWARD"
		_:
			return "?"


func _print_aggregate() -> void:
	var total := _agg_victories + _agg_defeats + _agg_incomplete
	if total <= 0:
		return
	print("[sim] ---- aggregate over %d runs ----" % total)
	print("[sim] victories=%d defeats=%d incomplete=%d | win-rate=%.0f%%" % [
		_agg_victories,
		_agg_defeats,
		_agg_incomplete,
		(float(_agg_victories) / float(total)) * 100.0,
	])
	print("[sim] avg combats/run=%.1f avg nodes/run=%.1f" % [
		float(_agg_combats) / float(total),
		float(_agg_nodes) / float(total),
	])
