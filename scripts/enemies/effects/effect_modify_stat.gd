class_name EffectModifyStat
extends AbilityEffect
## Stacking permanent (or temporary if duration>0) caster/ally stat buff.
## CSV: "luck|+1", "strength|+1|ABILITY_SCRAPPER_BUMPER" (stat|delta|followup_or_duration).
## Optional flat Block: "strength|+1|block|7".


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null:
		return
	var ability := AbilityEffect.ability_from_params(params)
	var enemy_index := AbilityEffect.enemy_index_from_params(params)
	var csv := AbilityEffect.csv_params(params)
	var stat_key := "luck"
	var delta := 1
	var duration := 0
	var followup_id := ""
	if csv.size() >= 1 and str(csv[0]).strip_edges() != "":
		stat_key = str(csv[0]).strip_edges().to_lower()
	if csv.size() >= 2:
		delta = _parse_delta(str(csv[1]))
	elif ability != null and ability.max_val != 0:
		delta = ability.max_val
	if csv.size() >= 3:
		var third := str(csv[2]).strip_edges()
		var third_l := third.to_lower()
		## Ignore hybrid block tokens — handled via parse_flat_block.
		if third_l not in ["block", "guard", "shield"]:
			if third.is_valid_int():
				duration = int(third)
			elif not third.is_empty():
				followup_id = third

	var subject := caster
	if ability != null and ability.target_type.strip_edges().to_lower() == "ally":
		if target != null and target.has_method("get_random_living_ally"):
			var ally: EnemyInstance = target.call("get_random_living_ally", caster)
			if ally != null:
				subject = ally

	var new_value := subject.apply_stackable_stat_buff(stat_key, delta)
	if duration > 0 and subject.has_method("queue_temp_stat_modifier"):
		subject.call("queue_temp_stat_modifier", stat_key, -delta, duration)

	if not followup_id.is_empty():
		caster.arm_prepared_ability(followup_id)

	var flat_block := AbilityEffect.parse_flat_block(ability)
	if flat_block > 0:
		if caster.roll_crit():
			flat_block = roundi(float(flat_block) * EnemyInstance.CRIT_DAMAGE_MULT)
			caster.emit_crit_notice(enemy_index)
		caster.gain_block(flat_block)
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_ENEMY_BLOCK") % [caster.get_localized_name(), flat_block]
		)
		if target != null and target.has_method("emit_enemy_block_for"):
			target.call("emit_enemy_block_for", caster)

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
				new_value,
			]
		)


func _parse_delta(raw: String) -> int:
	var cleaned := raw.strip_edges()
	if cleaned.begins_with("+"):
		cleaned = cleaned.substr(1)
	if cleaned.is_valid_int():
		return int(cleaned)
	return 1
