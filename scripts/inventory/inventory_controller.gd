class_name InventoryController
extends RefCounted
## Owns the player's BodyGrid and HP.
## No external stash — modules exist only on the active body grid.

const BASE_MAX_AP := 3
const BASE_HP_POOL := 30
const BASE_MAX_HP := 40  ## END 2 + base 30 via ActorStats.get_max_hp

var grid: BodyGrid
var max_hp: int = BASE_MAX_HP
var current_hp: int = BASE_MAX_HP


func _init() -> void:
	_bind_grid(BodyGrid.new())


func reset_run() -> void:
	_bind_grid(BodyGrid.new())
	max_hp = BASE_MAX_HP
	current_hp = BASE_MAX_HP


func apply_actor_stats(stats: ActorStats) -> void:
	## Sync Max HP from ActorStats (base 30 + END * 5).
	## END up → current HP rises by the same delta; END down → clamp to new max only.
	if stats == null:
		return
	var old_max := max_hp
	var new_max := maxi(1, stats.get_max_hp(BASE_HP_POOL))
	apply_max_hp_change(new_max, old_max)


func apply_max_hp_change(new_max: int, old_max: int = -1) -> void:
	## Central HP pool reaction to Max HP changes (endurance, gear, etc.).
	## Gain: current += (new_max - old_max). Loss: current = min(current, new_max).
	var previous := old_max if old_max >= 0 else max_hp
	max_hp = maxi(1, new_max)
	var delta := max_hp - previous
	if delta > 0:
		current_hp += delta
	elif delta < 0:
		current_hp = mini(current_hp, max_hp)
	current_hp = clampi(current_hp, 0, max_hp)
	EventBus.player_hp_changed.emit(current_hp, max_hp)


func _bind_grid(new_grid: BodyGrid) -> void:
	if grid != null and grid.item_unequipped.is_connected(_on_grid_item_unequipped):
		grid.item_unequipped.disconnect(_on_grid_item_unequipped)
	grid = new_grid
	grid.item_unequipped.connect(_on_grid_item_unequipped)


func _on_grid_item_unequipped(_item: ItemData, _reason: String) -> void:
	## Corruption destroys the module — there is no off-grid storage.
	pass


func place_item(item: ItemData, origin: Vector2i, footprint: Vector2i = Vector2i.ZERO) -> bool:
	return grid.place_item(item, origin, footprint) != null


func extract_from_grid(origin: Vector2i) -> ItemData:
	## Clear occupied cells for a drag pickup; silent remove until drop commits.
	var occ := grid.get_occupant(origin)
	if occ == null:
		return null
	var data: ItemData = occ.data
	grid.remove_item(occ, false)
	return data


func place_dragged(item: ItemData, origin: Vector2i, footprint: Vector2i = Vector2i.ZERO) -> bool:
	return grid.place_item(item, origin, footprint) != null


func try_place_anywhere(item: ItemData) -> bool:
	## Place on the first valid unlocked footprint; returns false if no fit.
	## Stackables first try to merge into an existing matching cell.
	if item == null:
		return false
	if item.is_stackable:
		var leftover := _merge_into_existing_stacks(item)
		if leftover <= 0:
			EventBus.inventory_changed.emit()
			return true
		item.current_stack = leftover
	for y in grid.height:
		for x in grid.width:
			var origin := Vector2i(x, y)
			if grid.can_place_item(item, origin):
				var ok := place_item(item, origin)
				if ok:
					EventBus.inventory_changed.emit()
				return ok
	EventBus.placement_failed.emit("KEY_PLACE_OCCUPIED")
	return false


