extends Node
## Autoload: loads enemy blueprints and abilities from CSV.

const ABILITIES_CSV_PATH := "res://data/abilities.csv"
const ENEMIES_CSV_PATH := "res://data/enemies.csv"

var _abilities_by_id: Dictionary = {}  # String -> EnemyAbility
var _enemies_by_id: Dictionary = {}  # String -> EnemyData


func _ready() -> void:
	reload()


func reload() -> void:
	_abilities_by_id.clear()
	_enemies_by_id.clear()
	_load_abilities_csv(ABILITIES_CSV_PATH)
	_load_enemies_csv(ENEMIES_CSV_PATH)


func get_ability(ability_id: String) -> EnemyAbility:
	return _abilities_by_id.get(ability_id, null)


func get_enemy(enemy_id: String) -> EnemyData:
	return _enemies_by_id.get(enemy_id, null)


func has_enemy(enemy_id: String) -> bool:
	return _enemies_by_id.has(enemy_id)


func get_all_enemies() -> Array[EnemyData]:
	var result: Array[EnemyData] = []
	for enemy: EnemyData in _enemies_by_id.values():
		result.append(enemy)
	return result


func create_blueprint(enemy_id: String) -> EnemyData:
	## Deep duplicate so encounter-specific edits don't mutate the catalog.
	var proto := get_enemy(enemy_id)
	if proto == null:
		push_warning("EnemyDatabase: unknown enemy id '%s'" % enemy_id)
		return null
	return proto.duplicate(true) as EnemyData


func create_instance(enemy_id: String) -> EnemyInstance:
	var blueprint := create_blueprint(enemy_id)
	if blueprint == null:
		return null
	var instance := EnemyInstance.new()
	instance.setup(blueprint)
	return instance


func create_instance_from_data(blueprint: EnemyData) -> EnemyInstance:
	if blueprint == null:
		return null
	var instance := EnemyInstance.new()
	instance.setup(blueprint.duplicate(true) as EnemyData)
	return instance


# ---------------------------------------------------------------------------
# Encounter generation
# ---------------------------------------------------------------------------

func get_enemies_by_faction_and_tier(faction: String, tier: String) -> Array[EnemyData]:
	var result: Array[EnemyData] = []
	var faction_key := faction.strip_edges().to_lower()
	var tier_key := tier.strip_edges().to_lower()
	if faction_key.is_empty() or tier_key.is_empty():
		return result
	for enemy: EnemyData in _enemies_by_id.values():
		if enemy == null:
			continue
		if enemy.get_faction() == faction_key and enemy.get_combat_tier() == tier_key:
			result.append(enemy)
	return result


func get_random_boss() -> EnemyData:
	## Picks a random boss-tier enemy (any faction). Caller may filter further.
	var bosses: Array[EnemyData] = []
	for enemy: EnemyData in _enemies_by_id.values():
		if enemy != null and enemy.is_boss_tier():
			bosses.append(enemy)
	if bosses.is_empty():
		push_warning("EnemyDatabase: no boss-tier enemies in catalog")
		return null
	bosses.shuffle()
	return create_blueprint(bosses[0].id)


func get_random_boss_for_faction(faction: String) -> EnemyData:
	var bosses: Array[EnemyData] = get_enemies_by_faction_and_tier(faction, EnemyData.TIER_BOSS)
	if bosses.is_empty():
		## Fallback: role=boss in case tier was mis-tagged.
		for enemy: EnemyData in _enemies_by_id.values():
			if enemy != null and enemy.get_faction() == faction.strip_edges().to_lower() and enemy.get_role() == EnemyData.ROLE_BOSS:
				bosses.append(enemy)
	if bosses.is_empty():
		return null
	bosses.shuffle()
	return create_blueprint(bosses[0].id)


