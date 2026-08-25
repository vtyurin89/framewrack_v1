class_name EnemyInstance
extends ActorStats
## Runtime enemy: difficulty-scaled HP, stats, ability rolls, and turn-phase state.

const CRIT_DAMAGE_MULT := 1.4
const MIN_STAT := 1
## TODO: Remove this temporary DEV HP cap and rebalance enemy HP from data/CSV
## (base_hp + endurance scaling + difficulty multiplier) before release.
## Caps enemies above this value; enemies with ≤ this HP are unchanged.
const DEV_FORCE_ENEMY_HP := 20

var data: EnemyData
var max_hp: int = 1
var current_hp: int = 1
var current_block: int = 0
var is_selected: bool = false
var abilities: Array[EnemyAbility] = []
## Combat status effects (poison, burn, rust, …).
var statuses: StatusController = StatusController.new()
## Summoner link for summoned_creature minions (WeakRef to EnemyInstance).
var summoner_ref: WeakRef = null
## Pocket thief: chips stolen this combat (returned on death, kept on flee).
var stolen_chips: int = 0
## Stasis Pod Right: grid item stolen this combat (returned on pod death).
var stolen_grid_item: ItemData = null
## Number of combat turns this enemy has started (for PRE_ACTION intervals).
var turns_taken: int = 0
## Psychosis: direct attack HP hits received during the current player turn.
var direct_hits_this_player_turn: int = 0
## Psychosis: whether the +1 STR threshold already fired this player turn.
var _psychosis_triggered_this_turn: bool = false
## Remaining cooldown turns keyed by ability id.
var _ability_cooldowns: Dictionary = {}
## Prepared / charged ability ids (for requires_prepare skills like Bumper Slam).
var _prepared_ability_ids: Dictionary = {}
## Next main ability the AI must attempt when usable (set by prepare skills).
var forced_next_ability_id: String = ""
## Stacking permanent combat buff totals keyed by stat id (strength, luck, …).
var _stat_buff_stacks: Dictionary = {}
## Committed next main ability (matches the telegraphed CombatIntention).
var planned_ability: EnemyAbility = null
var current_intention: CombatIntention = null


func setup(blueprint: EnemyData) -> void:
	data = blueprint
	turns_taken = 0
	stolen_chips = 0
	stolen_grid_item = null
	summoner_ref = null
	direct_hits_this_player_turn = 0
	_psychosis_triggered_this_turn = false
	_ability_cooldowns.clear()
	_prepared_ability_ids.clear()
	_stat_buff_stacks.clear()
	forced_next_ability_id = ""
	if data == null:
		reset_combat_stats(MIN_STAT, MIN_STAT, MIN_STAT, MIN_STAT, MIN_STAT)
		max_hp = 1
		current_hp = 1
		abilities.clear()
		planned_ability = null
		current_intention = null
		if statuses == null:
			statuses = StatusController.new()
		else:
			statuses.clear_combat_statuses()
		return

	strength = maxi(MIN_STAT, data.strength)
	agility = maxi(MIN_STAT, data.agility)
	endurance = maxi(MIN_STAT, data.endurance)
	intelligence = maxi(MIN_STAT, data.intelligence)
	luck = maxi(MIN_STAT, data.luck)

	var hp_mult := 1.0
	if GameSettings != null:
		hp_mult = GameSettings.get_enemy_hp_multiplier()
	## ActorStats formula: base_hp + (endurance * 5), then difficulty mult.
	var raw_hp := float(get_max_hp(data.get_effective_base_hp()))
	max_hp = maxi(1, int(round(raw_hp * hp_mult)))
	## TODO: Remove DEV_FORCE_ENEMY_HP — temporary HP cap for development balance testing.
	## Only clamps enemies that would exceed the cap; lower HP values stay as-is.
	if DEV_FORCE_ENEMY_HP > 0:
		max_hp = mini(max_hp, DEV_FORCE_ENEMY_HP)
	current_hp = max_hp
	current_block = 0
	is_selected = false
	if statuses == null:
		statuses = StatusController.new()
	else:
		statuses.clear_combat_statuses()

	abilities.clear()
	for ability: EnemyAbility in data.abilities:
		if ability != null:
			abilities.append(ability)
	planned_ability = null
	current_intention = null
	## Trait passives applied at spawn (e.g. summoned_creature on slaver minions).
	for trait_id: String in data.trait_ids:
		var tid := trait_id.strip_edges().to_lower()
		if tid.is_empty() or EnemyData.MECHANIC_TRAIT_IDS.has(tid):
			continue
		statuses.apply_status_by_id(tid, 1)


