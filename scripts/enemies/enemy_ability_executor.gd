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
		"summon": EffectSummon.new(),
	}


func set_combat(combat: Node) -> void:
	_combat = combat


static func resolve_damage_stat_bonus(caster: EnemyInstance, ability: EnemyAbility) -> int:
	## Full scaling_stat when set; multi-hit / Desperate Attack uses floor(STR / 2).
	if caster == null or ability == null:
		return 0
	if ability.stat_scaling != EnemyAbility.StatScaling.NONE:
		return caster.get_stat(ability.stat_scaling)
	if ability.type == EnemyAbility.AbilityType.MULTI_HIT or ability.hit_count > 1:
		return int(caster.strength / 2.0)
	return 0


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

	## Healing / defensive skills always share a 1-turn cooldown floor.
	if ability.requires_defensive_cooldown():
		var cd := maxi(1, ability.cooldown_turns)
		caster.start_ability_cooldown(ability, cd)
	elif ability.cooldown_turns > 0:
		caster.start_ability_cooldown(ability, ability.cooldown_turns)
