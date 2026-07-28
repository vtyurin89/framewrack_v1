class_name EffectStatus
extends AbilityEffect
## Applies a named status / defensive buff.
## CSV effect_params examples: "block", "poison|2", "burn|3".


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null:
		return
	var ability := AbilityEffect.ability_from_params(params)
	var enemy_index := AbilityEffect.enemy_index_from_params(params)
	var csv := AbilityEffect.csv_params(params)
	var status_id := "block"
	var potency := 1
	if csv.size() >= 1 and str(csv[0]).strip_edges() != "":
		status_id = str(csv[0]).strip_edges().to_lower()
	if csv.size() >= 2 and str(csv[1]).is_valid_int():
		potency = int(csv[1])
	elif ability != null:
		potency = ability.roll_base() + caster.get_stat(ability.stat_scaling)

	match status_id:
		"block", "guard", "shield":
			if caster.roll_crit():
				potency = int(round(float(potency) * EnemyInstance.CRIT_DAMAGE_MULT))
				caster.emit_crit_notice(enemy_index)
			caster.gain_block(maxi(0, potency))
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_ENEMY_BLOCK") % [caster.get_localized_name(), potency]
			)
			if target != null and target.has_method("emit_enemy_hp_for"):
				target.call("emit_enemy_hp_for", caster)
		"poison", "burn", "rust":
			if target != null and target.has_method("apply_player_status"):
				target.call("apply_player_status", status_id, maxi(1, potency))
				EventBus.combat_log_message.emit(
					tr("KEY_LOG_ENEMY_STATUS") % [caster.get_localized_name(), status_id, potency]
				)
		_:
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_ENEMY_STATUS") % [caster.get_localized_name(), status_id, potency]
			)
