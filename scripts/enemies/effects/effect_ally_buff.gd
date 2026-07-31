class_name EffectAllyBuff
extends AbilityEffect
## Permanent strength (or other) buff for self + all living allies.
## CSV: "strength|+2"


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null:
		return
	var csv := AbilityEffect.csv_params(params)
	var stat_key := "strength"
	var delta := 2
	if csv.size() >= 1 and str(csv[0]).strip_edges() != "":
		stat_key = str(csv[0]).strip_edges().to_lower()
	if csv.size() >= 2:
		var cleaned := str(csv[1]).strip_edges()
		if cleaned.begins_with("+"):
			cleaned = cleaned.substr(1)
		if cleaned.is_valid_int():
			delta = int(cleaned)

	var subjects: Array[EnemyInstance] = [caster]
	if target != null and target.get("enemies") is Array:
		for enemy: EnemyInstance in target.enemies:
			if enemy != null and enemy.is_alive() and enemy != caster:
				subjects.append(enemy)

	for subject in subjects:
		_apply_stat(subject, stat_key, delta)
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_ENEMY_STAT_MOD") % [
				subject.get_localized_name(),
				stat_key.to_upper(),
				delta,
				subject.get_stat(EnemyAbility.parse_stat_scaling(stat_key)),
			]
		)


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
			subject.strength = maxi(EnemyInstance.MIN_STAT, subject.strength + delta)
