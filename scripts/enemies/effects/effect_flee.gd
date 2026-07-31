class_name EffectFlee
extends AbilityEffect
## Marks the caster as escaped (HP 0 + death signal). Keeps stolen chips (no refund).


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null:
		return
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_ENEMY_FLED") % [
			caster.get_localized_name(),
			maxi(caster.stolen_chips, 0),
		]
	)
	## Successful escape: chips stay with the thief (death-hook must not refund).
	caster.stolen_chips = 0
	if caster.statuses != null:
		caster.statuses.clear_combat_statuses()
	caster.current_hp = 0
	caster.clear_intention()
	if target != null and target.get("enemies") is Array:
		var idx: int = target.enemies.find(caster)
		if idx >= 0:
			EventBus.enemy_intention_changed.emit(idx, caster.current_intention)
			EventBus.enemy_died.emit(idx)
			if target.has_method("_ensure_valid_selection"):
				target.call("_ensure_valid_selection")
