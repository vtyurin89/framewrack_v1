class_name EffectAllyBuff
extends AbilityEffect
## Permanent stacking stat buff for self + all living allies.
## CSV: "strength|+2" (fixed) or "strength|INTELLIGENCE" (caster's scaling stat).


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null:
		return
	var csv := AbilityEffect.csv_params(params)
	var ability := AbilityEffect.ability_from_params(params)
	var stat_key := "strength"
	var delta := 2
	if csv.size() >= 1 and str(csv[0]).strip_edges() != "":
		stat_key = str(csv[0]).strip_edges().to_lower()
	if csv.size() >= 2:
		delta = _resolve_delta(caster, ability, str(csv[1]))
	elif ability != null and ability.stat_scaling != EnemyAbility.StatScaling.NONE:
		delta = maxi(1, caster.get_stat(ability.stat_scaling))

	var subjects: Array[EnemyInstance] = [caster]
	if target != null and target.get("enemies") is Array:
		for enemy: EnemyInstance in target.enemies:
			if enemy != null and enemy.is_alive() and enemy != caster:
				subjects.append(enemy)

	for subject in subjects:
		var new_value := subject.apply_stackable_stat_buff(stat_key, delta)
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_ENEMY_STAT_MOD") % [
				subject.get_localized_name(),
				stat_key.to_upper(),
				delta,
				new_value,
			]
		)


func _resolve_delta(caster: EnemyInstance, ability: EnemyAbility, raw: String) -> int:
	var cleaned := raw.strip_edges()
	if cleaned.begins_with("+"):
		cleaned = cleaned.substr(1)
	if cleaned.is_valid_int():
		return int(cleaned)
	var scaling := EnemyAbility.parse_stat_scaling(cleaned)
	if scaling != EnemyAbility.StatScaling.NONE:
		return maxi(1, caster.get_stat(scaling))
	if ability != null and ability.stat_scaling != EnemyAbility.StatScaling.NONE:
		return maxi(1, caster.get_stat(ability.stat_scaling))
	return 2
