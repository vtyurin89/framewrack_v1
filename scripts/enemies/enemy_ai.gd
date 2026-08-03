class_name EnemyAI
extends RefCounted
## Phased enemy decisioning: pre-action buffs, then priority multi-hit, then weighted deck.
## Also commits a planned main action for StS-style intention telegraphs.

const ID_ENEMY_STUDY := "ABILITY_ENEMY_STUDY"
const ID_ENEMY_STUDY_SHORT := "enemy_study"
const ID_DESPERATE_ATTACK := "ABILITY_DESPERATE_ATTACK"
const ID_DESPERATE_ATTACK_SHORT := "desperate_attack"
const DEFAULT_STUDY_INTERVAL := 2
const DEFAULT_DESPERATE_HP_RATIO := 0.40

const ID_SLAVER_SUMMON := "ABILITY_SLAVER_SUMMON"
const ID_SLAVER_BRAND := "ABILITY_SLAVER_BRAND"
const ID_DESERTER_AIM := "ABILITY_DESERTER_AIM"
const ID_DESERTER_SNIPE := "ABILITY_DESERTER_SNIPE"
const ID_DESERTER_EVASION := "ABILITY_DESERTER_EVASION"
const ID_DESERTER_SHIELD := "ABILITY_DESERTER_SHIELD"
const ID_THIEF_STEAL := "ABILITY_THIEF_STEAL"
const ID_THIEF_STAB := "ABILITY_THIEF_STAB"
const ID_THIEF_SCOUT := "ABILITY_THIEF_SCOUT"
const ID_THIEF_FLEE := "ABILITY_THIEF_FLEE"
const ID_SCRAPPER_SHIELD := "ABILITY_SCRAPPER_SHIELD"
const ID_SCRAPPER_BUMPER := "ABILITY_SCRAPPER_BUMPER"
const ID_SCRAPPER_EXHAUST := "ABILITY_SCRAPPER_EXHAUST"


static func trigger_pre_action_phase(enemy: EnemyInstance) -> Dictionary:
	## Runs at the start of an enemy's turn, before main ability selection.
	## Returns { ability: EnemyAbility|null, triggered: bool } — CombatManager applies via executor.
	var result := {
		"ability": null,
		"triggered": false,
	}
	if enemy == null or not enemy.is_alive():
		return result

	enemy.begin_enemy_turn()

	var pre: EnemyAbility = _pick_ready_pre_action(enemy)
	if pre == null:
		return result

	result["ability"] = pre
	result["triggered"] = true
	return result


static func resolve_main_action(enemy: EnemyInstance, combat: Node = null) -> Dictionary:
	## Returns { ability: EnemyAbility|null } for EnemyAbilityExecutor.
	## Prefers a previously committed plan so the telegraph matches execution.
	var result := {
		"ability": null,
	}
	if enemy == null or not enemy.is_alive():
		return result

	if enemy.planned_ability != null and _is_ability_still_usable(enemy, enemy.planned_ability):
		## Desperate may override a deck pick if HP dropped after planning.
		var desperate := _get_desperate_if_ready(enemy)
		if desperate != null and enemy.planned_ability != desperate:
			if enemy.planned_ability.type != EnemyAbility.AbilityType.MULTI_HIT:
				if _can_commit_offensive(combat, desperate):
					result["ability"] = desperate
					enemy.planned_ability = desperate
					return result
		## Scripted overrides that must win even over a prior plan.
		var forced := _pick_scripted_main(enemy, combat)
		if forced != null and forced != enemy.planned_ability:
			## Aim→snipe and flee prep must not be blocked by stale plans.
			if forced.id in [
				ID_DESERTER_SNIPE, ID_THIEF_SCOUT, ID_THIEF_FLEE, ID_SLAVER_SUMMON,
				FacelessLady.ID_INJECT,
			]:
				if is_offensive_ability(forced) and not _can_commit_offensive(combat, forced):
					var alt := _pick_non_offensive(enemy)
					if alt != null:
						enemy.planned_ability = alt
						result["ability"] = alt
						return result
				enemy.planned_ability = forced
				result["ability"] = forced
				return result
		## Planned offensive still consumes a slot on the act phase.
		if is_offensive_ability(enemy.planned_ability):
			if not _can_commit_offensive(combat, enemy.planned_ability):
				var defensive := _pick_non_offensive(enemy)
				if defensive != null:
					enemy.planned_ability = defensive
					result["ability"] = defensive
					return result
		result["ability"] = enemy.planned_ability
		return result

	return commit_main_action(enemy, false, combat)


