class_name EffectStatus
extends AbilityEffect
## Applies a named status. Honors ability.target_type: player | self | ally | all_allies.


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null:
		return
	var ability := AbilityEffect.ability_from_params(params)
	var csv := AbilityEffect.csv_params(params)
	var status_id := "poison"
	var potency := 1
	if csv.size() >= 1 and str(csv[0]).strip_edges() != "":
		status_id = str(csv[0]).strip_edges().to_lower()
	if csv.size() >= 2 and str(csv[1]).is_valid_int():
		potency = int(csv[1])
	elif ability != null:
		potency = ability.roll_base() + caster.get_stat(ability.stat_scaling)
	potency = maxi(1, potency)

	## Defensive leftovers still route to shield formula.
	if status_id in ["block", "guard", "shield"]:
		EffectShield.new().apply(caster, target, params)
		return

	var target_type := "player"
	if ability != null:
		target_type = ability.target_type.strip_edges().to_lower()

	match target_type:
		"self":
			_apply_to_enemy(caster, status_id, potency)
		"ally":
			if target != null and target.has_method("get_random_living_ally"):
				var ally: EnemyInstance = target.call("get_random_living_ally", caster)
				if ally != null:
					_apply_to_enemy(ally, status_id, potency)
		"all_allies":
			if target != null and target.get("enemies") is Array:
				for enemy: EnemyInstance in target.enemies:
					if enemy != null and enemy.is_alive() and enemy != caster:
						_apply_to_enemy(enemy, status_id, potency)
		_:
			## Default: player.
			if target != null and target.has_method("apply_player_status"):
				target.call("apply_player_status", status_id, potency)
				EventBus.combat_log_message.emit(
					tr("KEY_LOG_ENEMY_STATUS") % [caster.get_localized_name(), status_id, potency]
				)
			else:
				EventBus.combat_log_message.emit(
					tr("KEY_LOG_ENEMY_STATUS") % [caster.get_localized_name(), status_id, potency]
				)


func _apply_to_enemy(enemy: EnemyInstance, status_id: String, potency: int) -> void:
	if enemy == null:
		return
	if enemy.statuses == null:
		enemy.statuses = StatusController.new()
	enemy.statuses.apply_status_by_id(status_id, potency)
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_ENEMY_STATUS") % [enemy.get_localized_name(), status_id, potency]
	)