func generate_encounter(faction: String, budget: int) -> Array[EnemyData]:
	## Builds a same-faction NORMAL-tier pack that fits within `budget` threat.
	var result: Array[EnemyData] = []
	var pool: Array[EnemyData] = get_enemies_by_faction_and_tier(faction, EnemyData.TIER_NORMAL)
	if pool.is_empty():
		push_warning("EnemyDatabase: no normal enemies for faction '%s'" % faction)
		return result

	var remaining := maxi(budget, 0)
	if remaining <= 0:
		## Still return one cheapest fighter so combat can start.
		pool.sort_custom(func(a: EnemyData, b: EnemyData) -> bool: return a.threat_level < b.threat_level)
		result.append(create_blueprint(pool[0].id))
		return result

	var working: Array[EnemyData] = pool.duplicate()
	working.shuffle()
	var guard := 0
	while remaining > 0 and guard < 64:
		guard += 1
		var candidates: Array[EnemyData] = []
		for enemy: EnemyData in working:
			var cost := maxi(enemy.threat_level, 1)
			if cost <= remaining:
				candidates.append(enemy)
		if candidates.is_empty():
			break
		var pick: EnemyData = candidates[randi() % candidates.size()]
		result.append(create_blueprint(pick.id))
		remaining -= maxi(pick.threat_level, 1)

	if result.is_empty():
		working.sort_custom(func(a: EnemyData, b: EnemyData) -> bool: return a.threat_level < b.threat_level)
		result.append(create_blueprint(working[0].id))
	return result


func validate_same_faction(enemies: Array[EnemyData]) -> bool:
	if enemies.is_empty():
		return true
	var faction := ""
	for enemy: EnemyData in enemies:
		if enemy == null:
			continue
		if faction.is_empty():
			faction = enemy.get_faction()
			continue
		if enemy.get_faction() != faction:
			return false
	return true


# ---------------------------------------------------------------------------
# Abilities CSV
# ---------------------------------------------------------------------------

