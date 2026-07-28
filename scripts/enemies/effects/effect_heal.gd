class_name EffectHeal
extends AbilityEffect
## Restores HP to the caster (self) or a living ally when target_type is ally.


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null:
		return
	var ability := AbilityEffect.ability_from_params(params)
	var enemy_index := AbilityEffect.enemy_index_from_params(params)
	if ability == null:
		return

	var amount := ability.roll_base() + caster.get_stat(ability.stat_scaling)
	if caster.roll_crit():
		amount = int(round(float(amount) * EnemyInstance.CRIT_DAMAGE_MULT))
		caster.emit_crit_notice(enemy_index)
	amount = maxi(0, amount)

	var heal_target := caster
	if ability.target_type.strip_edges().to_lower() == "ally" and target != null and target.has_method("get_random_living_ally"):
		var ally: EnemyInstance = target.call("get_random_living_ally", caster)
		if ally != null:
			heal_target = ally

	var healed := heal_target.heal(amount)
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_ENEMY_HEAL") % [heal_target.get_localized_name(), healed]
	)
	if target != null and target.has_method("emit_enemy_hp_for"):
		target.call("emit_enemy_hp_for", heal_target)
