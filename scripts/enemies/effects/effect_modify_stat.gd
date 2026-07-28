class_name EffectModifyStat
extends AbilityEffect
## Permanently (or temporarily if duration>0) alters a caster/ally stat.
## CSV effect_params examples: "luck|+1", "lck|1", "strength|-1|3" (stat|delta|duration_turns).


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null:
		return
	var ability := AbilityEffect.ability_from_params(params)
	var csv := AbilityEffect.csv_params(params)
	var stat_key := "luck"
	var delta := 1
	var duration := 0
	if csv.size() >= 1 and str(csv[0]).strip_edges() != "":
		stat_key = str(csv[0]).strip_edges().to_lower()
	if csv.size() >= 2:
		delta = _parse_delta(str(csv[1]))
	elif ability != null and ability.max_val != 0:
		delta = ability.max_val
	if csv.size() >= 3 and str(csv[2]).is_valid_int():
		duration = int(csv[2])

	var subject := caster
	if ability != null and ability.target_type.strip_edges().to_lower() == "ally":
		if target != null and target.has_method("get_random_living_ally"):
			var ally: EnemyInstance = target.call("get_random_living_ally", caster)
			if ally != null:
				subject = ally

	_apply_stat(subject, stat_key, delta)
	if duration > 0 and subject.has_method("queue_temp_stat_modifier"):
		subject.call("queue_temp_stat_modifier", stat_key, -delta, duration)

	if ability != null and ability.id in ["ABILITY_ENEMY_STUDY", "enemy_study"]:
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_ENEMY_STUDY") % [
				subject.get_localized_name(),
				ability.get_combat_notice_text(),
				subject.luck,
			]
		)
	else:
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_ENEMY_STAT_MOD") % [
				subject.get_localized_name(),
				stat_key.to_upper(),
				delta,
				subject.get_stat(_stat_enum(stat_key)),
			]
		)


func _parse_delta(raw: String) -> int:
	var cleaned := raw.strip_edges()
	if cleaned.begins_with("+"):
		cleaned = cleaned.substr(1)
	if cleaned.is_valid_int():
		return int(cleaned)
	return 1


func _stat_enum(stat_key: String) -> EnemyAbility.StatScaling:
	return EnemyAbility.parse_stat_scaling(stat_key)


func _apply_stat(subject: EnemyInstance, stat_key: String, delta: int) -> void:
	match EnemyAbility.parse_stat_scaling(stat_key):
		EnemyAbility.StatScaling.STRENGTH:
			subject.strength = maxi(EnemyInstance.MIN_STAT, subject.strength + delta)
		EnemyAbility.StatScaling.AGILITY:
			subject.agility = maxi(EnemyInstance.MIN_STAT, subject.agility + delta)
		EnemyAbility.StatScaling.ENDURANCE:
			subject.endurance = maxi(EnemyInstance.MIN_STAT, subject.endurance + delta)
		EnemyAbility.StatScaling.INTELLIGENCE:
			subject.intelligence = maxi(EnemyInstance.MIN_STAT, subject.intelligence + delta)
		EnemyAbility.StatScaling.LUCK:
			subject.luck = maxi(EnemyInstance.MIN_STAT, subject.luck + delta)
		_:
			subject.luck = maxi(EnemyInstance.MIN_STAT, subject.luck + delta)
