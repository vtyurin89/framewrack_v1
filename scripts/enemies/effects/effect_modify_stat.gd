class_name EffectModifyStat
extends AbilityEffect
## Stacking permanent (or temporary if duration>0) caster/ally stat buff.
## CSV examples:
##   luck|+1
##   strength|+1|ABILITY_SCRAPPER_BUMPER
##   strength|+1|intelligence|+1|ABILITY_SPECIMEN_NECROTIC
## Optional flat Block tokens: block|7 anywhere after the first stat pair.


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null:
		return
	var ability := AbilityEffect.ability_from_params(params)
	var enemy_index := AbilityEffect.enemy_index_from_params(params)
	var csv := AbilityEffect.csv_params(params)

	var subject := caster
	if ability != null and ability.target_type.strip_edges().to_lower() == "ally":
		if target != null and target.has_method("get_random_living_ally"):
			var ally: EnemyInstance = target.call("get_random_living_ally", caster)
			if ally != null:
				subject = ally

	var followup_id := ""
	var applied_any := false
	var i := 0
	## Fallback when CSV is empty: use ability max_val as strength delta.
	if csv.is_empty():
		var delta := 1
		if ability != null and ability.max_val != 0:
			delta = ability.max_val
		var new_value := subject.apply_stackable_stat_buff("strength", delta)
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_ENEMY_STAT_MOD") % [
				subject.get_localized_name(),
				"STRENGTH",
				delta,
				new_value,
			]
		)
		applied_any = true
	else:
		while i < csv.size():
			var token := str(csv[i]).strip_edges()
			var token_l := token.to_lower()
			if token.is_empty():
				i += 1
				continue
			if token_l in ["block", "guard", "shield"]:
				## Flat block handled via parse_flat_block below.
				if i + 1 < csv.size() and str(csv[i + 1]).is_valid_int():
					i += 2
				else:
					i += 1
				continue
			if _looks_like_stat(token_l):
				var delta := 1
				if i + 1 < csv.size():
					delta = _parse_delta(str(csv[i + 1]))
				var new_value := subject.apply_stackable_stat_buff(token_l, delta)
				var is_study := (
					ability != null and ability.id in ["ABILITY_ENEMY_STUDY", "enemy_study"]
				)
				if not is_study:
					EventBus.combat_log_message.emit(
						tr("KEY_LOG_ENEMY_STAT_MOD") % [
							subject.get_localized_name(),
							token_l.to_upper(),
							delta,
							new_value,
						]
					)
				applied_any = true
				i += 2
				continue
			## Ability id followup (e.g. ABILITY_SCRAPPER_BUMPER).
			if token.to_upper().begins_with("ABILITY_") or token.contains("_"):
				followup_id = token
				i += 1
				break
			## Legacy third-token duration int after a single pair — rare.
			if token.is_valid_int():
				var duration := int(token)
				if duration > 0 and subject.has_method("queue_temp_stat_modifier"):
					## Reverse last buff is not tracked here; ignore legacy duration.
					pass
				i += 1
				continue
			i += 1

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


func _looks_like_stat(token_l: String) -> bool:
	return token_l in [
		"strength", "str",
		"agility", "agi",
		"endurance", "end",
		"intelligence", "int",
		"luck", "lck",
		"humanity", "hum",
	]


func _parse_delta(raw: String) -> int:
	var cleaned := raw.strip_edges()
	if cleaned.begins_with("+"):
		cleaned = cleaned.substr(1)
	if cleaned.is_valid_int():
		return int(cleaned)
	return 1
