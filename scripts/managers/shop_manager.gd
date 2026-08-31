extends Node
## Merchant shop session: stock generation, pricing, and purchases (autoload).

signal shop_session_begun(items: Array)
signal shop_session_cleared
signal item_purchased(item: ItemData, price: int)
signal purchase_failed(reason_key: String)

const STOCK_COUNT := 6
const PRICE_LIST := 1.0
const PRICE_DISCOUNT := 0.8
const PRICE_MARKUP := 1.25
const VIP_CARD_ID := "FAKE_VIP_CARD_GOLD_PARTNER"

## Same starter / story items RewardManager keeps out of combat loot.
const EXCLUDED_SHOP_IDS: Array[String] = [
	"SCRAP_PIPE",
	"HEAVY_SCRAP_PLATE",
	"EYE_OF_PALE_MAIDEN",
	"SLIMY_PARASITE",
	"NEURO_TICK",
	"BROKEN_SLOT",
]

var price_multiplier: float = PRICE_LIST
var stock_items: Array[ItemData] = []
## instance_id -> final shop price for current stock.
var _stock_prices: Dictionary = {}
var _active: bool = false


func is_active() -> bool:
	return _active


func is_vip_card_equipped(inventory: InventoryController) -> bool:
	## Fake VIP Card forces Bonnie's Good Mood while it sits in the Body Grid.
	if inventory == null:
		return false
	if StatCheckManager != null:
		return StatCheckManager.inventory_has_item(inventory, VIP_CARD_ID)
	if inventory.grid == null:
		return false
	var needle := VIP_CARD_ID.strip_edges().to_upper()
	for placed: PlacedItem in inventory.grid.items:
		if placed == null or placed.data == null:
			continue
		if placed.data.id.strip_edges().to_upper() == needle:
			return true
	return false


func clear_session() -> void:
	_active = false
	price_multiplier = PRICE_LIST
	stock_items.clear()
	_stock_prices.clear()
	shop_session_cleared.emit()


func begin_session(items: Array[ItemData], multiplier: float = PRICE_LIST) -> void:
	clear_session()
	price_multiplier = multiplier if multiplier > 0.0 else PRICE_LIST
	_active = true
	for item in items:
		if item == null:
			continue
		stock_items.append(item)
		_stock_prices[item.get_instance_id()] = calc_shop_price(
			item.get_price_value(), price_multiplier
		)
	shop_session_begun.emit(stock_items)


func generate_stock(act: int, count: int = STOCK_COUNT) -> Array[ItemData]:
	## Sellable non-harmful items; rarity weights shift slightly by act.
	var depth := maxi(act, 1)
	var w_common := 0.55
	var w_uncommon := 0.30
	var w_rare := 0.12
	var w_very_rare := 0.03
	var shift := 0.02 * float(depth - 1)
	var take := mini(shift * 2.0, w_common)
	if take > 0.0:
		w_common -= take
		w_uncommon += take * 0.5
		w_rare += take * 0.35
		w_very_rare += take * 0.15

	var out: Array[ItemData] = []
	var used_ids: Dictionary = {}
	var target := maxi(1, count)
	var guard := 0
	while out.size() < target and guard < target * 8:
		guard += 1
		var tier := _roll_tier(w_common, w_uncommon, w_rare, w_very_rare)
		var want_consumable := out.size() < 2 or randf() < 0.28
		var item := _pick_shop_item_of_tier(tier, want_consumable, used_ids)
		if item == null and want_consumable:
			item = _pick_shop_item_of_tier(tier, false, used_ids)
		if item == null:
			continue
		out.append(item)
		used_ids[item.id.strip_edges().to_upper()] = true
	out.shuffle()
	return out


func calc_shop_price(base_price: int, multiplier: float = -1.0) -> int:
	var mult := price_multiplier if multiplier < 0.0 else multiplier
	if mult <= 0.0:
		mult = PRICE_LIST
	return maxi(1, int(ceil(float(maxi(0, base_price)) * mult)))