func begin_enemy_turn() -> void:
	## Hook at act start. `turns_taken` counts completed acts (see end_enemy_turn).
	pass


func end_enemy_turn() -> void:
	## Count this act as completed so planning and resolve share the same clock.
	## Tick cooldowns after the main action so a 1-turn CD skips the next act.
	turns_taken += 1
	_tick_ability_cooldowns()


func _tick_ability_cooldowns() -> void:
	var keys: Array = _ability_cooldowns.keys()
	for key in keys:
		var remaining: int = int(_ability_cooldowns[key]) - 1
		if remaining <= 0:
			_ability_cooldowns.erase(key)
		else:
			_ability_cooldowns[key] = remaining


func start_ability_cooldown(ability: EnemyAbility, turns: int) -> void:
	if ability == null or turns <= 0:
		return
	## +1 because end_enemy_turn() ticks on the cast turn; net wait = `turns` full acts.
	_ability_cooldowns[ability.id] = turns + 1


func is_ability_on_cooldown(ability: EnemyAbility) -> bool:
	if ability == null:
		return false
	return int(_ability_cooldowns.get(ability.id, 0)) > 0


func get_current_act_number() -> int:
	## 1-based act index; matches available_from_turn in abilities CSV.
	return turns_taken + 1


func is_ability_unlocked(ability: EnemyAbility) -> bool:
	if ability == null:
		return false
	return ability.is_unlocked_for_act(get_current_act_number())


func can_use_ability(ability: EnemyAbility) -> bool:
	if ability == null:
		return false
	if not is_ability_unlocked(ability):
		return false
	if is_ability_on_cooldown(ability):
		return false
	if ability.requires_prepare and not is_ability_prepared(ability.id):
		return false
	return true


func arm_prepared_ability(ability_id: String) -> void:
	var needle := ability_id.strip_edges()
	if needle.is_empty():
		return
	_prepared_ability_ids[needle] = true
	forced_next_ability_id = needle


func is_ability_prepared(ability_id: String) -> bool:
	return bool(_prepared_ability_ids.get(ability_id.strip_edges(), false))


func consume_prepared_ability(ability_id: String) -> void:
	var needle := ability_id.strip_edges()
	if needle.is_empty():
		return
	_prepared_ability_ids.erase(needle)
	if forced_next_ability_id == needle:
		forced_next_ability_id = ""


func apply_stackable_stat_buff(stat_key: String, delta: int) -> int:
	## All enemy combat stat buffs stack additively for the rest of the fight.
	if delta == 0:
		return get_stat(EnemyAbility.parse_stat_scaling(stat_key))
	var key := stat_key.strip_edges().to_lower()
	_stat_buff_stacks[key] = int(_stat_buff_stacks.get(key, 0)) + delta
	match EnemyAbility.parse_stat_scaling(key):
		EnemyAbility.StatScaling.STRENGTH:
			strength = maxi(MIN_STAT, strength + delta)
			return strength
		EnemyAbility.StatScaling.AGILITY:
			agility = maxi(MIN_STAT, agility + delta)
			return agility
		EnemyAbility.StatScaling.ENDURANCE:
			endurance = maxi(MIN_STAT, endurance + delta)
			return endurance
		EnemyAbility.StatScaling.INTELLIGENCE:
			intelligence = maxi(MIN_STAT, intelligence + delta)
			return intelligence
		EnemyAbility.StatScaling.LUCK:
			luck = maxi(MIN_STAT, luck + delta)
			return luck
		_:
			luck = maxi(MIN_STAT, luck + delta)
			return luck


func get_stat_buff_stacks(stat_key: String) -> int:
	return int(_stat_buff_stacks.get(stat_key.strip_edges().to_lower(), 0))


func find_ability(ability_id: String) -> EnemyAbility:
	var needle := ability_id.strip_edges()
	if needle.is_empty():
		return null
	for ability: EnemyAbility in abilities:
		if ability != null and ability.id == needle:
			return ability
	return null


func find_ability_any(ability_ids: Array[String]) -> EnemyAbility:
	for ability_id: String in ability_ids:
		var found := find_ability(ability_id)
		if found != null:
			return found
	return null


func get_hp_ratio() -> float:
	return float(current_hp) / float(maxi(max_hp, 1))


