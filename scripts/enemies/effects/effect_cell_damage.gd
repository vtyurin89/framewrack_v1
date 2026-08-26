class_name EffectCellDamage
extends AbilityEffect
## Applies unified CellDamage to the player's body grid.
## Params: DETONATE | STATUS|turns (e.g. OVERLOAD|2).


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if target == null or not target.has_method("apply_cell_damage"):
		return
	var csv := AbilityEffect.csv_params(params)
	var target_cell := Vector2i(-1, -1)
	var status_type := ItemStatus.Type.COOLDOWN
	var duration := 0

	if not csv.is_empty() and str(csv[0]).strip_edges().to_upper() == "DETONATE":
		if target.has_method("find_sticky_grenade_cell"):
			target_cell = target.call("find_sticky_grenade_cell")
		if target_cell == Vector2i(-1, -1):
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_GRENADE_NONE") % (
					caster.get_localized_name() if caster != null else "?"
				)
			)
			return
	else:
		if csv.size() >= 1:
			status_type = ItemStatus.parse_type_id(str(csv[0]))
		if csv.size() >= 2 and str(csv[1]).is_valid_int():
			duration = maxi(1, int(csv[1]))
		elif csv.size() >= 1:
			duration = 1

	target.call("apply_cell_damage", target_cell, status_type, duration)
	if duration > 0 and caster != null:
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_CELL_DAMAGE") % [
				caster.get_localized_name(),
				ItemStatus.TYPE_IDS.get(status_type, "STATUS"),
				duration,
			]
		)
