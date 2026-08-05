class_name EnemyAbilityExecutor
extends RefCounted
## Maps EnemyAbility.main_effect to AbilityEffect handlers and runs combat side-effects.

var _combat: Node
var _handlers: Dictionary = {}  # String -> AbilityEffect


func _init(combat: Node = null) -> void:
	_combat = combat
	_handlers = {
		"damage": EffectDamage.new(),
		"heal": EffectHeal.new(),
		"modify_stat": EffectModifyStat.new(),
		"status": EffectStatus.new(),
		"shield": EffectShield.new(),
		"summon": EffectSummon.new(),
		"brand_stim": EffectBrandStimulation.new(),
		"steal_chips": EffectStealChips.new(),
		"flee": EffectFlee.new(),
		"ally_buff": EffectAllyBuff.new(),
		"force_insert": EffectForceInsert.new(),
	}


func set_combat(combat: Node) -> void:
	_combat = combat


static func resolve_damage_stat_bonus(caster: EnemyInstance, ability: EnemyAbility) -> int:
	## Physical → Strength; spell → Intelligence; multi-hit / Desperate Attack → floor(STR / 2).
	if caster == null or ability == null:
		return 0
	match ability.stat_scaling:
		EnemyAbility.StatScaling.STRENGTH:
			return caster.strength
		EnemyAbility.StatScaling.INTELLIGENCE:
			return caster.intelligence
		EnemyAbility.StatScaling.AGILITY:
			return caster.agility
		EnemyAbility.StatScaling.ENDURANCE:
			return caster.endurance
		EnemyAbility.StatScaling.LUCK:
			return caster.luck
		EnemyAbility.StatScaling.NONE:
			if ability.type == EnemyAbility.AbilityType.MULTI_HIT or ability.hit_count > 1:
				return int(caster.strength / 2.0)
			return 0
		_:
			return 0


static func resolve_shield_block(caster: EnemyInstance, ability: EnemyAbility) -> int:
	## Shield skills: base_block + caster agility.
	if caster == null or ability == null:
		return caster.agility if caster != null else 0
	return ability.roll_base() + caster.agility


func execute(caster: EnemyInstance, enemy_index: int, ability: EnemyAbility) -> void:
	if caster == null or ability == null or _combat == null:
		return

	## Floating notice from CSV combat_text / ability name.
	var notice_kind := "ability"
	if ability.type == EnemyAbility.AbilityType.PRE_ACTION:
		notice_kind = "pre_action"
	elif ability.hit_count > 1 and ability.main_effect == "damage":
		notice_kind = "multi_hit"
	caster.emit_ability_notice(enemy_index, ability, notice_kind)

	var effect_key := ability.main_effect.strip_edges().to_lower()
	if effect_key.is_empty():
		effect_key = ability.infer_main_effect()
	## Legacy BLOCK / status+block rows route through EffectShield.
	if effect_key == "status" and _is_shield_ability(ability):
		effect_key = "shield"
	elif ability.type == EnemyAbility.AbilityType.BLOCK:
		effect_key = "shield"

	if ability.hit_count > 1 and effect_key == "damage":
		EventBus.combat_log_message.emit(
			TranslationServer.translate("KEY_LOG_ENEMY_MULTI_HIT") % [
				caster.get_localized_name(),
				ability.get_localized_name(),
				maxi(1, ability.hit_count),
			]
		)

	var handler: AbilityEffect = _handlers.get(effect_key, null)
	if handler == null:
		## Fallback: treat unknown effects as damage.
		handler = _handlers["damage"]

	var params: Array = [ability, enemy_index]
	params.append_array(ability.get_effect_param_list())
	handler.apply(caster, _combat, params)

	if ability.requires_prepare:
		caster.consume_prepared_ability(ability.id)

	## Healing / defensive skills always share a 1-turn cooldown floor.
	if ability.requires_defensive_cooldown():
		var cd := maxi(1, ability.cooldown_turns)
		caster.start_ability_cooldown(ability, cd)
	elif ability.cooldown_turns > 0:
		caster.start_ability_cooldown(ability, ability.cooldown_turns)


static func _is_shield_ability(ability: EnemyAbility) -> bool:
	if ability == null:
		return false
	var params := ability.effect_params.strip_edges().to_lower()
	return (
		params.begins_with("block")
		or params.begins_with("guard")
		or params.begins_with("shield")
	)
