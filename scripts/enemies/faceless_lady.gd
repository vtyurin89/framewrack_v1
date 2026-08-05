class_name FacelessLady
extends RefCounted
## Scripted AI helpers for the Faceless Lady (Безликая дама).

const ID_INJECT := "ABILITY_FACELESS_INJECT"
const ID_TEETH := "ABILITY_FACELESS_TEETH"
const ID_GRIP := "ABILITY_FACELESS_GRIP"
const PARASITE_ITEM_ID := "SLIMY_PARASITE"


static func pick_scripted_ability(enemy: EnemyInstance, combat: Node) -> EnemyAbility:
	## Parasite Injection once unlocked (available_from_turn on the ability CSV).
	if enemy == null or enemy.data == null:
		return null
	if _player_has_parasite(combat):
		return null
	var inject := enemy.find_ability(ID_INJECT)
	if inject != null and enemy.can_use_ability(inject):
		return inject
	return null


static func _player_has_parasite(combat: Node) -> bool:
	if combat == null:
		return false
	if combat.has_method("has_item_in_grid"):
		return bool(combat.call("has_item_in_grid", PARASITE_ITEM_ID))
	return false