func add_stackable_item(item_id: String, amount: int) -> int:
	## Grants `amount` of a stackable catalog item, merging into existing stacks.
	## Returns how many units were successfully stored.
	if amount <= 0 or ItemDatabase == null:
		return 0
	var prototype: ItemData = ItemDatabase.get_item(item_id)
	if prototype == null:
		push_warning("InventoryController: unknown item '%s'" % item_id)
		return 0
	var max_stack := maxi(prototype.max_stack, 1) if prototype.is_stackable else 1
	var remaining := amount
	## Fill existing stacks first.
	if grid != null:
		for placed: PlacedItem in grid.items:
			if remaining <= 0:
				break
			if placed == null or placed.data == null:
				continue
			if placed.data.id != item_id or not placed.data.is_stackable:
				continue
			var room := maxi(0, max_stack - placed.data.current_stack)
			if room <= 0:
				continue
			var add := mini(room, remaining)
			placed.data.current_stack += add
			placed.data.max_stack = max_stack
			remaining -= add
	## Place new stacks for the remainder.
	while remaining > 0:
		var chunk := mini(remaining, max_stack)
		var inst: ItemData = ItemDatabase.create_instance(item_id)
		if inst == null:
			break
		inst.is_stackable = true
		inst.max_stack = max_stack
		inst.current_stack = chunk
		if not try_place_anywhere(inst):
			break
		remaining -= chunk
	var granted := amount - remaining
	if granted > 0:
		EventBus.inventory_changed.emit()
	return granted


func _merge_into_existing_stacks(item: ItemData) -> int:
	## Returns leftover stack that still needs a new cell.
	if item == null or not item.is_stackable or grid == null:
		return item.current_stack if item else 0
	var remaining := item.current_stack
	var max_stack := maxi(item.max_stack, 1)
	for placed: PlacedItem in grid.items:
		if remaining <= 0:
			break
		if placed == null or placed.data == null:
			continue
		if placed.data.id != item.id or not placed.data.is_stackable:
			continue
		var room := maxi(0, max_stack - placed.data.current_stack)
		if room <= 0:
			continue
		var add := mini(room, remaining)
		placed.data.current_stack += add
		placed.data.max_stack = max_stack
		remaining -= add
	return remaining


func get_max_ap() -> int:
	return BASE_MAX_AP + grid.get_total_max_ap_bonus()


func get_equipped_items_by_type(type_id: String) -> Array[PlacedItem]:
	## All functional (or simply placed) modules matching item_type id.
	var result: Array[PlacedItem] = []
	if grid == null:
		return result
	var needle := type_id.strip_edges().to_upper()
	if needle.is_empty():
		return result
	for placed: PlacedItem in grid.items:
		if placed == null or placed.data == null or placed.data.item_type == null:
			continue
		var placed_type := placed.data.item_type.id.strip_edges().to_upper()
		if placed_type == needle or (needle == "ARMOR" and placed_type == "SHIELD"):
			result.append(placed)
	return result


func get_neuron_amplifier_hp_cost() -> int:
	## Base 4 HP + 1 per equipped armor module on the body grid.
	var base_cost: int = 4
	var armor_count: int = get_equipped_items_by_type("armor").size()
	return base_cost + armor_count


func can_safely_use_neuron_amplifier() -> bool:
	## Dialogue / out-of-combat safety: must keep HP above the cost.
	return current_hp > get_neuron_amplifier_hp_cost()


func pay_neuron_amplifier_hp(allow_fatal: bool = false) -> bool:
	## Spends dynamic HP cost. Returns false if blocked by safety (non-fatal path).
	var cost := get_neuron_amplifier_hp_cost()
	if cost <= 0:
		return true
	if not allow_fatal and current_hp <= cost:
		return false
	current_hp = maxi(0, current_hp - cost)
	EventBus.player_hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0:
		EventBus.player_died.emit()
	return true


func apply_damage(amount: int, block: int = 0) -> int:
	var absorbed := mini(block, amount)
	var remaining := amount - absorbed
	current_hp = maxi(0, current_hp - remaining)
	EventBus.player_hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0:
		EventBus.player_died.emit()
	return remaining