static func commit_main_action(
	enemy: EnemyInstance, force_reroll: bool = false, combat: Node = null
) -> Dictionary:
	## Pick and store the next main action (used at player-turn intention planning).
	var result := {
		"ability": null,
	}
	if enemy == null or not enemy.is_alive():
		if enemy != null:
			enemy.planned_ability = null
		return result

	var desperate := _get_desperate_if_ready(enemy)
	if desperate != null and _can_commit_offensive(combat, desperate):
		enemy.planned_ability = desperate
		result["ability"] = desperate
		return result

	var scripted := _pick_scripted_main(enemy, combat)
	if scripted != null:
		if is_offensive_ability(scripted) and not _can_commit_offensive(combat, scripted):
			scripted = _pick_non_offensive(enemy)
		if scripted != null:
			enemy.planned_ability = scripted
			result["ability"] = scripted
			return result

	if (
		not force_reroll
		and enemy.planned_ability != null
		and _is_ability_still_usable(enemy, enemy.planned_ability)
		and enemy.planned_ability.is_main_deck_ability()
	):
		## Keep plan only if it still fits the group attack cap.
		if (
			not is_offensive_ability(enemy.planned_ability)
			or _can_commit_offensive(combat, enemy.planned_ability)
		):
			result["ability"] = enemy.planned_ability
			return result

	var picked := _choose_weighted(enemy, combat)
	if is_offensive_ability(picked) and not _can_commit_offensive(combat, picked):
		picked = _pick_non_offensive(enemy)
	enemy.planned_ability = picked
	result["ability"] = picked
	return result


static func is_offensive_ability(ability: EnemyAbility) -> bool:
	if ability == null:
		return false
	if ability.type == EnemyAbility.AbilityType.MULTI_HIT:
		return true
	var effect := ability.infer_main_effect()
	return effect in ["damage", "steal_chips"]


static func _can_commit_offensive(combat: Node, ability: EnemyAbility) -> bool:
	if not is_offensive_ability(ability):
		return true
	if combat == null:
		return true
	if combat.has_method("try_reserve_attacker_slot"):
		return bool(combat.call("try_reserve_attacker_slot"))
	return true


static func _pick_non_offensive(enemy: EnemyInstance) -> EnemyAbility:
	## Prefer shield / status-self / heal when the group attack cap is full.
	var preferred: Array[EnemyAbility] = []
	var fallback: Array[EnemyAbility] = []
	for ability: EnemyAbility in enemy.abilities:
		if ability == null or not ability.is_main_deck_ability():
			continue
		if enemy.is_ability_on_cooldown(ability):
			continue
		if is_offensive_ability(ability):
			continue
		var effect := ability.infer_main_effect()
		if effect in ["shield", "heal", "status", "summon", "ally_buff", "brand_stim", "flee"]:
			preferred.append(ability)
		else:
			fallback.append(ability)
	if not preferred.is_empty():
		return preferred[randi() % preferred.size()]
	if not fallback.is_empty():
		return fallback[randi() % fallback.size()]
	return null


static func _pick_ready_pre_action(enemy: EnemyInstance) -> EnemyAbility:
	var candidates: Array[EnemyAbility] = []
	for ability: EnemyAbility in enemy.abilities:
		if ability == null or ability.type != EnemyAbility.AbilityType.PRE_ACTION:
			continue
		if enemy.is_ability_on_cooldown(ability):
			continue
		var interval := ability.trigger_interval if ability.trigger_interval > 0 else DEFAULT_STUDY_INTERVAL
		if interval <= 0:
			continue
		if enemy.turns_taken % interval != 0:
			continue
		candidates.append(ability)
	if candidates.is_empty():
		return null
	## Prefer non-study buffs when several are ready (stimulants / pre-buff).
	for ability in candidates:
		if ability.id != ID_ENEMY_STUDY and ability.id != ID_ENEMY_STUDY_SHORT:
			return ability
	return candidates[0]


