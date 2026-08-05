class_name NeuroChipItem
extends RefCounted
## Compatibility facade — Neuro-Chips are global currency via GameManager.

const ITEM_ID := "NEURO_CHIP"
const DISPLAY_NAME := "Neuro-Chips"
const DEFAULT_MAX_STACK := 999


static func create_stack(_amount: int = 1) -> ItemData:
	## Physical chip stacks are retired; callers should use GameManager.add_chips.
	push_warning("NeuroChipItem.create_stack: Neuro-Chips are global currency, not items")
	return null


static func grant_to_inventory(_inventory: InventoryController, amount: int) -> int:
	if GameManager == null:
		return 0
	return GameManager.add_chips(amount)


static func count_in_inventory(_inventory: InventoryController = null) -> int:
	if GameManager == null:
		return 0
	return GameManager.get_chips()


static func try_spend(_inventory: InventoryController, amount: int) -> int:
	## Spend from global balance. Returns amount actually spent.
	if GameManager == null or amount <= 0:
		return 0
	if GameManager.spend_chips(amount):
		return amount
	var available: int = GameManager.get_chips()
	if available <= 0:
		return 0
	GameManager.spend_chips(available)
	return available
