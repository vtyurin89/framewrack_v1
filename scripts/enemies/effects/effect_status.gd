class_name EffectStatus
extends AbilityEffect
## Applies a named status / debuff to the player.
## Block / guard / shield rows should use EffectShield (executor remaps them).


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

	## Defensive leftovers still route to shield formula.
	if status_id in ["block", "guard", "shield"]:
		EffectShield.new().apply(caster, target, params)
		return

	match status_id:
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
