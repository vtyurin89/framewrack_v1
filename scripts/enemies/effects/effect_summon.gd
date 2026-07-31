class_name EffectSummon
extends AbilityEffect
## Spawns additional enemy minions by enemy_id via CombatSummonHelper.
## CSV effect_params: "slaver_minion" or "slaver_minion|2" (id|max_count).
## Count summoned = max_count - currently living matching minions (at least 1 if room).


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null or target == null:
		return
	var csv := AbilityEffect.csv_params(params)
	var enemy_id := "scrap_drone"
	var max_alive := 2
	if csv.size() >= 1 and str(csv[0]).strip_edges() != "":
		enemy_id = str(csv[0]).strip_edges()
	if csv.size() >= 2 and str(csv[1]).is_valid_int():
		max_alive = maxi(1, int(csv[1]))

	var living_minions := 0
	if target.get("enemies") is Array:
		for enemy: EnemyInstance in target.enemies:
			if enemy == null or not enemy.is_alive():
				continue
			if enemy.data != null and enemy.data.id == enemy_id:
				living_minions += 1
			elif enemy.get_summoner() == caster:
				living_minions += 1

	var to_spawn := clampi(max_alive - living_minions, 1, max_alive)
	if living_minions >= max_alive:
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_ENEMY_SUMMON_FAIL") % [caster.get_localized_name(), enemy_id]
		)
		return

	var spawned_any := false
	for _i in to_spawn:
		if living_minions >= max_alive:
			break
		var spawned: EnemyInstance = CombatSummonHelper.spawn_enemy(target, enemy_id, caster)
		if spawned == null:
			continue
		spawned_any = true
		living_minions += 1
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_ENEMY_SUMMON") % [caster.get_localized_name(), spawned.get_localized_name()]
		)
	if not spawned_any:
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_ENEMY_SUMMON_FAIL") % [caster.get_localized_name(), enemy_id]
		)
