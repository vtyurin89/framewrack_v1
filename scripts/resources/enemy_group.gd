class_name EnemyGroup
extends Resource
## Hand-crafted combat pack (max 3 enemies). Selected by map layer / elite flag.

@export var group_id: String = ""
@export var group_name: String = ""
## Preferred authoring path when EnemyData assets are stubs / CSV-backed.
@export var enemy_ids: Array[String] = []
## Optional embedded EnemyData (id is enough; resolved via EnemyDatabase at spawn).
@export var enemies: Array[EnemyData] = []
## Act primary_faction gate: human (Act 1), synthet (Act 2+), chimera (Act 3).
@export var faction: String = "human"
@export var min_layer: int = 1
@export var max_layer: int = 99
@export var is_starter_group: bool = false
@export var is_elite: bool = false
## Caps how many units may use heavy offensive actions in one enemy turn.
@export var max_attackers_per_turn: int = 2


func matches_layer(layer: int) -> bool:
	return layer >= min_layer and layer <= max_layer


func get_faction() -> String:
	var f := faction.strip_edges().to_lower()
	if f == "robot":
		return "synthet"
	return f if not f.is_empty() else "human"


func matches_faction(wanted: String) -> bool:
	var w := wanted.strip_edges().to_lower()
	if w.is_empty():
		return true
	if w == "robot":
		w = "synthet"
	return get_faction() == w


func resolve_enemy_datas() -> Array[EnemyData]:
	## Builds up to 3 runtime blueprints from IDs (CSV) or embedded EnemyData stubs.
	var result: Array[EnemyData] = []
	var ids := _collect_ids()
	for enemy_id in ids:
		if result.size() >= 3:
			break
		var id_str := enemy_id.strip_edges()
		if id_str.is_empty():
			continue
		if EnemyDatabase != null and EnemyDatabase.has_enemy(id_str):
			var bp := EnemyDatabase.create_blueprint(id_str)
			if bp != null:
				result.append(bp)
				continue
		## Fallback: duplicate embedded stub if present.
		for stub: EnemyData in enemies:
			if stub != null and stub.id == id_str:
				result.append(stub.duplicate(true) as EnemyData)
				break
	return result


func _collect_ids() -> Array[String]:
	var ids: Array[String] = []
	if not enemy_ids.is_empty():
		for eid in enemy_ids:
			var s := str(eid).strip_edges()
			if not s.is_empty():
				ids.append(s)
		return ids
	for enemy: EnemyData in enemies:
		if enemy == null:
			continue
		var s := enemy.id.strip_edges()
		if not s.is_empty():
			ids.append(s)
	return ids
