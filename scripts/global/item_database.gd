extends Node
## Autoload: loads ItemData blueprints from res://data/items.csv.
## Resolves type / rarity / trait references and optional merchant `price`.

const ITEMS_CSV_PATH := "res://data/items.csv"
const TYPE_DIR := "res://resources/item_types/"
const RARITY_DIR := "res://resources/rarities/"
const TRAIT_CATALOG_PATH := "res://data/traits.csv"
const TRAIT_CATALOG_FALLBACK_PATH := "res://data/trait_catalog.csv"

var _items_by_id: Dictionary = {}  # String -> ItemData
var _types_by_id: Dictionary = {}  # String -> ItemTypeData
var _rarities_by_id: Dictionary = {}  # String -> ItemRarityData
var _traits_by_id: Dictionary = {}  # String -> TraitData


func _ready() -> void:
	_index_types()
	_index_rarities()
	_index_traits_from_catalog()
	reload()


func reload() -> void:
	_items_by_id.clear()
	_load_items_csv(ITEMS_CSV_PATH)


func get_item(item_id: String) -> ItemData:
	return _items_by_id.get(item_id, null)


func has_item(item_id: String) -> bool:
	return _items_by_id.has(item_id)


func get_all_items() -> Array[ItemData]:
	var result: Array[ItemData] = []
	for item: ItemData in _items_by_id.values():
		result.append(item)
	return result


func create_instance(item_id: String) -> ItemData:
	## Deep duplicate so runtime state (charges / trait activity) is per-instance.
	var proto: ItemData = get_item(item_id)
	if proto == null:
		push_warning("ItemDatabase: unknown item id '%s'" % item_id)
		return null
	var instance := proto.duplicate(true) as ItemData
	if instance:
		instance.initialize_runtime_state()
	return instance


func build_choice_pool(pool_id: String) -> Array:
	## Returns ItemData prototypes (not instances) for SelectItemUI / reward stubs.
	var result: Array = []
	var key := pool_id.strip_edges().to_lower()
	match key:
		"uncommon_weapon":
			for item: ItemData in get_all_items():
				if item == null or item.item_type == null or item.rarity == null:
					continue
				if item.item_type.id.strip_edges().to_upper() != "WEAPON":
					continue
				if item.rarity.id.strip_edges().to_upper() != "UNCOMMON":
					continue
				result.append(item)
		"grenade", "grenades":
			for item: ItemData in get_all_items():
				if item == null or item.item_type == null:
					continue
				if item.item_type.id.strip_edges().to_upper() != "CONSUMABLE":
					continue
				## Explosives / thrown charges: damaging consumables aimed at enemies.
				if item.target_type == ItemData.TargetType.SINGLE_ENEMY and item.max_damage > 0:
					result.append(item)
			if result.is_empty():
				var thermite := get_item("THERMITE_CHARGE")
				if thermite != null:
					result.append(thermite)
		"combat_loot", "post_combat":
			for item_id in ["RUSTY_CHAIN", "BIO_GEL", "SALT_INJECTOR", "REBEL_CLEAVER"]:
				var item := get_item(item_id)
				if item != null:
					result.append(item)
		_:
			## Explicit CSV ids or unknown keys fall back to empty.
			pass
	return result


func _parse_target_type(raw: String) -> ItemData.TargetType:
	match raw.strip_edges().to_upper():
		"SELF":
			return ItemData.TargetType.SELF
		"ALL_ENEMIES":
			return ItemData.TargetType.ALL_ENEMIES
		"SINGLE_ENEMY", "":
			return ItemData.TargetType.SINGLE_ENEMY
		_:
			push_warning("ItemDatabase: unknown target_type '%s', defaulting to SINGLE_ENEMY" % raw)
			return ItemData.TargetType.SINGLE_ENEMY


