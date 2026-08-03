class_name FacelessLady
extends RefCounted
## Scripted AI helpers for the Faceless Lady (Безликая дама).

const ID_INJECT := "ABILITY_FACELESS_INJECT"
const ID_TEETH := "ABILITY_FACELESS_TEETH"
const ID_GRIP := "ABILITY_FACELESS_GRIP"
const PARASITE_ITEM_ID := "SLIMY_PARASITE"


static func pick_scripted_ability(enemy: EnemyInstance, combat: Node) -> EnemyAbility:
	## Parasite Injection from Turn 2 onward (cooldown handled by EnemyInstance).
	if enemy == null or enemy.data == null:
		return null
	## turns_taken counts completed turns; Turn 2 plans when turns_taken >= 1.
	if enemy.turns_taken < 1:
		return null
	if _player_has_parasite(combat):
		return null
	var inject := enemy.find_ability(ID_INJECT)
	if inject != null and not enemy.is_ability_on_cooldown(inject):
		return inject
	return null


static func _player_has_parasite(combat: Node) -> bool:
	if combat == null:
		return false
	if combat.has_method("has_item_in_grid"):
		return bool(combat.call("has_item_in_grid", PARASITE_ITEM_ID))
	return false