func get_localized_name() -> String:
	if data != null:
		return data.get_localized_name()
	return tr("ENEMY_UNKNOWN_NAME")


func get_localized_description() -> String:
	if data != null:
		return data.get_localized_description()
	return ""


func roll_crit() -> bool:
	var chance := get_crit_chance()
	if chance <= 0.0:
		return false
	return randf() < chance


func get_stat(scaling: EnemyAbility.StatScaling) -> int:
	match scaling:
		EnemyAbility.StatScaling.STRENGTH:
			return strength
		EnemyAbility.StatScaling.AGILITY:
			return agility
		EnemyAbility.StatScaling.ENDURANCE:
			return endurance
		EnemyAbility.StatScaling.INTELLIGENCE:
			return intelligence
		EnemyAbility.StatScaling.LUCK:
			return luck
		_:
			return 0


func get_ability_value_range(ability: EnemyAbility) -> Vector2i:
	if ability == null:
		return Vector2i.ZERO
	var r := ability.get_clamped_range()
	if ability.type == EnemyAbility.AbilityType.MULTI_HIT:
		var half_str := EnemyAbilityExecutor.resolve_damage_stat_bonus(self, ability)
		return Vector2i(r.x + half_str, r.y + half_str)
	## Shield: base_block + agility (always).
	if (
		ability.type == EnemyAbility.AbilityType.BLOCK
		or ability.main_effect.strip_edges().to_lower() == "shield"
	):
		return Vector2i(r.x + agility, r.y + agility)
	if ability.stat_scaling == EnemyAbility.StatScaling.NONE:
		return r
	var stat := get_stat(ability.stat_scaling)
	return Vector2i(r.x + stat, r.y + stat)


func format_ability_tooltip(ability: EnemyAbility) -> String:
	if ability == null:
		return ""
	var r := ability.get_clamped_range()
	if ability.type == EnemyAbility.AbilityType.PRE_ACTION:
		var interval := ability.trigger_interval if ability.trigger_interval > 0 else 2
		return tr("KEY_ABILITY_PRE_ACTION_FMT") % [interval]
	if ability.type == EnemyAbility.AbilityType.MULTI_HIT:
		var hits := ability.hit_count if ability.hit_count > 0 else 3
		var threshold_pct := int(round((ability.hp_threshold if ability.hp_threshold > 0.0 else 0.4) * 100.0))
		var scaled_mh := get_ability_value_range(ability)
		var half_str := EnemyAbilityExecutor.resolve_damage_stat_bonus(self, ability)
		return tr("KEY_ABILITY_MULTI_HIT_FMT") % [hits, scaled_mh.x, scaled_mh.y, half_str, threshold_pct]
	var scaled := get_ability_value_range(ability)
	var is_shield := (
		ability.type == EnemyAbility.AbilityType.BLOCK
		or ability.main_effect.strip_edges().to_lower() == "shield"
	)
	var stat := agility if is_shield else get_stat(ability.stat_scaling)
	var stat_key := "KEY_AGI" if is_shield else ability.stat_label_key()
	var action_verb := tr("KEY_ABILITY_DEALS")
	match ability.type:
		EnemyAbility.AbilityType.BLOCK:
			action_verb = tr("KEY_ABILITY_BLOCKS")
		EnemyAbility.AbilityType.HEAL:
			action_verb = tr("KEY_ABILITY_HEALS")
		EnemyAbility.AbilityType.SPECIAL:
			action_verb = tr("KEY_ABILITY_SPECIAL")
		_:
			action_verb = tr("KEY_ABILITY_DEALS")
	if is_shield:
		action_verb = tr("KEY_ABILITY_BLOCKS")
	if stat > 0 and not stat_key.is_empty():
		return tr("KEY_ABILITY_RANGE_STAT_FMT") % [
			action_verb,
			scaled.x,
			scaled.y,
			r.x,
			r.y,
			stat,
			tr(stat_key),
		]
	return tr("KEY_ABILITY_RANGE_FMT") % [action_verb, scaled.x, scaled.y, r.x, r.y]


