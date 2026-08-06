extends Node
## Autoload: d6 success-pool stat checks with optional AP dice boosts / guaranteed success.

const NEURO_STIMULATOR_ID := "NEURO_STIMULATOR"
const SYNAPSE_BOOSTER_ID := "SYNAPSE_BOOSTER"
const NEURON_AMPLIFIER_ID := "NEURON_AMPLIFIER"
## Neuro-Stimulator spends as 2 "AP" → +4 d6; Neuron Amplifier as 1 → +2 d6.
const NEURO_CHECK_AP_VALUE := 2
const NEURON_CHECK_AP_VALUE := 1

var force_guaranteed_success: bool = false
## When true, force_guaranteed_success is not cleared after one check (story locks).
var guaranteed_success_locked: bool = false


class CheckResult:
	var is_success: bool = false
	var successes_count: int = 0
	var dice_rolled: int = 0
	var rolls: Array[int] = []
	var ap_bonus_applied: int = 0
	var is_guaranteed: bool = false


func perform_check(
	stat_value: int, required_successes: int = 1, consumed_ap: int = 0
) -> CheckResult:
	var result := CheckResult.new()
	result.ap_bonus_applied = maxi(0, consumed_ap)

	if force_guaranteed_success:
		result.is_success = true
		result.is_guaranteed = true
		result.successes_count = maxi(1, required_successes)
		if not guaranteed_success_locked:
			force_guaranteed_success = false
		return result

	var total_dice := maxi(1, stat_value + (result.ap_bonus_applied * 2))
	result.dice_rolled = total_dice

	for _i in total_dice:
		var roll := randi_range(1, 6)
		result.rolls.append(roll)
		if roll >= 5:
			result.successes_count += 1

	result.is_success = result.successes_count >= maxi(1, required_successes)
	return result


func set_guaranteed_success(active: bool, locked: bool = false) -> void:
	force_guaranteed_success = active
	guaranteed_success_locked = locked and active


func clear_guaranteed_success() -> void:
	force_guaranteed_success = false
	guaranteed_success_locked = false


func inventory_has_item(inventory: InventoryController, item_id: String) -> bool:
	return find_placed_item(inventory, item_id) != null


func find_placed_item(inventory: InventoryController, item_id: String) -> PlacedItem:
	if inventory == null or inventory.grid == null:
		return null
	var needle := item_id.strip_edges().to_upper()
	if needle.is_empty():
		return null
	for placed: PlacedItem in inventory.grid.items:
		if placed == null or placed.data == null:
			continue
		if placed.data.id.strip_edges().to_upper() == needle:
			return placed
	return null


func consume_inventory_item(inventory: InventoryController, item_id: String) -> bool:
	var placed := find_placed_item(inventory, item_id)
	if placed == null or inventory == null or inventory.grid == null:
		return false
	var data := placed.data
	if data != null and data.consumable and data.max_charges > 0:
		data.current_charges = maxi(0, data.current_charges - 1)
		if data.current_charges <= 0 and data.destroy_on_empty:
			inventory.grid.remove_item(placed, true)
			EventBus.inventory_changed.emit()
			return true
		EventBus.inventory_changed.emit()
		return true
	inventory.grid.remove_item(placed, true)
	EventBus.inventory_changed.emit()
	return true


func try_consume_neuro_stimulator(inventory: InventoryController) -> int:
	## Returns consumed_ap value (2) on success, else 0.
	if not consume_inventory_item(inventory, NEURO_STIMULATOR_ID):
		return 0
	return NEURO_CHECK_AP_VALUE


func try_consume_synapse_booster(inventory: InventoryController) -> bool:
	if not consume_inventory_item(inventory, SYNAPSE_BOOSTER_ID):
		return false
	set_guaranteed_success(true, false)
	return true


func try_use_neuron_amplifier(inventory: InventoryController) -> int:
	## Dialogue path: pay HP only when safe (HP > cost). Returns AP-equivalent dice boost.
	if inventory == null:
		return 0
	if not has_neuron_amplifier(inventory):
		return 0
	if not inventory.can_safely_use_neuron_amplifier():
		return 0
	if not inventory.pay_neuron_amplifier_hp(false):
		return 0
	return NEURON_CHECK_AP_VALUE


func has_neuro_stimulator(inventory: InventoryController) -> bool:
	return inventory_has_item(inventory, NEURO_STIMULATOR_ID)


func has_synapse_booster(inventory: InventoryController) -> bool:
	return inventory_has_item(inventory, SYNAPSE_BOOSTER_ID)


func has_neuron_amplifier(inventory: InventoryController) -> bool:
	return inventory_has_item(inventory, NEURON_AMPLIFIER_ID)


func preview_dice_count(stat_value: int, consumed_ap: int = 0) -> int:
	return maxi(1, stat_value + (maxi(0, consumed_ap) * 2))
