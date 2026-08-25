extends Node
## Post-combat / chest loot generation and pick tracking (autoload).

signal rewards_generated(items: Array)
signal pick_limit_reached
signal rewards_session_cleared

const MAX_PICKS := 3
const CHEST_PICKS := 1
const CHEST_OFFER_COUNT := 3
## Starter loadout — never offered as combat loot.
const EXCLUDED_LOOT_IDS: Array[String] = [
	"SCRAP_PIPE",
	"HEAVY_SCRAP_PLATE",
	"EYE_OF_PALE_MAIDEN",
	"SLIMY_PARASITE",
	"NEURO_TICK",
	"BROKEN_SLOT",
	"LOCKPICK",
]

var initial_generated_items: Array[ItemData] = []
var picked_new_items_count: int = 0
var session_max_picks: int = MAX_PICKS
## Instance ids of new loot currently sitting in the inventory.
var _picked_instance_ids: Dictionary = {}


func clear_session() -> void:
	initial_generated_items.clear()
	picked_new_items_count = 0
	session_max_picks = MAX_PICKS
	_picked_instance_ids.clear()
	rewards_session_cleared.emit()


func begin_session(items: Array[ItemData], max_picks: int = MAX_PICKS) -> void:
	clear_session()
	session_max_picks = maxi(1, max_picks)
	for item in items:
		if item != null:
			initial_generated_items.append(item)
	rewards_generated.emit(initial_generated_items)


func generate_rewards(encounter_type: String, act_depth: int) -> Array[ItemData]:
	var kind := encounter_type.strip_edges().to_upper()
	## Count is fixed for all encounters; only rarity weights differ.
	var count := randi_range(5, 6)
	var consumable_count := randi_range(1, 2)
	var w_common := 0.68
	var w_uncommon := 0.24
	var w_rare := 0.07
	var w_very_rare := 0.01
	match kind:
		"ELITE", "COMBAT_ELITE":
			w_common = 0.28
			w_uncommon = 0.48
			w_rare = 0.20
			w_very_rare = 0.04
		"BOSS", "COMBAT_BOSS":
			w_common = 0.0
			w_uncommon = 0.50
			w_rare = 0.38
			w_very_rare = 0.12
		_:
			## NORMAL / COMBAT_NORMAL / default
			w_common = 0.68
			w_uncommon = 0.24
			w_rare = 0.07
			w_very_rare = 0.01

	## Act depth: +2% uncommon and +2% rare+ per layer, taken from common.
	var depth := maxi(act_depth, 0)
	var shift := 0.02 * float(depth)
	var take := mini(shift * 2.0, w_common)
	if take > 0.0:
		w_common -= take
		w_uncommon += take * 0.5
		w_rare += take * 0.35
		w_very_rare += take * 0.15

	consumable_count = mini(consumable_count, count)
	var gear_count := count - consumable_count

	var out: Array[ItemData] = []
	var used_ids: Dictionary = {}
	for _i in consumable_count:
		var tier := _roll_tier(w_common, w_uncommon, w_rare, w_very_rare)
		var item := _pick_random_item_of_tier(tier, true, used_ids)
		if item != null:
			out.append(item)
			used_ids[item.id.strip_edges().to_upper()] = true
	for _i in gear_count:
		var tier := _roll_tier(w_common, w_uncommon, w_rare, w_very_rare)
		var item := _pick_random_item_of_tier(tier, false, used_ids)
		if item != null:
			out.append(item)
			used_ids[item.id.strip_edges().to_upper()] = true

	## Shuffle so consumables aren't always first in the Space layout.
	out.shuffle()
	return out


func generate_chest_rewards(act_depth: int) -> Array[ItemData]:
	## High-tier map chest: exactly 3 non-common gear offers (no consumables / lockpicks).
	var w_common := 0.0
	var w_uncommon := 0.28
	var w_rare := 0.42
	var w_very_rare := 0.30
	var depth := maxi(act_depth, 0)
	var shift := 0.015 * float(depth)
	var take := mini(shift, w_uncommon)
	if take > 0.0:
		w_uncommon -= take
		w_rare += take * 0.4
		w_very_rare += take * 0.6

	var out: Array[ItemData] = []
	var used_ids: Dictionary = {}
	for _i in CHEST_OFFER_COUNT:
		var tier := _roll_tier(w_common, w_uncommon, w_rare, w_very_rare)
		var item := _pick_chest_item_of_tier(tier, used_ids)
		if item != null:
			out.append(item)
			used_ids[item.id.strip_edges().to_upper()] = true
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
	return picked_new_items_count < session_max_picks


