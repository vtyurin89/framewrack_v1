class_name EffectSummon
extends AbilityEffect
## Spawns an additional enemy minion by enemy_id via EncounterManager.
## CSV effect_params: "scrap_drone" (enemy catalog id).


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null or target == null:
		return
	var csv := AbilityEffect.csv_params(params)
	var enemy_id := "scrap_drone"
	if csv.size() >= 1 and str(csv[0]).strip_edges() != "":
		enemy_id = str(csv[0]).strip_edges()

	var spawned: EnemyInstance = EncounterManager.spawn_enemy(target, enemy_id)
	if spawned == null:
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_ENEMY_SUMMON_FAIL") % [caster.get_localized_name(), enemy_id]
		)
		return
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_ENEMY_SUMMON") % [caster.get_localized_name(), spawned.get_localized_name()]
	)