func is_shop_stock(item: ItemData) -> bool:
	if item == null:
		return false
	return _stock_prices.has(item.get_instance_id())


func get_item_price(item: ItemData) -> int:
	if item == null:
		return 0
	return int(_stock_prices.get(item.get_instance_id(), 0))


func can_purchase(item: ItemData) -> bool:
	if not _active or item == null or not is_shop_stock(item):
		return false
	var price := get_item_price(item)
	var chips := GameManager.get_chips() if GameManager != null else 0
	return chips >= price


func try_purchase(item: ItemData) -> bool:
	## Spend chips and remove the listing. Caller places the item in the Body Grid.
	if not can_purchase(item):
		purchase_failed.emit("KEY_SHOP_NOT_ENOUGH_CHIPS")
		return false
	var id := item.get_instance_id()
	var price := int(_stock_prices.get(id, 0))
	if price > 0:
		if GameManager == null or not GameManager.spend_chips(price):
			purchase_failed.emit("KEY_SHOP_NOT_ENOUGH_CHIPS")
			return false
	_stock_prices.erase(id)
	var keep: Array[ItemData] = []
	for stock_item in stock_items:
		if stock_item != item:
			keep.append(stock_item)
	stock_items = keep
	item_purchased.emit(item, price)
	return true


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


func _pick_shop_item_of_tier(
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
		if not _is_shop_eligible(proto):
			continue
		if used_ids.has(proto.id.strip_edges().to_upper()):
			continue
		if want_consumable != _is_consumable_proto(proto):
			continue
		if proto.rarity.get_tier() == tier:
			pool.append(proto)
	if pool.is_empty():
		if tier == ItemRarityData.Tier.VERY_RARE:
			return _pick_shop_item_of_tier(ItemRarityData.Tier.RARE, want_consumable, used_ids)
		if tier == ItemRarityData.Tier.RARE:
			return _pick_shop_item_of_tier(ItemRarityData.Tier.UNCOMMON, want_consumable, used_ids)
		if tier == ItemRarityData.Tier.UNCOMMON:
			return _pick_shop_item_of_tier(ItemRarityData.Tier.COMMON, want_consumable, used_ids)
		return _pick_any_shop_matching(want_consumable, used_ids)
	var pick: ItemData = pool[randi() % pool.size()]
	return ItemDatabase.create_instance(pick.id)


func _pick_any_shop_matching(want_consumable: bool, used_ids: Dictionary = {}) -> ItemData:
	if ItemDatabase == null:
		return null
	var pool: Array[ItemData] = []
	for proto: ItemData in ItemDatabase.get_all_items():
		if proto == null:
			continue
		if not _is_shop_eligible(proto):
			continue
		if used_ids.has(proto.id.strip_edges().to_upper()):
			continue
		if want_consumable != _is_consumable_proto(proto):
			continue
		pool.append(proto)
	if pool.is_empty():
		for proto2: ItemData in ItemDatabase.get_all_items():
			if proto2 == null or not _is_shop_eligible(proto2):
				continue
			if used_ids.has(proto2.id.strip_edges().to_upper()):
				continue
			pool.append(proto2)
	if pool.is_empty():
		return null
	var pick: ItemData = pool[randi() % pool.size()]
	return ItemDatabase.create_instance(pick.id)


func _is_shop_eligible(proto: ItemData) -> bool:
	if proto == null:
		return false
	if proto.is_currency() or proto.is_harmful_item():
		return false
	if EXCLUDED_SHOP_IDS.has(proto.id.strip_edges().to_upper()):
		return false
	if proto.rarity != null and proto.rarity.get_tier() == ItemRarityData.Tier.BOSS:
		return false
	return proto.is_sellable()


func _is_consumable_proto(proto: ItemData) -> bool:
	if proto == null:
		return false
	if proto.consumable:
		return true
	if proto.item_type != null and proto.item_type.id.strip_edges().to_upper() == "CONSUMABLE":
		return true
	return false
