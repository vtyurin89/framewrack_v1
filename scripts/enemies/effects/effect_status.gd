class_name EffectStatus
extends AbilityEffect
## Applies a named status. Honors ability.target_type: player | self | ally | all_allies.


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null:
		return
	var ability := AbilityEffect.ability_from_params(params)
	var csv := AbilityEffect.csv_params(params)
	var potency_default := 1
	if csv.size() >= 2 and str(csv[1]).is_valid_int():
		potency_default = int(csv[1])
	elif ability != null:
		potency_default = ability.roll_base() + caster.get_stat(ability.stat_scaling)
	potency_default = maxi(1, potency_default)

	## Single-status shield shortcut (block/guard/shield).
	if csv.size() >= 1:
		var first_id := str(csv[0]).strip_edges().to_lower()
		if first_id in ["block", "guard", "shield"]:
			EffectShield.new().apply(caster, target, params)
			return

	var target_type := "player"
	if ability != null:
		target_type = ability.target_type.strip_edges().to_lower()

	match target_type:
		"self":
			_apply_multi_to_enemy(caster, csv, potency_default)
		"ally":
			if target != null and target.has_method("get_random_living_ally"):
				var ally: EnemyInstance = target.call("get_random_living_ally", caster)
				if ally != null:
					_apply_multi_to_enemy(ally, csv, potency_default)
		"all_allies":
			if target != null and target.get("enemies") is Array:
				for enemy: EnemyInstance in target.enemies:
					if enemy != null and enemy.is_alive() and enemy != caster:
						_apply_multi_to_enemy(enemy, csv, potency_default)
		_:
			## Default: player — supports panic|2|bleed|3 style multi-status params.
			_apply_multi_to_player(target, caster, csv, potency_default)


func _apply_multi_to_player(target: Node, caster: EnemyInstance, csv: Array, default_potency: int) -> void:
	var pairs := _parse_status_pairs(csv, default_potency)
	if pairs.is_empty():
		pairs.append({"id": "poison", "potency": maxi(1, default_potency)})
	for pair in pairs:
		var status_id: String = str(pair.get("id", "poison"))
		var potency: int = int(pair.get("potency", 1))
		if target != null and target.has_method("apply_player_status"):
			target.call("apply_player_status", status_id, potency)
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_ENEMY_STATUS") % [caster.get_localized_name(), status_id, potency]
			)


func _apply_multi_to_enemy(enemy: EnemyInstance, csv: Array, default_potency: int) -> void:
	var pairs := _parse_status_pairs(csv, default_potency)
	if pairs.is_empty():
		pairs.append({"id": "poison", "potency": maxi(1, default_potency)})
	for pair in pairs:
		_apply_to_enemy(enemy, str(pair.get("id", "poison")), int(pair.get("potency", 1)))


func _parse_status_pairs(csv: Array, default_potency: int) -> Array:
	var out: Array = []
	var i := 0
	while i < csv.size():
		var token := str(csv[i]).strip_edges().to_lower()
		if token.is_empty() or token.is_valid_int():
			i += 1
			continue
		var potency := maxi(1, default_potency)
		if i + 1 < csv.size() and str(csv[i + 1]).is_valid_int():
			potency = maxi(1, int(csv[i + 1]))
			i += 2
		else:
			i += 1
		out.append({"id": token, "potency": potency})
	return out


func _apply_to_enemy(enemy: EnemyInstance, status_id: String, potency: int) -> void:
	if enemy == null:
		return
	if enemy.statuses == null:
		enemy.statuses = StatusController.new()
	enemy.statuses.apply_status_by_id(status_id, potency)
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_ENEMY_STATUS") % [enemy.get_localized_name(), status_id, potency]
	)
