class_name EffectBrandStimulation
extends AbilityEffect
## Slaver Master: deals fixed damage to living summoned minions and grants Frenzy.


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null or target == null:
		return
	var csv := AbilityEffect.csv_params(params)
	var dmg := 3
	if csv.size() >= 1 and str(csv[0]).is_valid_int():
		dmg = maxi(1, int(csv[0]))

	var hit_any := false
	if target.get("enemies") is Array:
		for enemy: EnemyInstance in target.enemies:
			if enemy == null or not enemy.is_alive() or enemy == caster:
				continue
			if enemy.get_summoner() != caster and not enemy.is_summoned_creature():
				continue
			enemy.apply_incoming_damage(dmg)
			if enemy.statuses == null:
				enemy.statuses = StatusController.new()
			if enemy.is_alive():
				enemy.statuses.apply_status_by_id("frenzy", 1)
			hit_any = true
			if target.has_method("emit_enemy_hp_for"):
				target.call("emit_enemy_hp_for", enemy)
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_BRAND_STIM") % [enemy.get_localized_name(), dmg]
			)
			if not enemy.is_alive() and target.get("enemies") is Array:
				var idx: int = target.enemies.find(enemy)
				if idx >= 0:
					enemy.clear_intention()
					EventBus.enemy_intention_changed.emit(idx, enemy.current_intention)
					if target.has_method("_on_enemy_defeated"):
						target.call("_on_enemy_defeated", enemy, idx)
					EventBus.enemy_died.emit(idx)
	if not hit_any:
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_BRAND_STIM_FAIL") % caster.get_localized_name()
		)
