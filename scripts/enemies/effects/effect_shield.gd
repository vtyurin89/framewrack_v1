class_name EffectShield
extends AbilityEffect
## Generates Block: base_block + caster agility.


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null:
		return
	var ability := AbilityEffect.ability_from_params(params)
	var enemy_index := AbilityEffect.enemy_index_from_params(params)
	if ability == null:
		return

	var amount := EnemyAbilityExecutor.resolve_shield_block(caster, ability)
	if caster.roll_crit():
		amount = roundi(float(amount) * EnemyInstance.CRIT_DAMAGE_MULT)
		caster.emit_crit_notice(enemy_index)
	amount = maxi(0, amount)
	caster.gain_block(amount)
	if ElderVaeron.is_vaeron(caster) and ElderVaeron.is_pod_right_alive(target):
		ElderVaeron.clamp_vaeron_block(caster)
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_ENEMY_BLOCK") % [caster.get_localized_name(), amount]
	)
	if target != null and target.has_method("emit_enemy_block_for"):
		target.call("emit_enemy_block_for", caster)
	elif target != null and target.has_method("emit_enemy_hp_for"):
		target.call("emit_enemy_hp_for", caster)
