class_name ElderVaeron
extends RefCounted
## Act 1 boss helpers: Elder Vaeron + left/right Stasis Pods.

const ID_VAERON := "elder_vaeron"
const ID_POD_LEFT := "stasis_pod_left"
const ID_POD_RIGHT := "stasis_pod_right"

const ID_GLITCH_STRIKE := "ABILITY_VAERON_GLITCH_STRIKE"
const ID_SYNAPSE_CHARGE := "ABILITY_VAERON_SYNAPSE_CHARGE"
const ID_SYNAPSE_BLAST := "ABILITY_VAERON_SYNAPSE_BLAST"
const ID_NEURO_TICK := "ABILITY_VAERON_NEURO_TICK"
const ID_VAERON_SHIELD := "ABILITY_VAERON_SHIELD"
const ID_POD_HEAL := "ABILITY_POD_LEFT_HEAL"
const ID_POD_LARVA := "ABILITY_POD_LEFT_LARVA"
const ID_POD_STEAL := "ABILITY_POD_RIGHT_STEAL"
const ID_POD_PULSE := "ABILITY_POD_RIGHT_PULSE"

const ITEM_BIONIC_LARVA := "BIONIC_LARVA"
const ITEM_NEURO_TICK := "NEURO_TICK"

## HP damage during player turn that cancels Synapse Charge.
const SYNAPSE_INTERRUPT_DAMAGE := 15
## Block cap while right pod keeps Vaeron's shield persistent.
const VAERON_BLOCK_CAP := 45
const POD_HEAL_AMOUNT := 4


static func is_vaeron(enemy: EnemyInstance) -> bool:
	return enemy != null and enemy.data != null and enemy.data.id == ID_VAERON


static func is_pod_left(enemy: EnemyInstance) -> bool:
	return enemy != null and enemy.data != null and enemy.data.id == ID_POD_LEFT


static func is_pod_right(enemy: EnemyInstance) -> bool:
	return enemy != null and enemy.data != null and enemy.data.id == ID_POD_RIGHT


static func is_stasis_pod(enemy: EnemyInstance) -> bool:
	return is_pod_left(enemy) or is_pod_right(enemy)


static func find_vaeron(combat: Node) -> EnemyInstance:
	if combat == null or not (combat.get("enemies") is Array):
		return null
	for enemy: EnemyInstance in combat.enemies:
		if is_vaeron(enemy) and enemy.is_alive():
			return enemy
	return null


static func is_pod_right_alive(combat: Node) -> bool:
	if combat == null or not (combat.get("enemies") is Array):
		return false
	for enemy: EnemyInstance in combat.enemies:
		if is_pod_right(enemy) and enemy.is_alive():
			return true
	return false


static func are_both_pods_destroyed(combat: Node) -> bool:
	if combat == null or not (combat.get("enemies") is Array):
		return true
	var left_alive := false
	var right_alive := false
	for enemy: EnemyInstance in combat.enemies:
		if not enemy.is_alive():
			continue
		if is_pod_left(enemy):
			left_alive = true
		elif is_pod_right(enemy):
			right_alive = true
	return not left_alive and not right_alive


static func is_phase_two(enemy: EnemyInstance, combat: Node) -> bool:
	if not is_vaeron(enemy):
		return false
	if enemy.get_hp_ratio() < 0.5:
		return true
	return are_both_pods_destroyed(combat)


static func pick_scripted_ability(enemy: EnemyInstance, combat: Node) -> EnemyAbility:
	if enemy == null or enemy.data == null:
		return null
	match enemy.data.id:
		ID_VAERON:
			return _ai_vaeron(enemy, combat)
		ID_POD_LEFT:
			return _ai_pod_left(enemy, combat)
		ID_POD_RIGHT:
			return _ai_pod_right(enemy, combat)
		_:
			return null


static func _ai_vaeron(enemy: EnemyInstance, combat: Node) -> EnemyAbility:
	## Forced Synapse Blast follow-up after charge.
	var followup := enemy.find_ability(ID_SYNAPSE_BLAST)
	if (
		followup != null
		and enemy.can_use_ability(followup)
		and enemy.is_ability_prepared(ID_SYNAPSE_BLAST)
	):
		return followup

	if is_phase_two(enemy, combat):
		var tick := enemy.find_ability(ID_NEURO_TICK)
		if tick != null and enemy.can_use_ability(tick):
			## Prefer parasite insert when unlocked / off cooldown in phase 2.
			if enemy.turns_taken > 0 and enemy.turns_taken % 4 == 3:
				return tick
		var charge := enemy.find_ability(ID_SYNAPSE_CHARGE)
		if charge != null and enemy.can_use_ability(charge):
			if not enemy.is_ability_prepared(ID_SYNAPSE_BLAST):
				return charge

	var strike := enemy.find_ability(ID_GLITCH_STRIKE)
	if strike != null and enemy.can_use_ability(strike):
		return strike
	var shield := enemy.find_ability(ID_VAERON_SHIELD)
	if shield != null and enemy.can_use_ability(shield):
		return shield
	return null


static func _ai_pod_left(enemy: EnemyInstance, _combat: Node) -> EnemyAbility:
	## Heal Vaeron every act; larva is a PRE_ACTION on interval 3.
	var heal := enemy.find_ability(ID_POD_HEAL)
	if heal != null and enemy.can_use_ability(heal):
		return heal
	return null


static func _ai_pod_right(enemy: EnemyInstance, _combat: Node) -> EnemyAbility:
	var steal := enemy.find_ability(ID_POD_STEAL)
	if steal != null and enemy.can_use_ability(steal) and enemy.stolen_grid_item == null:
		## Act 2+ (available_from_turn=2) and once per fight (max_charges=1).
		return steal
	var pulse := enemy.find_ability(ID_POD_PULSE)
	if pulse != null and enemy.can_use_ability(pulse):
		return pulse
	return null


static func clamp_vaeron_block(enemy: EnemyInstance) -> void:
	if not is_vaeron(enemy):
		return
	if enemy.current_block > VAERON_BLOCK_CAP:
		enemy.current_block = VAERON_BLOCK_CAP
