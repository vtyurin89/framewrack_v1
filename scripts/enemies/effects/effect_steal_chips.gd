class_name EffectStealChips
extends AbilityEffect
## Pocket Thief: minor damage + steal Neuro-Chips (intellect * multiplier).
## If player has 0 chips, deals normal damage and applies bleed instead.


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null or target == null:
		return
	var ability := AbilityEffect.ability_from_params(params)
	var csv := AbilityEffect.csv_params(params)
	var chip_mult := 4
	if csv.size() >= 1 and str(csv[0]).is_valid_int():
		chip_mult = maxi(1, int(csv[0]))

	var available: int = 0
	if GameManager != null:
		available = GameManager.get_chips()
	if available <= 0:
		## Fallback stab + bleed.
		EffectDamage.new().apply(caster, target, params)
		if target.has_method("apply_player_status"):
			target.call("apply_player_status", "bleed", 1)
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_ENEMY_STATUS") % [caster.get_localized_name(), "bleed", 1]
			)
		return

	var steal_amount := maxi(1, caster.intelligence * chip_mult)
	steal_amount = mini(steal_amount, available)
	var stolen: int = 0
	if GameManager != null:
		stolen = GameManager.take_chips(steal_amount)
	caster.stolen_chips += stolen

	## Minor chip-theft damage.
	var amount := 1
	if ability != null:
		amount = ability.roll_base() + EnemyAbilityExecutor.resolve_damage_stat_bonus(caster, ability)
	if caster.statuses != null:
		amount = caster.statuses.modify_outgoing_damage(amount)
	amount = maxi(1, amount)
	if target.has_method("apply_enemy_damage_to_player"):
		var dealt: int = target.call("apply_enemy_damage_to_player", amount)
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_CHIP_THEFT") % [caster.get_localized_name(), stolen, amount, dealt]
		)
	if caster.statuses != null:
		caster.statuses.consume_frenzy_after_attack()