func _parse_stat_scaling(raw: String, item: ItemData) -> ItemData.StatScaling:
	match raw.strip_edges().to_upper():
		"STR", "STRENGTH":
			return ItemData.StatScaling.STRENGTH
		"AGI", "AGILITY":
			return ItemData.StatScaling.AGILITY
		"INT", "INTELLIGENCE":
			return ItemData.StatScaling.INTELLIGENCE
		"END", "ENDURANCE":
			return ItemData.StatScaling.ENDURANCE
		"LCK", "LUCK":
			return ItemData.StatScaling.LUCK
		"NONE":
			return ItemData.StatScaling.NONE
		"":
			## Infer defaults when CSV omits the column.
			if item != null and item.max_damage > 0 and item.is_weapon():
				return ItemData.StatScaling.STRENGTH
			if item != null and item.base_armor > 0 and item.is_armor():
				return ItemData.StatScaling.AGILITY
			return ItemData.StatScaling.NONE
		_:
			push_warning("ItemDatabase: unknown scaling_stat '%s'" % raw)
			return ItemData.StatScaling.NONE


# ---------------------------------------------------------------------------
# Catalog indexing
# ---------------------------------------------------------------------------

func _index_types() -> void:
	_types_by_id.clear()
	for path in _list_tres(TYPE_DIR):
		var res: Resource = load(path)
		if res is ItemTypeData:
			var typed := res as ItemTypeData
			if not typed.id.is_empty():
				_types_by_id[typed.id.to_lower()] = typed
				_types_by_id[typed.id.to_upper()] = typed


func _index_rarities() -> void:
	_rarities_by_id.clear()
	for path in _list_tres(RARITY_DIR):
		var res: Resource = load(path)
		if res is ItemRarityData:
			var typed := res as ItemRarityData
			if not typed.id.is_empty():
				_rarities_by_id[typed.id.to_lower()] = typed
				_rarities_by_id[typed.id.to_upper()] = typed


func _index_traits_from_catalog() -> void:
	_traits_by_id.clear()
	var source_path := TRAIT_CATALOG_PATH
	if not FileAccess.file_exists(source_path):
		source_path = TRAIT_CATALOG_FALLBACK_PATH
	if not FileAccess.file_exists(source_path):
		return
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return
	var header: PackedStringArray = file.get_csv_line()
	var col: Dictionary = _header_map(header)
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.is_empty() or (row.size() == 1 and str(row[0]).strip_edges().is_empty()):
			continue
		var trait_id := _cell(row, col, "id").strip_edges()
		if trait_id.is_empty():
			continue
		var trait_data := TraitData.new()
		trait_data.id = trait_id
		trait_data.trait_name_key = _cell(row, col, "name_key")
		trait_data.description = _cell(row, col, "desc_key")
		trait_data.effect_target = _cell(row, col, "effect_target")
		trait_data.effect_value = _parse_int(_cell(row, col, "effect_value"), 0)
		_traits_by_id[trait_id] = trait_data
		_traits_by_id[trait_id.to_upper()] = trait_data


