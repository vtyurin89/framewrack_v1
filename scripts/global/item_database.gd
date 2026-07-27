extends Node
## Autoload: loads ItemData blueprints from res://data/items.csv.
## Resolves type / rarity / trait references and optional merchant `price`.

const ITEMS_CSV_PATH := "res://data/items.csv"
const TYPE_DIR := "res://resources/item_types/"
const RARITY_DIR := "res://resources/rarities/"
const TRAIT_CATALOG_PATH := "res://data/trait_catalog.csv"

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
	if not FileAccess.file_exists(TRAIT_CATALOG_PATH):
		return
	var file := FileAccess.open(TRAIT_CATALOG_PATH, FileAccess.READ)
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

	var rarity_id := _cell(row, col, "rarity_id")
	if rarity_id.is_empty():
		rarity_id = _cell(row, col, "rarity")
	item.rarity = _resolve_rarity(rarity_id)

	var width := _parse_int(_cell(row, col, "width"), 1)
	var height := _parse_int(_cell(row, col, "height"), 1)
	item.size = Vector2i(maxi(width, 1), maxi(height, 1))

	item.requires_edge = _parse_bool(_cell(row, col, "is_edge_only"))
	if _cell(row, col, "is_edge_only").is_empty():
		item.requires_edge = _parse_bool(_cell(row, col, "requires_edge"))

	item.usable = _parse_bool(_cell(row, col, "usable"), true)
	item.ap_cost = _parse_int(_cell(row, col, "ap_cost"), 0)
	item.base_damage = _parse_int(_cell(row, col, "base_damage"), 0)
	item.base_armor = _parse_int(_cell(row, col, "base_armor"), 0)
	## Keep legacy combat fields aligned for existing combat code paths.
	item.damage = item.base_damage
	item.block_amount = item.base_armor

	item.target_type = _parse_target_type(_cell(row, col, "target_type"))
	item.uses_per_turn = _parse_int(_cell(row, col, "uses_per_turn"), -1)

	var exhaust_raw := _cell(row, col, "exhaustable")
	if exhaust_raw.is_empty():
		exhaust_raw = _cell(row, col, "consumable")
	item.consumable = _parse_bool(exhaust_raw, false)
	item.max_charges = _parse_int(_cell(row, col, "max_charges"), 0)
	item.destroy_on_empty = _parse_bool(_cell(row, col, "destroy_on_empty"), false)
	item.initialize_runtime_state()

	item.price = _parse_price(_cell(row, col, "price"))

	item.traits = _parse_traits(_cell(row, col, "traits"))

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