func choose_ability() -> EnemyAbility:
	## Weighted pick from the main action deck only (excludes PRE_ACTION / MULTI_HIT / on-cooldown).
	var deck: Array[EnemyAbility] = []
	for ability: EnemyAbility in abilities:
		if ability == null or not ability.is_main_deck_ability():
			continue
		if not can_use_ability(ability):
			continue
		deck.append(ability)
	if deck.is_empty():
		return null
	var total := 0.0
	var weights: Array[float] = []
	for ability: EnemyAbility in deck:
		var w := ability.base_ai_weight
		if GameSettings != null:
			w *= GameSettings.get_ability_weight_multiplier(int(ability.weight_class))
		w = maxf(0.01, w)
		weights.append(w)
		total += w
	var roll := randf() * total
	var cursor := 0.0
	for i in deck.size():
		cursor += weights[i]
		if roll <= cursor:
			return deck[i]
	return deck[deck.size() - 1]


func resolve_ability(ability: EnemyAbility) -> Dictionary:
	## Returns { amount, is_crit, base_roll, stat, type, ability }.
	var result := {
		"amount": 0,
		"is_crit": false,
		"base_roll": 0,
		"stat": 0,
		"type": EnemyAbility.AbilityType.DAMAGE,
		"ability": ability,
	}
	if ability == null:
		return result

	var base_roll := ability.roll_base()
	var stat := get_stat(ability.stat_scaling)
	var raw := base_roll + stat
	var is_crit := roll_crit()
	var amount := raw
	if is_crit:
		amount = int(round(float(raw) * CRIT_DAMAGE_MULT))

	match ability.type:
		EnemyAbility.AbilityType.DAMAGE, EnemyAbility.AbilityType.SPECIAL:
			if GameSettings != null:
				amount = int(round(float(amount) * GameSettings.get_enemy_damage_multiplier()))
		_:
			pass

	result["amount"] = maxi(0, amount)
	result["is_crit"] = is_crit
	result["base_roll"] = base_roll
	result["stat"] = stat
	result["type"] = ability.type
	return result


func resolve_multi_hit_base_rolls(ability: EnemyAbility, hit_count: int) -> Array[int]:
	## MULTI_HIT: consecutive base rolls only — no Strength / stat bonus.
	var hits: Array[int] = []
	if ability == null or hit_count <= 0:
		return hits
	for _i in hit_count:
		var amount := ability.roll_base()
		if GameSettings != null:
			amount = int(round(float(amount) * GameSettings.get_enemy_damage_multiplier()))
		hits.append(maxi(0, amount))
	return hits


func apply_incoming_damage(amount: int, pierce_block: bool = false) -> int:
	## Absorb with enemy block first; returns HP lost.
	## Evasion fully negates the instance before block.
	## pierce_block: skip Block and apply remaining damage straight to HP.
	if amount > 0 and statuses != null and statuses.try_consume_evasion():
		return 0
	var remaining := maxi(0, amount)
	if not pierce_block and current_block > 0:
		var absorbed := mini(current_block, remaining)
		current_block -= absorbed
		remaining -= absorbed
	var before := current_hp
	current_hp = maxi(0, current_hp - remaining)
	return before - current_hp


func get_summoner() -> EnemyInstance:
	if summoner_ref == null:
		return null
	return summoner_ref.get_ref() as EnemyInstance


func set_summoner(master: EnemyInstance) -> void:
	summoner_ref = weakref(master) if master != null else null


func is_summoned_creature() -> bool:
	return statuses != null and statuses.has_status("summoned_creature")


func awards_exp() -> bool:
	if is_summoned_creature():
		return false
	return true


func gain_block(amount: int) -> void:
	if amount > 0:
		current_block += amount


func heal(amount: int) -> int:
	if amount <= 0:
		return 0
	var before := current_hp
	current_hp = mini(max_hp, current_hp + amount)
	return current_hp - before


func get_trait_ids() -> Array[String]:
	## Runtime trait id list from the blueprint (may be empty).
	var result: Array[String] = []
	if data == null:
		return result
	for trait_id: String in data.trait_ids:
		if not trait_id.is_empty():
			result.append(trait_id)
	return result


func has_enemy_trait(trait_id: String) -> bool:
	var needle := trait_id.strip_edges().to_lower()
	if needle.is_empty():
		return false
	for tid: String in get_trait_ids():
		if tid.strip_edges().to_lower() == needle:
			return true
	return false


func has_permanent_shield() -> bool:
	## Block persists across this enemy's turns when the hidden trait is present.
	return has_enemy_trait(EnemyData.TRAIT_PERMANENT_SHIELD)


