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

	var study_ids: Array[String] = [ID_ENEMY_STUDY, ID_ENEMY_STUDY_SHORT]
	var study: EnemyAbility = enemy.find_ability_any(study_ids)
	if study == null:
		return result

	var interval := study.trigger_interval if study.trigger_interval > 0 else DEFAULT_STUDY_INTERVAL
	if interval <= 0:
		return result
	if enemy.turns_taken % interval != 0:
		return result

	result["ability"] = study
	result["triggered"] = true
	return result


static func resolve_main_action(enemy: EnemyInstance) -> Dictionary:
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
				result["ability"] = desperate
				enemy.planned_ability = desperate
				return result
		result["ability"] = enemy.planned_ability
		return result

	return commit_main_action(enemy)


static func commit_main_action(enemy: EnemyInstance, force_reroll: bool = false) -> Dictionary:
	## Pick and store the next main action (used at player-turn intention planning).
	var result := {
		"ability": null,
	}
	if enemy == null or not enemy.is_alive():
		if enemy != null:
			enemy.planned_ability = null
		return result

	var desperate := _get_desperate_if_ready(enemy)
	if desperate != null:
		enemy.planned_ability = desperate
		result["ability"] = desperate
		return result

	if (
		not force_reroll
		and enemy.planned_ability != null
		and _is_ability_still_usable(enemy, enemy.planned_ability)
		and enemy.planned_ability.is_main_deck_ability()
	):
		result["ability"] = enemy.planned_ability
		return result

	enemy.planned_ability = enemy.choose_ability()
	result["ability"] = enemy.planned_ability
	return result


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
