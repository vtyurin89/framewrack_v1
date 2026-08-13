class_name EffectDamage
extends AbilityEffect
## Deals one or more damage rolls. STR for physical, INT for spells; luck may crit.


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null or target == null or not target.has_method("apply_enemy_damage_to_player"):
		return
	var ability := AbilityEffect.ability_from_params(params)
	var enemy_index := AbilityEffect.enemy_index_from_params(params)
	if ability == null:
		return

	var hits := maxi(1, ability.hit_count)
	## Physical → Strength; spell → Intelligence (via scaling_stat / half-STR multi-hit).
	var stat_bonus := EnemyAbilityExecutor.resolve_damage_stat_bonus(caster, ability)
	for _i in hits:
		var base_roll := ability.roll_base()
		var amount := base_roll + stat_bonus
		var is_crit := caster.roll_crit()
		var crit_mult := EnemyInstance.CRIT_DAMAGE_MULT
		if caster.statuses != null:
			crit_mult = caster.statuses.get_crit_damage_multiplier(crit_mult)
			amount = caster.statuses.modify_outgoing_damage(amount)
		if is_crit:
			amount = roundi(float(amount) * crit_mult)
		if GameSettings != null:
			amount = roundi(float(amount) * GameSettings.get_enemy_damage_multiplier())
		amount = maxi(0, amount)

		var dealt: int = target.call("apply_enemy_damage_to_player", amount, caster, "physical")
		if is_crit:
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_ENEMY_CRIT_HIT") % [caster.get_localized_name(), amount]
			)
			caster.emit_crit_notice(enemy_index)
		else:
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_ENEMY_STRIKE") % [caster.get_localized_name(), amount, dealt]
			)

		if target.has_method("is_player_defeated") and bool(target.call("is_player_defeated")):
			return

	_apply_status_riders(caster, target, ability)

	if caster.statuses != null:
		caster.statuses.consume_frenzy_after_attack()


func _apply_status_riders(caster: EnemyInstance, target: Node, ability: EnemyAbility) -> void:
	if ability == null or target == null:
		return
	var csv := ability.get_effect_param_list()
	## Whitelist known status riders so numeric / misc params are ignored.
	var known := [
		"slow", "bleed", "burn", "poison", "weakness", "vulnerability", "rust", "stun",
		"panic", "healing_curse", "sensor_glitch",
	]
	var i := 0
	while i < csv.size():
		var token := str(csv[i]).strip_edges().to_lower()
		if token.is_empty() or token.is_valid_int():
			i += 1
			continue
		if token not in known:
			i += 1
			continue
		var stacks := 1
		if i + 1 < csv.size() and str(csv[i + 1]).is_valid_int():
			stacks = maxi(1, int(csv[i + 1]))
			i += 2
		else:
			i += 1
		if target.has_method("apply_player_status"):
			target.call("apply_player_status", token, stacks)
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_ENEMY_STATUS") % [caster.get_localized_name(), token, stacks]
			)
