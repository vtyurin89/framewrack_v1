class_name EffectHeal
extends AbilityEffect
## Restores HP. target_type: self (default) | ally (random) | all_allies (self + living allies).


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null:
		return
	var ability := AbilityEffect.ability_from_params(params)
	var enemy_index := AbilityEffect.enemy_index_from_params(params)
	if ability == null:
		return

	var amount := ability.roll_base() + caster.get_stat(ability.stat_scaling)
	if caster.roll_crit():
		amount = int(round(float(amount) * EnemyInstance.CRIT_DAMAGE_MULT))
		caster.emit_crit_notice(enemy_index)
	amount = maxi(0, amount)

	var subjects: Array[EnemyInstance] = []
	match ability.target_type.strip_edges().to_lower():
		"ally":
			if target != null and target.has_method("get_random_living_ally"):
				var ally: EnemyInstance = target.call("get_random_living_ally", caster)
				if ally != null:
					subjects.append(ally)
			if subjects.is_empty():
				subjects.append(caster)
		"all_allies":
			subjects.append(caster)
			if target != null and target.get("enemies") is Array:
				for enemy: EnemyInstance in target.enemies:
					if enemy != null and enemy.is_alive() and enemy != caster:
						subjects.append(enemy)
		_:
			subjects.append(caster)

	for heal_target in subjects:
		var healed := heal_target.heal(amount)
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_ENEMY_HEAL") % [heal_target.get_localized_name(), healed]
		)
		if target != null and target.has_method("notify_enemy_healed"):
			target.call("notify_enemy_healed", heal_target, healed)
		elif target != null and target.has_method("emit_enemy_hp_for"):
			target.call("emit_enemy_hp_for", heal_target)