func has_always_reroll_intent() -> bool:
	## Mad/unstable enemies: HP damage always forces a fresh intention roll.
	return (
		has_enemy_trait(EnemyData.TRAIT_ALWAYS_REROLL_INTENT)
		or has_enemy_trait(EnemyData.TRAIT_UNPREDICTABLE)
	)


func has_psychosis() -> bool:
	return has_enemy_trait(EnemyData.TRAIT_PSYCHOSIS)


func reset_psychosis_turn_tracking() -> void:
	direct_hits_this_player_turn = 0
	_psychosis_triggered_this_turn = false


func register_direct_attack_hit() -> bool:
	## Counts one player-attack HP hit for Psychosis. Returns true if STR buff applied.
	if not has_psychosis() or not is_alive():
		return false
	direct_hits_this_player_turn += 1
	if _psychosis_triggered_this_turn or direct_hits_this_player_turn < 3:
		return false
	_psychosis_triggered_this_turn = true
	apply_stackable_stat_buff("strength", 1)
	return true


func clear_block_for_new_turn() -> bool:
	## Mirror player Block expiry. Returns true if Block was cleared.
	if has_permanent_shield():
		return false
	if current_block <= 0:
		return false
	current_block = 0
	return true


func has_traits() -> bool:
	return not get_trait_ids().is_empty()


func is_alive() -> bool:
	return current_hp > 0


func evaluate_intention(_player_state = null, combat_context = null) -> CombatIntention:
	## Commit next main action and build a rich CombatIntention telegraph.
	if not is_alive():
		clear_intention()
		return current_intention
	var action: Dictionary = EnemyAI.commit_main_action(self, true, combat_context)
	var ability: EnemyAbility = action.get("ability") as EnemyAbility
	if ability == null:
		current_intention = CombatIntention.new()
		current_intention.primary_type = CombatIntention.Type.UNKNOWN
	else:
		current_intention = CombatIntention.from_ability(self, ability)
	return current_intention


func reevaluate_intention_for_trigger(trigger: String, combat_context = null) -> bool:
	## Soft reactive refresh. Returns true only when the planned ability changed.
	## Triggers: "hp_damage" (self HP hit), "ally_death" (another enemy died).
	if not is_alive():
		clear_intention()
		return true
	if not EnemyAI.should_recommit_intention(self, combat_context, trigger):
		return false
	var previous: EnemyAbility = planned_ability
	## Free this unit's reserved attacker slot before recommitting.
	planned_ability = null
	if combat_context != null and combat_context.has_method("recount_attacker_slots_from_plans"):
		combat_context.call("recount_attacker_slots_from_plans")
	evaluate_intention(null, combat_context)
	return previous != planned_ability


func reevaluate_intention(force: bool = false, combat_context = null) -> CombatIntention:
	## Legacy entry: force = full recommit; otherwise reason-check as HP damage.
	if force:
		return evaluate_intention(null, combat_context)
	reevaluate_intention_for_trigger("hp_damage", combat_context)
	return current_intention


func clear_intention() -> void:
	planned_ability = null
	if current_intention == null:
		current_intention = CombatIntention.new()
	current_intention.clear()


func mark_fleeing_next_turn() -> void:
	## Apply fleeing status and lock the telegraph to flee (escape on next act start).
	if statuses == null:
		statuses = StatusController.new()
	statuses.apply_status_by_id(StatusEffect.FLEEING, 1)
	var flee_ability := find_ability("ABILITY_THIEF_FLEE")
	if flee_ability != null:
		planned_ability = flee_ability
		current_intention = CombatIntention.from_ability(self, flee_ability)
	else:
		planned_ability = null
		current_intention = CombatIntention.make_flee()


func consume_planned_ability() -> EnemyAbility:
	var ability := planned_ability
	planned_ability = null
	return ability


func emit_combat_notice(enemy_index: int, text: String, kind: String = "ability") -> void:
	## Broadcast floating combat text for this fighter (UI listens on EventBus).
	if text.is_empty() or enemy_index < 0:
		return
	EventBus.enemy_combat_text.emit(enemy_index, text, kind)


func emit_ability_notice(enemy_index: int, ability: EnemyAbility, kind: String = "ability") -> void:
	if ability == null:
		return
	emit_combat_notice(enemy_index, ability.get_combat_notice_text(), kind)


func emit_crit_notice(enemy_index: int) -> void:
	emit_combat_notice(enemy_index, tr("KEY_COMBAT_TEXT_ENEMY_CRIT"), "crit")
