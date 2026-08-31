class_name EffectDamage
extends AbilityEffect
## Deals one or more damage rolls. STR for physical, INT for spells; luck may crit.
## Optional effect_params:
##   block|N — gain flat Block before striking
##   poison|3 — always apply status rider
##   poison|3|if_hp — apply only if any hit dealt HP damage through Block


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null or target == null or not target.has_method("apply_enemy_damage_to_player"):
		return
	var ability := AbilityEffect.ability_from_params(params)
	var enemy_index := AbilityEffect.enemy_index_from_params(params)
	if ability == null:
		return

	_apply_flat_block_from_params(caster, target, ability, enemy_index)

	var hits := maxi(1, ability.hit_count)
	## Physical → Strength; spell → Intelligence (via scaling_stat / half-STR multi-hit).
	var stat_bonus := EnemyAbilityExecutor.resolve_damage_stat_bonus(caster, ability)
	var total_hp_dealt := 0
	for _i in hits:
		var base_roll := ability.roll_base()
		var amount := base_roll + stat_bonus
		var is_crit := false
		if target.has_method("consume_forced_enemy_crit") and bool(target.call("consume_forced_enemy_crit")):
			is_crit = true
		else:
			is_crit = caster.roll_crit()
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
		total_hp_dealt += maxi(0, dealt)
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

	_apply_status_riders(caster, target, ability, total_hp_dealt > 0)

	if caster.statuses != null:
		caster.statuses.consume_frenzy_after_attack()


func _apply_flat_block_from_params(
	caster: EnemyInstance, target: Node, ability: EnemyAbility, enemy_index: int
) -> void:
	var amount := AbilityEffect.parse_flat_block(ability)
	if amount <= 0:
		return
	if caster.roll_crit():
		amount = roundi(float(amount) * EnemyInstance.CRIT_DAMAGE_MULT)
		caster.emit_crit_notice(enemy_index)
	caster.gain_block(amount)
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_ENEMY_BLOCK") % [caster.get_localized_name(), amount]
	)
	if target != null and target.has_method("emit_enemy_block_for"):
		target.call("emit_enemy_block_for", caster)


func _apply_status_riders(
	caster: EnemyInstance, target: Node, ability: EnemyAbility, dealt_hp: bool
) -> void:
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
		if token in ["block", "guard", "shield"]:
			## Flat block handled separately; skip value token.
			if i + 1 < csv.size() and str(csv[i + 1]).is_valid_int():
				i += 2
			else:
				i += 1
			continue
		if token not in known:
			i += 1
			continue
		var stacks := 1
		var require_hp := false
		if i + 1 < csv.size() and str(csv[i + 1]).is_valid_int():
			stacks = maxi(1, int(csv[i + 1]))
			i += 2
			if i < csv.size() and str(csv[i]).strip_edges().to_lower() in ["if_hp", "on_hp"]:
				require_hp = true
				i += 1
		else:
			i += 1
		if require_hp and not dealt_hp:
			continue
		if target.has_method("apply_player_status"):
			target.call("apply_player_status", token, stacks)
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_ENEMY_STATUS") % [caster.get_localized_name(), token, stacks]
			)