func heal_full() -> void:
	current_hp = max_hp
	EventBus.player_hp_changed.emit(current_hp, max_hp)


func heal_percent(fraction: float) -> int:
	## Heal up to `fraction` of max HP, never past max. Returns actual HP gained.
	if fraction <= 0.0:
		return 0
	var amount := maxi(1, int(floor(float(max_hp) * fraction)))
	var before := current_hp
	current_hp = mini(max_hp, current_hp + amount)
	var gained := current_hp - before
	if gained > 0:
		EventBus.player_hp_changed.emit(current_hp, max_hp)
	return gained


func remove_all_harmful_items() -> int:
	## Strip every is_harmful module from the body grid. Returns how many were removed.
	if grid == null:
		return 0
	var to_remove: Array[PlacedItem] = []
	for placed: PlacedItem in grid.items:
		if placed != null and placed.data != null and placed.data.is_harmful:
			to_remove.append(placed)
	for placed in to_remove:
		grid.remove_item(placed, true)
	return to_remove.size()


func is_dead() -> bool:
	return current_hp <= 0


func unlock_random_adjacent_cells(count: int = BodyGrid.LEVEL_UP_CELL_GAIN) -> Array[Vector2i]:
	## LEVEL_UP reveal helper used by Body Grid UI.
	if grid == null:
		return []
	return grid.unlock_random_adjacent_cells(count)


func unlock_random_cell() -> Array[Vector2i]:
	## Grid Expander: permanently unlock one adjacent locked cell.
	return unlock_random_adjacent_cells(1)


func find_placed_item(item_data: ItemData) -> PlacedItem:
	if grid == null or item_data == null:
		return null
	for placed: PlacedItem in grid.items:
		if placed != null and placed.data == item_data:
			return placed
	return null


func find_placed_item_by_id(item_id: String) -> PlacedItem:
	if grid == null:
		return null
	var needle := item_id.strip_edges().to_upper()
	if needle.is_empty():
		return null
	for placed: PlacedItem in grid.items:
		if placed == null or placed.data == null:
			continue
		if placed.data.id.strip_edges().to_upper() == needle:
			return placed
	return null


func has_item(item_id: String) -> bool:
	## True if Body Grid contains at least one instance of item_id.
	return find_placed_item_by_id(item_id) != null


func consume_item_charge(item_id: String) -> bool:
	## Spend one charge (or remove) an item in the Body Grid. Returns false if missing.
	var placed := find_placed_item_by_id(item_id)
	if placed == null:
		return false
	_spend_consumable_charge(placed)
	return true


func use_consumable_out_of_combat(item_data: ItemData, player_stats: PlayerStats = null) -> Dictionary:
	## Returns { ok: bool, message: String, unlocked_cells: Array[Vector2i] }.
	var result := {"ok": false, "message": "", "unlocked_cells": []}
	if item_data == null:
		return result
	if item_data.is_combat_only:
		result["message"] = tr("KEY_ITEM_COMBAT_ONLY")
		return result
	if not item_data.can_use_out_of_combat():
		result["message"] = tr("KEY_ITEM_CANNOT_USE")
		return result
	var placed := find_placed_item(item_data)
	if placed == null or grid == null:
		result["message"] = tr("KEY_ITEM_CANNOT_USE")
		return result
	if not item_data.has_charges_remaining() and item_data.consumable:
		result["message"] = tr("KEY_LOG_NO_CHARGES")
		return result

	## Special: permanent body-grid expansion.
	if item_data.is_grid_expander():
		var unlocked: Array[Vector2i] = unlock_random_cell()
		if unlocked.is_empty():
			result["message"] = tr("KEY_GRID_EXPAND_FULL")
			return result
		_spend_consumable_charge(placed)
		EventBus.grid_expanded.emit(unlocked)
		result["ok"] = true
		result["unlocked_cells"] = unlocked
		result["message"] = tr("KEY_GRID_EXPAND_SUCCESS")
		return result

	## Healing still applies out of combat.
	if TraitManager.has_trait(item_data, "TRAIT_BIO_GEL_HEAL"):
		var heal_amt := 8
		current_hp = mini(max_hp, current_hp + heal_amt)
		EventBus.player_hp_changed.emit(current_hp, max_hp)
		_spend_consumable_charge(placed)
		result["ok"] = true
		result["message"] = tr("KEY_LOG_STATUS_HEAL") % heal_amt
		return result

	## Permanent stat injections (usable from inventory outside combat).
	if _is_permanent_stat_injection(item_data):
		var perm_msg := _try_apply_permanent_stat_injection(item_data, player_stats)
		if perm_msg.is_empty():
			result["message"] = tr("KEY_ITEM_CANNOT_USE")
			return result
		_spend_consumable_charge(placed)
		result["ok"] = true
		result["message"] = perm_msg
		return result

	## AP stimulants / utility burn: consume only — no AP grant outside combat.
	_spend_consumable_charge(placed)
	result["ok"] = true
	if item_data.grants_ap_on_use():
		result["message"] = tr("KEY_ITEM_BURNED_NO_AP")
	else:
		result["message"] = tr("KEY_ITEM_CONSUMED")
	return result


