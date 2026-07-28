class_name EnemyAI
extends RefCounted
## Phased enemy decisioning: pre-action buffs, then priority multi-hit, then weighted deck.

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
	var result := {
		"ability": null,
	}
	if enemy == null or not enemy.is_alive():
		return result

	var desperate_ids: Array[String] = [ID_DESPERATE_ATTACK, ID_DESPERATE_ATTACK_SHORT]
	var desperate: EnemyAbility = enemy.find_ability_any(desperate_ids)
	if desperate != null and _can_use_desperate_attack(enemy, desperate):
		result["ability"] = desperate
		return result

	result["ability"] = enemy.choose_ability()
	return result


static func _can_use_desperate_attack(enemy: EnemyInstance, ability: EnemyAbility) -> bool:
	if enemy.is_ability_on_cooldown(ability):
		return false
	var threshold := ability.hp_threshold if ability.hp_threshold > 0.0 else DEFAULT_DESPERATE_HP_RATIO
	return enemy.get_hp_ratio() <= threshold
