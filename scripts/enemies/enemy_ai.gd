class_name EnemyAI
extends RefCounted
## Phased enemy decisioning: pre-action buffs, then priority multi-hit, then weighted deck.

const ID_ENEMY_STUDY := "ABILITY_ENEMY_STUDY"
const ID_DESPERATE_ATTACK := "ABILITY_DESPERATE_ATTACK"
const DEFAULT_STUDY_INTERVAL := 2
const DEFAULT_DESPERATE_HP_RATIO := 0.40
const DEFAULT_DESPERATE_HITS := 3
const DEFAULT_DESPERATE_COOLDOWN := 1


static func trigger_pre_action_phase(enemy: EnemyInstance) -> Dictionary:
	## Runs at the start of an enemy's turn, before main ability selection.
	## Returns { logs: Array[String], ability: EnemyAbility|null, triggered: bool }.
	var logs: Array[String] = []
	var result := {
		"logs": logs,
		"ability": null,
		"triggered": false,
	}
	if enemy == null or not enemy.is_alive():
		return result

	enemy.begin_enemy_turn()

	var study: EnemyAbility = enemy.find_ability(ID_ENEMY_STUDY)
	if study == null:
		return result

	var interval := study.trigger_interval if study.trigger_interval > 0 else DEFAULT_STUDY_INTERVAL
	if interval <= 0:
		return result
	if enemy.turns_taken % interval != 0:
		return result

	enemy.luck += 1
	logs.append(
		TranslationServer.translate("KEY_LOG_ENEMY_STUDY") % [
			enemy.get_localized_name(),
			study.get_localized_name(),
			enemy.luck,
		]
	)
	result["logs"] = logs
	result["ability"] = study
	result["triggered"] = true
	return result


static func resolve_main_action(enemy: EnemyInstance) -> Dictionary:
	## Returns:
	## { mode: "multi_hit"|"ability"|"fallback", ability: EnemyAbility|null, hits: Array[int], resolved: Dictionary }
	var result := {
		"mode": "fallback",
		"ability": null,
		"hits": [],
		"resolved": {},
	}
	if enemy == null or not enemy.is_alive():
		return result

	var desperate: EnemyAbility = enemy.find_ability(ID_DESPERATE_ATTACK)
	if desperate != null and _can_use_desperate_attack(enemy, desperate):
		var hit_count := desperate.hit_count if desperate.hit_count > 0 else DEFAULT_DESPERATE_HITS
		var hits: Array[int] = enemy.resolve_multi_hit_base_rolls(desperate, hit_count)
		enemy.start_ability_cooldown(
			desperate,
			desperate.cooldown_turns if desperate.cooldown_turns > 0 else DEFAULT_DESPERATE_COOLDOWN
		)
		result["mode"] = "multi_hit"
		result["ability"] = desperate
		result["hits"] = hits
		return result

	var ability: EnemyAbility = enemy.choose_ability()
	if ability != null:
		result["mode"] = "ability"
		result["ability"] = ability
		result["resolved"] = enemy.resolve_ability(ability)
		return result

	result["mode"] = "fallback"
	return result


static func _can_use_desperate_attack(enemy: EnemyInstance, ability: EnemyAbility) -> bool:
	if enemy.is_ability_on_cooldown(ability):
		return false
	var threshold := ability.hp_threshold if ability.hp_threshold > 0.0 else DEFAULT_DESPERATE_HP_RATIO
	return enemy.get_hp_ratio() <= threshold