func _list_tres(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".tres"):
			out.append(dir_path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	return out


# ---------------------------------------------------------------------------
# CSV items
# ---------------------------------------------------------------------------

func _load_items_csv(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("ItemDatabase: missing %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ItemDatabase: cannot open %s" % path)
		return

	var header: PackedStringArray = file.get_csv_line()
	var col: Dictionary = _header_map(header)

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.is_empty() or (row.size() == 1 and str(row[0]).strip_edges().is_empty()):
			continue
		var item := _parse_item_row(row, col)
		if item != null and not item.id.is_empty():
			_items_by_id[item.id] = item


func _parse_item_row(row: PackedStringArray, col: Dictionary) -> ItemData:
	var item := ItemData.new()
	item.id = _cell(row, col, "id").strip_edges()
	if item.id.is_empty():
		return null

	item.item_name_key = _cell(row, col, "name_key")
	item.item_desc_key = _cell(row, col, "desc_key")
	item.display_name = item.id.capitalize().replace("_", " ")

	var type_id := _cell(row, col, "item_type_id")
	if type_id.is_empty():
		type_id = _cell(row, col, "item_type")
	item.item_type = _resolve_type(type_id)
	item.sub_type = _cell(row, col, "sub_type").strip_edges().to_upper()

	var rarity_id := _cell(row, col, "rarity_id")
	if rarity_id.is_empty():
		rarity_id = _cell(row, col, "rarity")
	item.rarity = _resolve_rarity(rarity_id)

	var width := _parse_int(_cell(row, col, "width"), 1)
	var height := _parse_int(_cell(row, col, "height"), 1)
	item.size = Vector2i(maxi(width, 1), maxi(height, 1))
	item.shape_offsets = _parse_shape_mask(_cell(row, col, "shape_mask"))
	if not item.shape_offsets.is_empty():
		## Keep bounding box in sync with the mask (CSV width/height should match).
		item.size = ItemData.bounding_size_of(item.shape_offsets)

	item.requires_edge = _parse_bool(_cell(row, col, "is_edge_only"))
	if _cell(row, col, "is_edge_only").is_empty():
		item.requires_edge = _parse_bool(_cell(row, col, "requires_edge"))

	item.usable = _parse_bool(_cell(row, col, "usable"), true)
	item.ap_cost = _parse_int(_cell(row, col, "ap_cost"), 0)
	## Prefer min/max columns; legacy base_damage → [base-1, base+1].
	var min_dmg_raw := _cell(row, col, "min_damage")
	var max_dmg_raw := _cell(row, col, "max_damage")
	var legacy_dmg := _parse_int(_cell(row, col, "base_damage"), 0)
	if min_dmg_raw.is_empty() and max_dmg_raw.is_empty() and legacy_dmg > 0:
		item.min_damage = maxi(0, legacy_dmg - 1)
		item.max_damage = legacy_dmg + 1
	else:
		item.min_damage = _parse_int(min_dmg_raw, 0)
		item.max_damage = _parse_int(max_dmg_raw, 0)
	if item.max_damage < item.min_damage:
		var swap: int = item.min_damage
		item.min_damage = item.max_damage
		item.max_damage = swap
	item.base_armor = _parse_int(_cell(row, col, "base_armor"), 0)
	item.scaling_stat = _parse_stat_scaling(_cell(row, col, "scaling_stat"), item)
	## Keep legacy combat fields aligned for existing combat code paths.
	item.damage = item.max_damage
	item.block_amount = item.base_armor
	item.dropable = _parse_bool(_cell(row, col, "dropable"), true)
	## Legacy CSV spelling.
	if _cell(row, col, "dropable").is_empty():
		item.dropable = _parse_bool(_cell(row, col, "droppable"), true)
	item.is_harmful = _parse_bool(_cell(row, col, "is_harmful"), false)
	if item.is_harmful:
		item.enforce_harmful_constraints()

	item.target_type = _parse_target_type(_cell(row, col, "target_type"))
	item.uses_per_turn = _parse_int(_cell(row, col, "uses_per_turn"), -1)
	item.uses_per_combat = _parse_int(_cell(row, col, "uses_per_combat"), -1)
	item.cooldown = maxi(0, _parse_int(_cell(row, col, "cooldown"), 0))

	var exhaust_raw := _cell(row, col, "exhaustable")
	if exhaust_raw.is_empty():
		exhaust_raw = _cell(row, col, "consumable")
	item.consumable = _parse_bool(exhaust_raw, false)
	item.max_charges = _parse_int(_cell(row, col, "max_charges"), 0)
	item.destroy_on_empty = _parse_bool(_cell(row, col, "destroy_on_empty"), false)
	item.is_stackable = _parse_bool(_cell(row, col, "is_stackable"), false)
	item.max_stack = maxi(1, _parse_int(_cell(row, col, "max_stack"), 99))
	item.current_stack = clampi(_parse_int(_cell(row, col, "current_stack"), 1), 1, item.max_stack)

	## Combat-only: explicit CSV, else infer for damaging enemy-targeted consumables.
	var combat_only_raw := _cell(row, col, "is_combat_only")
	if not combat_only_raw.is_empty():
		item.is_combat_only = _parse_bool(combat_only_raw, false)
	elif item.consumable and item.max_damage > 0 and item.target_type != ItemData.TargetType.SELF:
		item.is_combat_only = true
	else:
		item.is_combat_only = false

	item.initialize_runtime_state()

	item.price = _parse_price(_cell(row, col, "price"))

	item.traits = _parse_traits(_cell(row, col, "traits"))
	if item.uses_per_combat <= 0 and TraitManager.has_trait(item, "TRAIT_ORACLE_KILL_SCALING"):
		item.uses_per_combat = 1

	var icon_path := _cell(row, col, "icon_path")
	if icon_path.is_empty():
		icon_path = _cell(row, col, "sprite_path")
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		item.texture = load(icon_path) as Texture2D

	return item


func _parse_price(raw: String) -> Variant:
	## Empty / "null" / non-integer → null (unsellable). Valid ints keep their value.
	var cell := raw.strip_edges()
	if cell.is_empty():
		return null
	if cell.to_lower() == "null":
		return null
	if not cell.is_valid_int():
		return null
	return int(cell)


func _parse_shape_mask(raw: String) -> Array[Vector2i]:
	## Format: "0,0;1,0;0,1" — cell offsets relative to origin.
	var out: Array[Vector2i] = []
	var cell := raw.strip_edges()
	if cell.is_empty():
		return out
	for part in cell.split(";", false):
		var token := str(part).strip_edges()
		if token.is_empty():
			continue
		var xy := token.split(",", false)
		if xy.size() < 2:
			continue
		if not str(xy[0]).strip_edges().is_valid_int():
			continue
		if not str(xy[1]).strip_edges().is_valid_int():
			continue
		out.append(Vector2i(int(xy[0]), int(xy[1])))
	return ItemData.normalize_offsets(out)


func _parse_traits(raw: String) -> Array[TraitData]:
	var result: Array[TraitData] = []
	var cleaned := raw.strip_edges().trim_prefix("\"").trim_suffix("\"")
	if cleaned.is_empty():
		return result
	for part in cleaned.split(",", false):
		var trait_id := str(part).strip_edges()
		if trait_id.is_empty():
			continue
		var proto: TraitData = _traits_by_id.get(trait_id, _traits_by_id.get(trait_id.to_upper(), null))
		if proto != null:
			result.append(proto.duplicate(true) as TraitData)
		else:
			var stub := TraitData.new()
			stub.id = trait_id
			stub.trait_name_key = trait_id + "_NAME"
			result.append(stub)
	return result


func _resolve_type(type_id: String) -> ItemTypeData:
	var key := type_id.strip_edges()
	if key.is_empty():
		return null
	if _types_by_id.has(key):
		return _types_by_id[key]
	if _types_by_id.has(key.to_lower()):
		return _types_by_id[key.to_lower()]
	# CSV may use WEAPON while resource id is "weapon".
	if key.to_lower() == "weapon" and _types_by_id.has("weapon"):
		return _types_by_id["weapon"]
	return null


func _resolve_rarity(rarity_id: String) -> ItemRarityData:
	var key := rarity_id.strip_edges()
	if key.is_empty():
		return null
	if _rarities_by_id.has(key):
		return _rarities_by_id[key]
	if _rarities_by_id.has(key.to_lower()):
		return _rarities_by_id[key.to_lower()]
	return null


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


func _parse_int(raw: String, default_value: int = 0) -> int:
	var cell := raw.strip_edges()
	if cell.is_empty() or not cell.is_valid_int():
		return default_value
	return int(cell)


func _parse_bool(raw: String, default_value: bool = false) -> bool:
	var cell := raw.strip_edges().to_lower()
	if cell.is_empty():
		return default_value
	return cell in ["1", "true", "yes", "y"]
