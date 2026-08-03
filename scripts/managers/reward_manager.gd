extends Node
## Post-combat loot generation and pick tracking (autoload).

signal rewards_generated(items: Array)
signal pick_limit_reached
signal rewards_session_cleared

const MAX_PICKS := 3
## Starter loadout — never offered as combat loot.
const EXCLUDED_LOOT_IDS: Array[String] = ["SCRAP_PIPE", "HEAVY_SCRAP_PLATE"]

var initial_generated_items: Array[ItemData] = []
var picked_new_items_count: int = 0
## Instance ids of new loot currently sitting in the inventory.
var _picked_instance_ids: Dictionary = {}


func clear_session() -> void:
	initial_generated_items.clear()
	picked_new_items_count = 0
	_picked_instance_ids.clear()
	rewards_session_cleared.emit()


func begin_session(items: Array[ItemData]) -> void:
	clear_session()
	for item in items:
		if item != null:
			initial_generated_items.append(item)
	rewards_generated.emit(initial_generated_items)


func generate_rewards(encounter_type: String, act_depth: int) -> Array[ItemData]:
	var kind := encounter_type.strip_edges().to_upper()
	## Count is fixed for all encounters; only rarity weights differ.
	var count := randi_range(5, 6)
	var consumable_count := randi_range(1, 2)
	var w_common := 0.70
	var w_uncommon := 0.25
	var w_rare := 0.05
	match kind:
		"ELITE", "COMBAT_ELITE":
			w_common = 0.30
			w_uncommon = 0.50
			w_rare = 0.20
		"BOSS", "COMBAT_BOSS":
			w_common = 0.0
			w_uncommon = 0.60
			w_rare = 0.40
		_:
			## NORMAL / COMBAT_NORMAL / default
			w_common = 0.70
			w_uncommon = 0.25
			w_rare = 0.05

	## Act depth: +2% uncommon and +2% rare per layer, taken from common.
	var depth := maxi(act_depth, 0)
	var shift := 0.02 * float(depth)
	var take := mini(shift * 2.0, w_common)
	if take > 0.0:
		w_common -= take
		w_uncommon += take * 0.5
		w_rare += take * 0.5

	consumable_count = mini(consumable_count, count)
	var gear_count := count - consumable_count

	var out: Array[ItemData] = []
	for _i in consumable_count:
		var tier := _roll_tier(w_common, w_uncommon, w_rare)
		var item := _pick_random_item_of_tier(tier, true)
		if item != null:
			out.append(item)
	for _i in gear_count:
		var tier := _roll_tier(w_common, w_uncommon, w_rare)
		var item := _pick_random_item_of_tier(tier, false)
		if item != null:
			out.append(item)

	## Shuffle so consumables aren't always first in the Space layout.
	out.shuffle()
	return out


func is_new_loot(item: ItemData) -> bool:
	if item == null:
		return false
	for offered in initial_generated_items:
		if offered == item:
			return true
	return false


func can_pick_new_item(item: ItemData) -> bool:
	if not is_new_loot(item):
		return true
	var id := item.get_instance_id()
	if _picked_instance_ids.has(id):
		return true
	return picked_new_items_count < MAX_PICKS


func notify_new_item_picked(item: ItemData) -> bool:
	if item == null or not is_new_loot(item):
		return true
	var id := item.get_instance_id()
	if _picked_instance_ids.has(id):
		return true
	if picked_new_items_count >= MAX_PICKS:
		pick_limit_reached.emit()
		return false
	_picked_instance_ids[id] = true
	picked_new_items_count += 1
	return true


func notify_new_item_unpicked(item: ItemData) -> void:
	if item == null or not is_new_loot(item):
		return
	var id := item.get_instance_id()
	if not _picked_instance_ids.has(id):
		return
	_picked_instance_ids.erase(id)
	picked_new_items_count = maxi(0, picked_new_items_count - 1)


func _roll_tier(w_common: float, w_uncommon: float, w_rare: float) -> ItemRarityData.Tier:
	var total := w_common + w_uncommon + w_rare
	if total <= 0.0:
		return ItemRarityData.Tier.COMMON
	var roll := randf() * total
	if roll < w_common:
		return ItemRarityData.Tier.COMMON
	roll -= w_common
	if roll < w_uncommon:
		return ItemRarityData.Tier.UNCOMMON
	return ItemRarityData.Tier.RARE


func _pick_random_item_of_tier(tier: ItemRarityData.Tier, want_consumable: bool) -> ItemData:
	if ItemDatabase == null:
		return null
	var pool: Array[ItemData] = []
	for proto: ItemData in ItemDatabase.get_all_items():
		if proto == null or proto.rarity == null:
			continue
		if proto.is_currency():
			continue
		if _is_excluded_loot(proto.id):
			continue
		if want_consumable != _is_consumable_proto(proto):
			continue
		if proto.rarity.get_tier() == tier:
			pool.append(proto)
	if pool.is_empty():
		## Soft fallback down the rarity ladder (same consumable/gear filter).
		if tier == ItemRarityData.Tier.RARE:
			return _pick_random_item_of_tier(ItemRarityData.Tier.UNCOMMON, want_consumable)
		if tier == ItemRarityData.Tier.UNCOMMON:
			return _pick_random_item_of_tier(ItemRarityData.Tier.COMMON, want_consumable)
		## Last resort: any matching category, ignore rarity.
		return _pick_any_matching(want_consumable)
	var pick: ItemData = pool[randi() % pool.size()]
	return ItemDatabase.create_instance(pick.id)


func _pick_any_matching(want_consumable: bool) -> ItemData:
	if ItemDatabase == null:
		return null
	var pool: Array[ItemData] = []
	for proto: ItemData in ItemDatabase.get_all_items():
		if proto == null:
			continue
		if proto.is_currency():
			continue
		if _is_excluded_loot(proto.id):
			continue
		if want_consumable != _is_consumable_proto(proto):
			continue
		pool.append(proto)
	if pool.is_empty():
		return null
	var pick: ItemData = pool[randi() % pool.size()]
	return ItemDatabase.create_instance(pick.id)


func _is_excluded_loot(item_id: String) -> bool:
	var key := item_id.strip_edges().to_upper()
	return EXCLUDED_LOOT_IDS.has(key)


func _is_consumable_proto(proto: ItemData) -> bool:
	if proto == null:
		return false
	if proto.consumable:
		return true
	if proto.item_type != null and proto.item_type.id.strip_edges().to_upper() == "CONSUMABLE":
		return true
	return false
