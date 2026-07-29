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