static func _pick_scripted_main(enemy: EnemyInstance, combat: Node) -> EnemyAbility:
	var enemy_id := enemy.data.id if enemy.data != null else ""

	match enemy_id:
		"slaver_master":
			return _ai_slaver_master(enemy, combat)
		"corp_deserter":
			return _ai_corp_deserter(enemy, combat)
		"pocket_thief":
			return _ai_pocket_thief(enemy, combat)
		"scrapper_tank":
			return _ai_scrapper_tank(enemy, combat)
		"faceless_lady":
			return FacelessLady.pick_scripted_ability(enemy, combat)
		_:
			return null


static func _ai_slaver_master(enemy: EnemyInstance, combat: Node) -> EnemyAbility:
	var living_minions := _count_living_minions(combat, enemy, "slaver_minion")
	if living_minions < 2:
		var summon := enemy.find_ability(ID_SLAVER_SUMMON)
		if summon != null and not enemy.is_ability_on_cooldown(summon):
			return summon
	if living_minions > 0:
		var brand := enemy.find_ability(ID_SLAVER_BRAND)
		if brand != null and not enemy.is_ability_on_cooldown(brand) and randf() < 0.45:
			return brand
	return null


static func _ai_corp_deserter(enemy: EnemyInstance, combat: Node) -> EnemyAbility:
	var player_vuln := _player_has_status(combat, "vulnerability")
	## Aim → Snipe lock: while the mark is fresh (first snipe window), always shoot.
	if player_vuln and enemy.turns_taken <= 1:
		var snipe := enemy.find_ability(ID_DESERTER_SNIPE)
		if snipe != null and not enemy.is_ability_on_cooldown(snipe):
			return snipe

	## First act: always aim.
	if enemy.turns_taken <= 0:
		var aim := enemy.find_ability(ID_DESERTER_AIM)
		if aim != null and not enemy.is_ability_on_cooldown(aim):
			return aim

	## After the snipe window, low HP prefers defense.
	if enemy.get_hp_ratio() < 0.5 and enemy.turns_taken >= 2 and randf() < 0.75:
		var defense := _pick_first_usable(enemy, [ID_DESERTER_SHIELD, ID_DESERTER_EVASION])
		if defense != null:
			return defense
	return null


static func _ai_pocket_thief(enemy: EnemyInstance, combat: Node) -> EnemyAbility:
	## turns_taken is the count of turns already started. Planning before turn N means
	## turns_taken == N-1. Turn 3 = scout (fleeing). Turn 4+ = flee ability fallback.
	if enemy.statuses != null and enemy.statuses.has_status("fleeing"):
		var flee := enemy.find_ability(ID_THIEF_FLEE)
		if flee != null:
			return flee

	if enemy.turns_taken == 2:
		var scout := enemy.find_ability(ID_THIEF_SCOUT)
		if scout != null and not enemy.is_ability_on_cooldown(scout):
			return scout

	if enemy.turns_taken >= 3:
		var flee2 := enemy.find_ability(ID_THIEF_FLEE)
		if flee2 != null:
			return flee2

	var chips := _player_chip_count(combat)
	if chips <= 0:
		var stab := enemy.find_ability(ID_THIEF_STAB)
		if stab != null and not enemy.is_ability_on_cooldown(stab):
			return stab
	else:
		var steal := enemy.find_ability(ID_THIEF_STEAL)
		if steal != null and not enemy.is_ability_on_cooldown(steal):
			return steal
	return null


static func _ai_scrapper_tank(enemy: EnemyInstance, combat: Node) -> EnemyAbility:
	var allies := _count_living_allies(combat, enemy)
	if allies <= 0:
		## Alone: stay aggressive — bumper / exhaust, almost never shield.
		if randf() < 0.85:
			var bumper := enemy.find_ability(ID_SCRAPPER_BUMPER)
			if bumper != null and not enemy.is_ability_on_cooldown(bumper):
				return bumper
			var exhaust := enemy.find_ability(ID_SCRAPPER_EXHAUST)
			if exhaust != null and not enemy.is_ability_on_cooldown(exhaust):
				return exhaust
		return null
	return null