func notify_new_item_picked(item: ItemData) -> bool:
	if item == null or not is_new_loot(item):
		return true
	var id := item.get_instance_id()
	if _picked_instance_ids.has(id):
		return true
	if picked_new_items_count >= session_max_picks:
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


func _roll_tier(
	w_common: float, w_uncommon: float, w_rare: float, w_very_rare: float = 0.0
) -> ItemRarityData.Tier:
	var total := w_common + w_uncommon + w_rare + w_very_rare
	if total <= 0.0:
		return ItemRarityData.Tier.COMMON
	var roll := randf() * total
	if roll < w_common:
		return ItemRarityData.Tier.COMMON
	roll -= w_common
	if roll < w_uncommon:
		return ItemRarityData.Tier.UNCOMMON
	roll -= w_uncommon
	if roll < w_rare:
		return ItemRarityData.Tier.RARE
	return ItemRarityData.Tier.VERY_RARE


func _pick_random_item_of_tier(
	tier: ItemRarityData.Tier,
	want_consumable: bool,
	used_ids: Dictionary = {}
) -> ItemData:
	if ItemDatabase == null:
		return null
	var pool: Array[ItemData] = []
	for proto: ItemData in ItemDatabase.get_all_items():
		if proto == null or proto.rarity == null:
			continue
		if proto.is_currency() or proto.is_harmful_item():
			continue
		if _is_excluded_loot(proto.id):
			continue
		if used_ids.has(proto.id.strip_edges().to_upper()):
			continue
		if want_consumable != _is_consumable_proto(proto):
			continue
		if proto.rarity.get_tier() == tier:
			pool.append(proto)
	if pool.is_empty():
		## Soft fallback down the rarity ladder (same consumable/gear filter).
		if tier == ItemRarityData.Tier.VERY_RARE:
			return _pick_random_item_of_tier(ItemRarityData.Tier.RARE, want_consumable, used_ids)
		if tier == ItemRarityData.Tier.RARE:
			return _pick_random_item_of_tier(ItemRarityData.Tier.UNCOMMON, want_consumable, used_ids)
		if tier == ItemRarityData.Tier.UNCOMMON:
			return _pick_random_item_of_tier(ItemRarityData.Tier.COMMON, want_consumable, used_ids)
		## Last resort: any matching category, ignore rarity.
		return _pick_any_matching(want_consumable, used_ids)
	var pick: ItemData = pool[randi() % pool.size()]
	return ItemDatabase.create_instance(pick.id)


func _pick_chest_item_of_tier(tier: ItemRarityData.Tier, used_ids: Dictionary) -> ItemData:
	## Chest loot: gear only, never common / consumable / quest tools.
	if ItemDatabase == null:
		return null
	var pool: Array[ItemData] = []
	for proto: ItemData in ItemDatabase.get_all_items():
		if not _is_chest_eligible(proto, used_ids):
			continue
		if proto.rarity != null and proto.rarity.get_tier() == tier:
			pool.append(proto)
	if pool.is_empty():
		if tier == ItemRarityData.Tier.VERY_RARE:
			return _pick_chest_item_of_tier(ItemRarityData.Tier.RARE, used_ids)
		if tier == ItemRarityData.Tier.RARE:
			return _pick_chest_item_of_tier(ItemRarityData.Tier.UNCOMMON, used_ids)
		## Absolute fallback: any eligible chest item.
		for proto2: ItemData in ItemDatabase.get_all_items():
			if _is_chest_eligible(proto2, used_ids):
				pool.append(proto2)
		if pool.is_empty():
			return null
	var pick: ItemData = pool[randi() % pool.size()]
	return ItemDatabase.create_instance(pick.id)


func _is_chest_eligible(proto: ItemData, used_ids: Dictionary) -> bool:
	if proto == null:
		return false
	if proto.is_currency() or proto.is_harmful_item():
		return false
	if proto.is_quest_item():
		return false
	if _is_consumable_proto(proto):
		return false
	if _is_excluded_loot(proto.id):
		return false
	if used_ids.has(proto.id.strip_edges().to_upper()):
		return false
	if proto.rarity != null and proto.rarity.get_tier() == ItemRarityData.Tier.COMMON:
		return false
	return true


