class_name EffectStealItem
extends AbilityEffect
## Stasis Pod Right: steals one consumable (else random non-harmful) from the Body Grid.


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null or target == null:
		return
	if caster.stolen_grid_item != null:
		return
	if not target.has_method("steal_item_from_player_grid"):
		return
	var stolen: ItemData = target.call("steal_item_from_player_grid", caster)
	if stolen == null:
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_POD_STEAL_FAIL") % caster.get_localized_name()
		)
		return
	caster.stolen_grid_item = stolen
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_POD_STEAL") % [caster.get_localized_name(), stolen.get_localized_name()]
	)
	var enemy_index := AbilityEffect.enemy_index_from_params(params)
	EventBus.item_stolen_by_enemy.emit(enemy_index, stolen)