func _try_apply_permanent_stat_injection(item_data: ItemData, player_stats: PlayerStats) -> String:
	## Returns localized success message, or "" on failure / missing stats.
	if item_data == null or player_stats == null:
		return ""
	if TraitManager.has_trait(item_data, "TRAIT_PERM_STRENGTH"):
		var amt := TraitManager.get_trait_value(item_data, "TRAIT_PERM_STRENGTH", 1)
		if amt != 0:
			player_stats.add_stat_bonus("strength", amt)
			return tr("KEY_LOG_PERM_STAT_GAIN") % [
				item_data.get_localized_name(), tr("KEY_STR"), amt
			]
	if TraitManager.has_trait(item_data, "TRAIT_PERM_INTELLIGENCE"):
		var amt := TraitManager.get_trait_value(item_data, "TRAIT_PERM_INTELLIGENCE", 1)
		if amt != 0:
			player_stats.add_stat_bonus("intelligence", amt)
			return tr("KEY_LOG_PERM_STAT_GAIN") % [
				item_data.get_localized_name(), tr("KEY_INT"), amt
			]
	if TraitManager.has_trait(item_data, "TRAIT_PERM_ENDURANCE"):
		var amt := TraitManager.get_trait_value(item_data, "TRAIT_PERM_ENDURANCE", 1)
		if amt != 0:
			player_stats.add_stat_bonus("endurance", amt)
			apply_actor_stats(player_stats)
			return tr("KEY_LOG_PERM_STAT_GAIN") % [
				item_data.get_localized_name(), tr("KEY_END"), amt
			]
	return ""


func _is_permanent_stat_injection(item_data: ItemData) -> bool:
	if item_data == null:
		return false
	return (
		TraitManager.has_trait(item_data, "TRAIT_PERM_STRENGTH")
		or TraitManager.has_trait(item_data, "TRAIT_PERM_INTELLIGENCE")
		or TraitManager.has_trait(item_data, "TRAIT_PERM_ENDURANCE")
	)


func _spend_consumable_charge(placed: PlacedItem) -> void:
	if placed == null or placed.data == null or grid == null:
		return
	var data := placed.data
	if data.consumable and data.max_charges > 0:
		data.current_charges = maxi(0, data.current_charges - 1)
		EventBus.inventory_changed.emit()
		if data.current_charges <= 0 and data.destroy_on_empty:
			grid.remove_item(placed, true)
			EventBus.item_removed.emit(data.id)
			EventBus.inventory_changed.emit()
		return
	## Non-charge consumables / one-shot tools: remove from grid.
	grid.remove_item(placed, true)
	EventBus.item_removed.emit(data.id)
	EventBus.inventory_changed.emit()
