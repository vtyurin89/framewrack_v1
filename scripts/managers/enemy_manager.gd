class_name EnemyManager
extends RefCounted
## Registry for hand-crafted EnemyGroup packs (human Act 1+).
## Enemy blueprints still resolve through EnemyDatabase (CSV).

const GROUPS_DIR := "res://data/enemy_groups/"

const HUMAN_CORE_IDS: Array[String] = [
	"desperate_rebel",
	"field_medic",
	"rebel_warlord",
	"slaver_master",
	"slaver_minion",
	"corp_deserter",
	"pocket_thief",
	"scrapper_tank",
]

static var _groups_cache: Array[EnemyGroup] = []
static var _groups_loaded: bool = false


static func get_registered_human_ids() -> Array[String]:
	return HUMAN_CORE_IDS.duplicate()


static func is_summon_only(enemy_id: String) -> bool:
	return enemy_id.strip_edges().to_lower() == "slaver_minion"


static func get_all_groups(force_reload: bool = false) -> Array[EnemyGroup]:
	if force_reload:
		_groups_loaded = false
		_groups_cache.clear()
	_ensure_groups_loaded()
	return _groups_cache.duplicate()


static func get_group_by_id(group_id: String) -> EnemyGroup:
	_ensure_groups_loaded()
	var needle := group_id.strip_edges()
	for group: EnemyGroup in _groups_cache:
		if group != null and group.group_id == needle:
			return group
	return null


static func get_encounter_for_node(node_layer: int, is_elite: bool) -> EnemyGroup:
	## Starter layers 1–2: starter groups. Layer 3+: mid packs. Elite: elite packs.
	_ensure_groups_loaded()
	var layer := maxi(node_layer, 0)
	var pool: Array[EnemyGroup] = []

	if is_elite:
		for group: EnemyGroup in _groups_cache:
			if group == null or not group.is_elite:
				continue
			if group.matches_layer(layer):
				pool.append(group)
	elif layer <= 2:
		for group: EnemyGroup in _groups_cache:
			if group == null or not group.is_starter_group or group.is_elite:
				continue
			if group.matches_layer(layer):
				pool.append(group)
	else:
		for group: EnemyGroup in _groups_cache:
			if group == null or group.is_starter_group or group.is_elite:
				continue
			if group.matches_layer(layer):
				pool.append(group)

	if pool.is_empty():
		## Soft fallback: any non-elite group that matches the layer.
		for group: EnemyGroup in _groups_cache:
			if group == null or group.is_elite:
				continue
			if group.matches_layer(maxi(layer, 1)):
				pool.append(group)
	if pool.is_empty() and not _groups_cache.is_empty():
		pool.append(_groups_cache[0])
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]


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


static func _ensure_groups_loaded() -> void:
	if _groups_loaded:
		return
	_groups_loaded = true
	_groups_cache.clear()
	var dir := DirAccess.open(GROUPS_DIR)
	if dir == null:
		push_warning("EnemyManager: cannot open %s" % GROUPS_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var path := GROUPS_DIR.path_join(file_name)
			var loaded := load(path)
			if loaded is EnemyGroup:
				_groups_cache.append(loaded as EnemyGroup)
		file_name = dir.get_next()
	dir.list_dir_end()
