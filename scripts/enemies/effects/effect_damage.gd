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
		if is_crit:
			amount = roundi(float(amount) * EnemyInstance.CRIT_DAMAGE_MULT)
		if GameSettings != null:
			amount = roundi(float(amount) * GameSettings.get_enemy_damage_multiplier())
		amount = maxi(0, amount)

		var dealt: int = target.call("apply_enemy_damage_to_player", amount)
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