func _pick_any_matching(want_consumable: bool, used_ids: Dictionary = {}) -> ItemData:
	if ItemDatabase == null:
		return null
	var pool: Array[ItemData] = []
	for proto: ItemData in ItemDatabase.get_all_items():
		if proto == null:
			continue
		if proto.is_currency() or proto.is_harmful_item():
			continue
		if _is_excluded_loot(proto.id):
			continue
		if used_ids.has(proto.id.strip_edges().to_upper()):
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


func generate_rare_offer(count: int = 3) -> Array[ItemData]:
	## Dialog reward: N distinct RARE / VERY_RARE gear items (pick subset in UI).
	var out: Array[ItemData] = []
	var used: Dictionary = {}
	var n := maxi(1, count)
	for _i in n:
		var item := _pick_rare_or_better_gear(used)
		if item == null:
			break
		out.append(item)
		used[item.id.strip_edges().to_upper()] = true
	return out


func generate_rare_weapon() -> ItemData:
	return _pick_typed_rare_or_better(["WEAPON"], {})


func generate_rare_module() -> ItemData:
	return _pick_typed_rare_or_better(["AMPLIFIER", "ACTIVE_MODULE", "IMPLANT"], {})


func ensure_at_least_one_rare(items: Array[ItemData]) -> Array[ItemData]:
	## Elite dialog combat: guarantee ≥1 RARE / VERY_RARE in the offer.
	for item in items:
		if item != null and item.rarity != null:
			var tier := item.rarity.get_tier()
			if tier == ItemRarityData.Tier.RARE or tier == ItemRarityData.Tier.VERY_RARE:
				return items
	var used: Dictionary = {}
	for item2 in items:
		if item2 != null:
			used[item2.id.strip_edges().to_upper()] = true
	var rare := _pick_rare_or_better_gear(used)
	if rare == null:
		return items
	var out: Array[ItemData] = items.duplicate()
	if out.is_empty():
		out.append(rare)
	else:
		out[0] = rare
	out.shuffle()
	return out


func _pick_rare_or_better_gear(used_ids: Dictionary) -> ItemData:
	var roll := randf()
	var tier := ItemRarityData.Tier.RARE if roll < 0.78 else ItemRarityData.Tier.VERY_RARE
	var item := _pick_random_item_of_tier(tier, false, used_ids)
	if item == null:
		item = _pick_random_item_of_tier(ItemRarityData.Tier.RARE, false, used_ids)
	return item


func _pick_typed_rare_or_better(type_ids: Array[String], used_ids: Dictionary) -> ItemData:
	if ItemDatabase == null:
		return null
	var allowed: Dictionary = {}
	for tid in type_ids:
		allowed[tid.strip_edges().to_upper()] = true
	var rare_pool: Array[ItemData] = []
	var vr_pool: Array[ItemData] = []
	for proto: ItemData in ItemDatabase.get_all_items():
		if proto == null or proto.item_type == null or proto.rarity == null:
			continue
		if proto.is_currency() or proto.is_harmful_item():
			continue
		if _is_excluded_loot(proto.id):
			continue
		if used_ids.has(proto.id.strip_edges().to_upper()):
			continue
		var type_key := proto.item_type.id.strip_edges().to_upper()
		if not allowed.has(type_key):
			continue
		var tier := proto.rarity.get_tier()
		if tier == ItemRarityData.Tier.VERY_RARE:
			vr_pool.append(proto)
		elif tier == ItemRarityData.Tier.RARE:
			rare_pool.append(proto)
	var pool: Array[ItemData] = rare_pool
	if randf() < 0.22 and not vr_pool.is_empty():
		pool = vr_pool
	elif pool.is_empty():
		pool = vr_pool
	if pool.is_empty():
		## Soft fallback: any matching type.
		for proto2: ItemData in ItemDatabase.get_all_items():
			if proto2 == null or proto2.item_type == null:
				continue
			if allowed.has(proto2.item_type.id.strip_edges().to_upper()):
				if not _is_excluded_loot(proto2.id) and not used_ids.has(proto2.id.strip_edges().to_upper()):
					pool.append(proto2)
	if pool.is_empty():
		return null
	var pick: ItemData = pool[randi() % pool.size()]
	return ItemDatabase.create_instance(pick.id)
