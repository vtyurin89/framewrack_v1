class_name EnemyManager
extends RefCounted
## Act spawn tables and encounter helpers for human (and other) enemy packs.
## Enemy blueprints live in CSV via EnemyDatabase; this registers content IDs
## used by Act 1 / Act 2 generators and fixed encounters.

const HUMAN_CORE_IDS: Array[String] = [
	"slaver_master",
	"slaver_minion",
	"corp_deserter",
	"pocket_thief",
	"scrapper_tank",
]

## Act 1 human pool — summon minions are excluded from random packs.
const ACT1_HUMAN_SPAWN: Array[String] = [
	"desperate_rebel",
	"field_medic",
	"slaver_master",
	"corp_deserter",
	"pocket_thief",
	"scrapper_tank",
]

const ACT2_HUMAN_SPAWN: Array[String] = [
	"desperate_rebel",
	"field_medic",
	"rebel_warlord",
	"slaver_master",
	"corp_deserter",
	"pocket_thief",
	"scrapper_tank",
]

## Fixed showcase packs (solo master, deserter duo, etc.).
const PACK_SLAVER_SOLO: Array[String] = ["slaver_master"]
const PACK_DESERTER: Array[String] = ["corp_deserter"]
const PACK_THIEF: Array[String] = ["pocket_thief"]
const PACK_SCRAPPER: Array[String] = ["scrapper_tank"]
const PACK_HUMAN_STREET: Array[String] = ["pocket_thief", "desperate_rebel"]
const PACK_HUMAN_CHECKPOINT: Array[String] = ["scrapper_tank", "corp_deserter"]


static func get_registered_human_ids() -> Array[String]:
	return HUMAN_CORE_IDS.duplicate()


static func get_act_spawn_table(act: int) -> Array[String]:
	if act >= 2:
		return ACT2_HUMAN_SPAWN.duplicate()
	return ACT1_HUMAN_SPAWN.duplicate()


static func is_summon_only(enemy_id: String) -> bool:
	return enemy_id.strip_edges().to_lower() == "slaver_minion"


static func generate_act_encounter(act: int, budget: int, faction: String = "human") -> Array[EnemyData]:
	## Builds an encounter from the act spawn table using power_rating costs.
	var result: Array[EnemyData] = []
	if EnemyDatabase == null:
		return result
	var pool_ids := get_act_spawn_table(act)
	var pool: Array[EnemyData] = []
	for eid in pool_ids:
		if is_summon_only(eid):
			continue
		if not EnemyDatabase.has_enemy(eid):
			continue
		var bp: EnemyData = EnemyDatabase.get_enemy(eid)
		if bp == null:
			continue
		if not faction.is_empty() and bp.get_faction() != faction.strip_edges().to_lower():
			continue
		pool.append(bp)
	if pool.is_empty():
		return EnemyDatabase.generate_encounter(faction, budget)

	var remaining := maxi(budget, 0)
	var working := pool.duplicate()
	working.shuffle()
	var guard := 0
	while remaining > 0 and guard < 64:
		guard += 1
		var candidates: Array[EnemyData] = []
		for enemy: EnemyData in working:
			var cost := _cost(enemy)
			if cost <= remaining:
				candidates.append(enemy)
		if candidates.is_empty():
			break
		var pick: EnemyData = candidates[randi() % candidates.size()]
		result.append(EnemyDatabase.create_blueprint(pick.id))
		remaining -= _cost(pick)

	if result.is_empty():
		working.sort_custom(func(a: EnemyData, b: EnemyData) -> bool:
			return _cost(a) < _cost(b)
		)
		result.append(EnemyDatabase.create_blueprint(working[0].id))
	return result


static func create_pack(pack_ids: Array) -> Array[EnemyData]:
	var result: Array[EnemyData] = []
	if EnemyDatabase == null:
		return result
	for eid in pack_ids:
		var id_str := str(eid).strip_edges()
		if id_str.is_empty() or not EnemyDatabase.has_enemy(id_str):
			continue
		var bp := EnemyDatabase.create_blueprint(id_str)
		if bp != null:
			result.append(bp)
	return result


static func _cost(enemy: EnemyData) -> int:
	if enemy == null:
		return 1
	if enemy.power_rating > 0:
		return enemy.power_rating
	return maxi(enemy.threat_level, 1)