func _load_abilities_csv(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("EnemyDatabase: missing %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("EnemyDatabase: cannot open %s" % path)
		return

	var header: PackedStringArray = file.get_csv_line()
	var col: Dictionary = _header_map(header)
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if _is_blank_row(row):
			continue
		var ability := _parse_ability_row(row, col)
		if ability != null and not ability.id.is_empty():
			_abilities_by_id[ability.id] = ability


func _parse_ability_row(row: PackedStringArray, col: Dictionary) -> EnemyAbility:
	var ability := EnemyAbility.new()
	ability.id = _cell(row, col, "id").strip_edges()
	if ability.id.is_empty():
		return null

	var name_cell := _cell(row, col, "name")
	ability.ability_name_key = name_cell if not name_cell.is_empty() else ability.id + "_NAME"

	var desc_cell := _cell(row, col, "description")
	if desc_cell.is_empty():
		desc_cell = _cell(row, col, "desc")
	ability.description_key = desc_cell if not desc_cell.is_empty() else ability.id + "_DESC"

	ability.target_type = _cell(row, col, "target_type").strip_edges().to_lower()
	if ability.target_type.is_empty():
		ability.target_type = "player"

	ability.main_effect = EnemyAbility.parse_main_effect(_cell(row, col, "main_effect"))
	ability.effect_params = _cell(row, col, "effect_params").strip_edges()

	ability.type = EnemyAbility.parse_type(_cell(row, col, "type"))
	if ability.main_effect.is_empty():
		ability.main_effect = ability.infer_main_effect()

	ability.min_val = _parse_int(_cell(row, col, "min_val"), 1)
	ability.max_val = _parse_int(_cell(row, col, "max_val"), ability.min_val)

	var scaling_raw := _cell(row, col, "scaling_stat")
	if scaling_raw.is_empty():
		scaling_raw = _cell(row, col, "stat_scaling")
	ability.stat_scaling = EnemyAbility.parse_stat_scaling(scaling_raw)

	var weight_raw := _cell(row, col, "weight_class")
	if weight_raw.is_empty():
		match ability.type:
			EnemyAbility.AbilityType.MULTI_HIT:
				ability.weight_class = EnemyAbility.WeightClass.HEAVY
			EnemyAbility.AbilityType.BLOCK, EnemyAbility.AbilityType.HEAL, EnemyAbility.AbilityType.PRE_ACTION:
				ability.weight_class = EnemyAbility.WeightClass.LIGHT
			_:
				ability.weight_class = EnemyAbility.WeightClass.STANDARD
	else:
		ability.weight_class = EnemyAbility.parse_weight_class(weight_raw)

	ability.base_ai_weight = _parse_float(_cell(row, col, "ai_weight"), 1.0)
	ability.hit_count = maxi(0, _parse_int(_cell(row, col, "hit_count"), 1))
	ability.hp_threshold = _parse_float(_cell(row, col, "hp_threshold"), 0.0)
	ability.cooldown_turns = maxi(0, _parse_int(_cell(row, col, "cooldown_turns"), 0))
	ability.max_charges = _parse_int(_cell(row, col, "max_charges"), -1)
	ability.trigger_interval = maxi(0, _parse_int(_cell(row, col, "trigger_interval"), 0))
	if ability.type == EnemyAbility.AbilityType.PRE_ACTION:
		ability.base_ai_weight = 0.0
		if ability.trigger_interval <= 0:
			ability.trigger_interval = 2
	elif ability.type == EnemyAbility.AbilityType.MULTI_HIT:
		ability.base_ai_weight = 0.0
		if ability.hit_count <= 0:
			ability.hit_count = 3
		if ability.hp_threshold <= 0.0:
			ability.hp_threshold = 0.4
		if ability.cooldown_turns <= 0:
			ability.cooldown_turns = 1

	## Healing / defensive / shielding skills always share a 1-turn cooldown floor.
	if ability.requires_defensive_cooldown() and ability.cooldown_turns < 1:
		ability.cooldown_turns = 1

	ability.combat_text = _cell(row, col, "combat_text").strip_edges()
	return ability


# ---------------------------------------------------------------------------
# Enemies CSV
# ---------------------------------------------------------------------------

func _load_enemies_csv(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("EnemyDatabase: missing %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("EnemyDatabase: cannot open %s" % path)
		return

	var header: PackedStringArray = file.get_csv_line()
	var col: Dictionary = _header_map(header)
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if _is_blank_row(row):
			continue
		var enemy := _parse_enemy_row(row, col)
		if enemy != null and not enemy.id.is_empty():
			_enemies_by_id[enemy.id] = enemy


func _parse_enemy_row(row: PackedStringArray, col: Dictionary) -> EnemyData:
	var enemy := EnemyData.new()
	enemy.id = _cell(row, col, "id").strip_edges()
	if enemy.id.is_empty():
		return null

	var name_cell := _cell(row, col, "name")
	enemy.enemy_name_key = name_cell if not name_cell.is_empty() else "ENEMY_UNKNOWN_NAME"
	var desc_cell := _cell(row, col, "description")
	enemy.enemy_desc_key = desc_cell
	enemy.display_name = enemy.id.capitalize().replace("_", " ")

	enemy.base_hp = _parse_int(_cell(row, col, "base_hp"), 0)
	enemy.max_hp = maxi(enemy.base_hp, 1)
	enemy.strength = maxi(1, _parse_int(_cell(row, col, "str"), 1))
	enemy.agility = maxi(1, _parse_int(_cell(row, col, "agi"), 1))
	enemy.endurance = maxi(1, _parse_int(_cell(row, col, "end"), 1))
	enemy.intelligence = maxi(1, _parse_int(_cell(row, col, "int"), 1))
	enemy.luck = maxi(1, _parse_int(_cell(row, col, "lck"), 1))
	enemy.exp_reward = _parse_int(_cell(row, col, "exp_reward"), 15)

	enemy.faction = _normalize_faction(_cell(row, col, "faction"), enemy.id)
	enemy.combat_tier = _normalize_tier(_cell(row, col, "combat_tier"))
	enemy.role = _normalize_role(_cell(row, col, "role"), enemy.combat_tier)
	enemy.threat_level = maxi(1, _parse_int(_cell(row, col, "threat_level"), 10))

	enemy.abilities = _parse_ability_list(_cell(row, col, "abilities"))
	enemy.trait_ids = _parse_id_list(_cell(row, col, "traits"))
	enemy.sprite_path = _cell(row, col, "sprite_path")

	var color_raw := _cell(row, col, "placeholder_color")
	if not color_raw.is_empty():
		enemy.placeholder_color = Color.html(color_raw)
	elif enemy.id.find("synthet") >= 0:
		enemy.placeholder_color = Color(0.65, 0.55, 0.7, 1)
	else:
		enemy.placeholder_color = Color(0.82, 0.82, 0.85, 1)

	## Legacy fallbacks derived from first matching abilities.
	for ability: EnemyAbility in enemy.abilities:
		if ability == null:
			continue
		if ability.type == EnemyAbility.AbilityType.DAMAGE:
			enemy.basic_damage = ability.min_val + enemy.strength
		elif ability.type == EnemyAbility.AbilityType.MULTI_HIT:
			enemy.special_damage = ability.max_val
			enemy.special_chance = 0.0
			enemy.corruption_duration = 0
	return enemy


func _parse_ability_list(raw: String) -> Array[EnemyAbility]:
	var result: Array[EnemyAbility] = []
	for ability_id in _parse_id_list(raw):
		var proto: EnemyAbility = _abilities_by_id.get(ability_id, null)
		if proto != null:
			result.append(proto.duplicate(true) as EnemyAbility)
		else:
			push_warning("EnemyDatabase: unknown ability '%s'" % ability_id)
	return result


func _parse_id_list(raw: String) -> Array[String]:
	var result: Array[String] = []
	var cleaned := raw.strip_edges().trim_prefix("\"").trim_suffix("\"")
	if cleaned.is_empty():
		return result
	for part in cleaned.split(",", false):
		var id := str(part).strip_edges()
		if not id.is_empty():
			result.append(id)
	return result


# ---------------------------------------------------------------------------
# CSV helpers
# ---------------------------------------------------------------------------

func _header_map(header: PackedStringArray) -> Dictionary:
	var map: Dictionary = {}
	for i in header.size():
		map[str(header[i]).strip_edges().to_lower()] = i
	return map


func _cell(row: PackedStringArray, col: Dictionary, name: String) -> String:
	var idx: int = int(col.get(name.to_lower(), -1))
	if idx < 0 or idx >= row.size():
		return ""
	return str(row[idx]).strip_edges()


func _is_blank_row(row: PackedStringArray) -> bool:
	return row.is_empty() or (row.size() == 1 and str(row[0]).strip_edges().is_empty())


func _parse_int(raw: String, default_value: int = 0) -> int:
	var cell := raw.strip_edges()
	if cell.is_empty() or not cell.is_valid_int():
		return default_value
	return int(cell)


func _parse_float(raw: String, default_value: float = 0.0) -> float:
	var cell := raw.strip_edges()
	if cell.is_empty() or not cell.is_valid_float():
		return default_value
	return float(cell)


func _normalize_faction(raw: String, enemy_id: String) -> String:
	var key := raw.strip_edges().to_lower()
	match key:
		EnemyData.FACTION_HUMAN, EnemyData.FACTION_SYNTHET, EnemyData.FACTION_CHIMERA:
			return key
		_:
			pass
	## Infer from legacy ids when CSV omits faction.
	if enemy_id.find("synthet") >= 0 or enemy_id.find("drone") >= 0:
		return EnemyData.FACTION_SYNTHET
	if enemy_id.find("chimera") >= 0:
		return EnemyData.FACTION_CHIMERA
	return EnemyData.FACTION_HUMAN


func _normalize_tier(raw: String) -> String:
	match raw.strip_edges().to_lower():
		EnemyData.TIER_ELITE:
			return EnemyData.TIER_ELITE
		EnemyData.TIER_BOSS:
			return EnemyData.TIER_BOSS
		_:
			return EnemyData.TIER_NORMAL


func _normalize_role(raw: String, tier: String) -> String:
	var key := raw.strip_edges().to_lower()
	match key:
		EnemyData.ROLE_MINION, EnemyData.ROLE_DAMAGE, EnemyData.ROLE_SUPPORT, EnemyData.ROLE_BOSS:
			return key
		_:
			pass
	if tier == EnemyData.TIER_BOSS:
		return EnemyData.ROLE_BOSS
	return EnemyData.ROLE_DAMAGE