static func _choose_weighted(enemy: EnemyInstance, combat: Node) -> EnemyAbility:
	var deck: Array[EnemyAbility] = []
	var weights: Array[float] = []
	var total := 0.0
	var alone := _count_living_allies(combat, enemy) <= 0
	var enemy_id := enemy.data.id if enemy.data != null else ""

	for ability: EnemyAbility in enemy.abilities:
		if ability == null or not ability.is_main_deck_ability():
			continue
		if enemy.is_ability_on_cooldown(ability):
			continue
		var w := ability.base_ai_weight
		if GameSettings != null:
			w *= GameSettings.get_ability_weight_multiplier(int(ability.weight_class))

		## Scrapper alone: heavily downrank shield.
		if alone and enemy_id == "scrapper_tank" and ability.id == ID_SCRAPPER_SHIELD:
			w *= 0.15
		## Deserter low HP: prefer defense in the weighted pool too.
		if enemy_id == "corp_deserter" and enemy.get_hp_ratio() < 0.5:
			if ability.id in [ID_DESERTER_SHIELD, ID_DESERTER_EVASION]:
				w *= 2.5
			elif ability.main_effect == "damage":
				w *= 0.45

		w = maxf(0.01, w)
		deck.append(ability)
		weights.append(w)
		total += w

	if deck.is_empty():
		return null
	var roll := randf() * total
	var cursor := 0.0
	for i in deck.size():
		cursor += weights[i]
		if roll <= cursor:
			return deck[i]
	return deck[deck.size() - 1]


static func _get_desperate_if_ready(enemy: EnemyInstance) -> EnemyAbility:
	var desperate_ids: Array[String] = [ID_DESPERATE_ATTACK, ID_DESPERATE_ATTACK_SHORT]
	var desperate: EnemyAbility = enemy.find_ability_any(desperate_ids)
	if desperate != null and _can_use_desperate_attack(enemy, desperate):
		return desperate
	return null


static func _is_ability_still_usable(enemy: EnemyInstance, ability: EnemyAbility) -> bool:
	if ability == null:
		return false
	if enemy.find_ability(ability.id) == null:
		return false
	if enemy.is_ability_on_cooldown(ability):
		return false
	if ability.type == EnemyAbility.AbilityType.MULTI_HIT:
		return _can_use_desperate_attack(enemy, ability)
	return true


static func _can_use_desperate_attack(enemy: EnemyInstance, ability: EnemyAbility) -> bool:
	if enemy.is_ability_on_cooldown(ability):
		return false
	var threshold := ability.hp_threshold if ability.hp_threshold > 0.0 else DEFAULT_DESPERATE_HP_RATIO
	return enemy.get_hp_ratio() <= threshold


static func _pick_first_usable(enemy: EnemyInstance, ids: Array) -> EnemyAbility:
	for id_variant in ids:
		var ability := enemy.find_ability(str(id_variant))
		if ability != null and not enemy.is_ability_on_cooldown(ability):
			return ability
	return null


static func _count_living_minions(combat: Node, master: EnemyInstance, minion_id: String) -> int:
	if combat == null or not (combat.get("enemies") is Array):
		return 0
	var count := 0
	for enemy: EnemyInstance in combat.enemies:
		if enemy == null or not enemy.is_alive() or enemy == master:
			continue
		if enemy.get_summoner() == master:
			count += 1
		elif enemy.data != null and enemy.data.id == minion_id:
			count += 1
	return count


static func _count_living_allies(combat: Node, self_enemy: EnemyInstance) -> int:
	if combat == null or not (combat.get("enemies") is Array):
		return 0
	var count := 0
	for enemy: EnemyInstance in combat.enemies:
		if enemy != null and enemy.is_alive() and enemy != self_enemy:
			count += 1
	return count


static func _player_has_status(combat: Node, status_id: String) -> bool:
	if combat == null:
		return false
	var statuses = combat.get("player_statuses")
	if statuses == null:
		return false
	if statuses.has_method("has_status"):
		return bool(statuses.has_status(status_id))
	return false


static func _player_chip_count(combat: Node) -> int:
	if combat == null:
		return 0
	var inventory = combat.get("inventory")
	return NeuroChipItem.count_in_inventory(inventory as InventoryController)
