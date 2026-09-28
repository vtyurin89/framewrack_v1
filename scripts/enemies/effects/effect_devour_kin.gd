class_name EffectDevourKin
extends AbilityEffect
## Scavenger Chimera: tears into a downed sibling (entity_trembling_corpse).
## Deals fixed pure damage; a kill fully heals the cannibal and stacks +3 STR / +3 LCK.


const DEVOUR_DAMAGE := 8
const CORPSE_ID := "entity_trembling_corpse"


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if caster == null or target == null:
		return
	var corpse: EnemyInstance = null
	if target.has_method("find_enemy_by_id"):
		corpse = target.call("find_enemy_by_id", CORPSE_ID)
	if corpse == null:
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_DEVOUR_NONE") % caster.get_localized_name()
		)
		return
	EventBus.combat_log_message.emit(
		tr("KEY_LOG_DEVOUR_KIN") % [
			caster.get_localized_name(),
			corpse.get_localized_name(),
			DEVOUR_DAMAGE,
		]
	)
	corpse.apply_incoming_damage(DEVOUR_DAMAGE, true)
	if target.has_method("emit_enemy_hp_for"):
		target.call("emit_enemy_hp_for", corpse)
	if not corpse.is_alive() and target.has_method("on_enemy_devoured"):
		target.call("on_enemy_devoured", caster, corpse)
