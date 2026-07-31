class_name NeuroChipItem
extends RefCounted
## Currency helper for Neuro-Chips (stackable inventory item).

const ITEM_ID := "NEURO_CHIP"
const DISPLAY_NAME := "Neuro-Chips"
const DEFAULT_MAX_STACK := 999


static func create_stack(amount: int = 1) -> ItemData:
	## Builds a runtime ItemData instance with the requested stack size.
	if ItemDatabase == null:
		return null
	var item: ItemData = ItemDatabase.create_instance(ITEM_ID)
	if item == null:
		return null
	item.is_stackable = true
	item.max_stack = maxi(item.max_stack, DEFAULT_MAX_STACK)
	item.current_stack = clampi(maxi(amount, 1), 1, item.max_stack)
	return item


static func grant_to_inventory(inventory: InventoryController, amount: int) -> int:
	## Adds Neuro-Chips into existing stacks, then places remainder. Returns amount granted.
	if inventory == null or amount <= 0:
		return 0
	return inventory.add_stackable_item(ITEM_ID, amount)


static func count_in_inventory(inventory: InventoryController) -> int:
	if inventory == null or inventory.grid == null:
		return 0
	var total := 0
	for placed: PlacedItem in inventory.grid.items:
		if placed == null or placed.data == null:
			continue
		if placed.data.id != ITEM_ID:
			continue
		total += maxi(placed.data.current_stack, 1) if placed.data.is_stackable else 1
	return total


static func try_spend(inventory: InventoryController, amount: int) -> int:
	## Removes up to `amount` Neuro-Chips from the body grid. Returns how many were taken.
	if inventory == null or inventory.grid == null or amount <= 0:
		return 0
	var remaining := amount
	var to_remove: Array[PlacedItem] = []
	for placed: PlacedItem in inventory.grid.items:
		if remaining <= 0:
			break
		if placed == null or placed.data == null:
			continue
		if placed.data.id != ITEM_ID or not placed.data.is_stackable:
			continue
		var take := mini(remaining, maxi(placed.data.current_stack, 0))
		if take <= 0:
			continue
		placed.data.current_stack -= take
		remaining -= take
		if placed.data.current_stack <= 0:
			to_remove.append(placed)
	for placed in to_remove:
		inventory.grid.remove_item(placed, false)
	var spent := amount - remaining
	if spent > 0:
		EventBus.inventory_changed.emit()
	return spent
