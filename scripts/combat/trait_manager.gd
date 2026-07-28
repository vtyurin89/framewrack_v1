class_name TraitManager
extends RefCounted
## Central trait helpers for combat-time effects.

const BURN_APPLY_STACKS := 3


static func has_trait(item: ItemData, trait_id: String) -> bool:
	if item == null:
		return false
	var wanted := trait_id.strip_edges().to_upper()
	for item_trait: TraitData in item.traits:
		if item_trait == null:
			continue
		if item_trait.id.strip_edges().to_upper() == wanted:
			return true
	return false


static func get_trait_value(item: ItemData, trait_id: String, fallback: int = 0) -> int:
	if item == null:
		return fallback
	var wanted := trait_id.strip_edges().to_upper()
	for item_trait: TraitData in item.traits:
		if item_trait == null:
			continue
		if item_trait.id.strip_edges().to_upper() == wanted:
			return item_trait.effect_value
	return fallback


static func activate_armor_core(
	core: PlacedItem,
	grid: BodyGrid,
	gain_block: Callable
) -> void:
	## Armor Core: grant own armor, then auto-trigger adjacent usable ARMOR modules.
	if core == null or core.data == null or grid == null or not gain_block.is_valid():
		return
	var core_armor := maxi(2, _effective_armor(core.data))
	gain_block.call(core_armor, core.data.get_localized_name())
	for neighbour: PlacedItem in grid.get_adjacent_items(core):
		if neighbour == null or neighbour.data == null:
			continue
		if not grid.is_item_functional(neighbour):
			continue
		if not neighbour.data.is_armor() or not neighbour.data.usable:
			continue
		if neighbour.data == core.data:
			continue
		var armor := _effective_armor(neighbour.data)
		gain_block.call(armor, "%s*" % neighbour.data.get_localized_name())


static func apply_passive_armor_from_spatial_traits(
	grid: BodyGrid,
	gain_block: Callable
) -> void:
	## Helmets / leg armor passives grant armor at player turn start.
	if grid == null or not gain_block.is_valid():
		return
	for placed: PlacedItem in grid.items:
		if placed == null or placed.data == null:
			continue
		if not grid.is_item_functional(placed):
			continue
		var trait_bonus := _calc_spatial_passive_armor(placed, grid)
		if trait_bonus > 0:
			gain_block.call(trait_bonus, placed.data.get_localized_name())


static func _effective_armor(item: ItemData) -> int:
	if item == null:
		return 0
	var armor := item.get_effective_armor()
	if armor <= 0 and item.block_amount > 0:
		armor = item.block_amount
	return maxi(0, armor)


static func _calc_spatial_passive_armor(placed: PlacedItem, grid: BodyGrid) -> int:
	var data := placed.data
	var low_helmet := has_trait(data, "TRAIT_HELMET_LOW")
	var high_helmet := has_trait(data, "TRAIT_HELMET_HIGH")
	var low_leg := has_trait(data, "TRAIT_LEG_LOW")
	var high_leg := has_trait(data, "TRAIT_LEG_HIGH")
	if not (low_helmet or high_helmet or low_leg or high_leg):
		return 0

	var factor := 0.0
	if high_helmet or high_leg:
		factor = 1.0
	elif low_helmet or low_leg:
		factor = 0.5

	var total_cells := 0
	var left := placed.origin.x
	var right := placed.origin.x + placed.data.size.x - 1
	var top := placed.origin.y
	var bottom := placed.origin.y + placed.data.size.y - 1

	if high_helmet or low_helmet:
		for col in range(left, right + 1):
			for y in range(bottom + 1, grid.height):
				var c := Vector2i(col, y)
				if grid.is_unlocked(c):
					total_cells += 1
	elif high_leg or low_leg:
		for col in range(left, right + 1):
			for y in range(0, top):
				var c := Vector2i(col, y)
				if grid.is_unlocked(c):
					total_cells += 1

	var base := int(floor(total_cells * factor))
	var row_penalty := _count_same_row_penalty(placed, grid)
	return maxi(0, base - row_penalty)


static func _count_same_row_penalty(origin_item: PlacedItem, grid: BodyGrid) -> int:
	var penalty := 0
	var row := origin_item.origin.y
	var is_helmet := origin_item.data.sub_type == "HELMET"
	var is_leg := origin_item.data.sub_type == "LEG_ARMOR"
	for other: PlacedItem in grid.items:
		if other == null or other == origin_item or other.data == null:
			continue
		if other.origin.y != row:
			continue
		if is_helmet and other.data.sub_type == "HELMET":
			penalty += 1
		elif is_leg and other.data.sub_type == "LEG_ARMOR":
			penalty += 1
	return penalty
