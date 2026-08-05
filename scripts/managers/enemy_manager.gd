class_name EnemyManager
extends RefCounted
## Registry for hand-crafted EnemyGroup packs (human Act 1+).
## Enemy blueprints still resolve through EnemyDatabase (CSV).

const GROUPS_DIR := "res://data/enemy_groups/"
## Layers that may only draw from is_starter_group packs (normal combat).
const STARTER_LAYER_MAX := 2

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
	## Starter layers 1–2: starter groups only. Layer 3+: mid packs. Elite: elite packs.
	## Soft fallbacks never promote mid/elite packs onto starter layers.
	_ensure_groups_loaded()
	var layer := maxi(node_layer, 0)
	var pool: Array[EnemyGroup] = _build_pool(layer, is_elite)

	if pool.is_empty():
		pool = _build_fallback_pool(layer, is_elite)
	if pool.is_empty():
		push_warning(
			"EnemyManager: no EnemyGroup for layer=%d elite=%s" % [layer, str(is_elite)]
		)
		return null
	return pool[randi() % pool.size()]


static func _build_pool(layer: int, is_elite: bool) -> Array[EnemyGroup]:
	var pool: Array[EnemyGroup] = []
	if is_elite:
		for group: EnemyGroup in _groups_cache:
			if group == null or not group.is_elite:
				continue
			if group.matches_layer(layer):
				pool.append(group)
		return pool

	if layer <= STARTER_LAYER_MAX:
		for group: EnemyGroup in _groups_cache:
			if group == null or not group.is_starter_group or group.is_elite:
				continue
			if group.matches_layer(layer):
				pool.append(group)
		return pool

	for group: EnemyGroup in _groups_cache:
		if group == null or group.is_starter_group or group.is_elite:
			continue
		if group.matches_layer(layer):
			pool.append(group)
	return pool


static func _build_fallback_pool(layer: int, is_elite: bool) -> Array[EnemyGroup]:
	var pool: Array[EnemyGroup] = []
	if is_elite:
		## Any elite pack; prefer ones that match a nearby deeper layer.
		for group: EnemyGroup in _groups_cache:
			if group == null or not group.is_elite:
				continue
			if group.matches_layer(maxi(layer, group.min_layer)):
				pool.append(group)
		return pool

	if layer <= STARTER_LAYER_MAX:
		## Starter layers must stay on starter packs even if layer tags mismatch.
		for group: EnemyGroup in _groups_cache:
			if group != null and group.is_starter_group and not group.is_elite:
				pool.append(group)
		return pool

	## Mid layers: any non-elite non-starter pack.
	for group: EnemyGroup in _groups_cache:
		if group == null or group.is_starter_group or group.is_elite:
			continue
		pool.append(group)
	return pool


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
			var loaded = load(path)
			if loaded is EnemyGroup:
				var group: EnemyGroup = loaded
				_groups_cache.append(group)
				_validate_group(group)
		file_name = dir.get_next()
	dir.list_dir_end()


static func _validate_group(group: EnemyGroup) -> void:
	if group == null or not group.is_starter_group or group.is_elite:
		return
	if EnemyDatabase == null:
		return
	for eid in group.enemy_ids:
		var id_str := str(eid).strip_edges()
		if id_str.is_empty() or not EnemyDatabase.has_enemy(id_str):
			continue
		var data: EnemyData = EnemyDatabase.get_enemy(id_str)
		if data == null:
			continue
		var cost: int = data.threat_level
		if data.power_rating > 0:
			cost = data.power_rating
		if cost >= 8:
			push_warning(
				"EnemyManager: starter group '%s' includes heavy enemy '%s' (power %d)"
				% [group.group_id, id_str, cost]
			)
