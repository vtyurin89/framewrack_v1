class_name CombatSummonHelper
extends RefCounted
## Spawns additional combatants into an active CombatManager encounter.


static func spawn_enemy(combat: Node, enemy_id: String) -> EnemyInstance:
	if combat == null or enemy_id.strip_edges().is_empty():
		return null
	if EnemyDatabase == null or not EnemyDatabase.has_enemy(enemy_id):
		push_warning("CombatSummonHelper: unknown enemy id '%s'" % enemy_id)
		return null
	var instance: EnemyInstance = EnemyDatabase.create_instance(enemy_id)
	if instance == null:
		return null
	if combat.has_method("add_summoned_enemy"):
		combat.call("add_summoned_enemy", instance)
	return instance
