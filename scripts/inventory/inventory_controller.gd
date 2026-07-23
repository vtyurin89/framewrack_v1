class_name InventoryController
extends RefCounted
## Owns the player's BodyGrid, stash of unplaced ItemData, and HP.
## Bridge between UI placement and combat queries.

const BASE_MAX_AP := 3
const BASE_MAX_HP := 40

var grid: BodyGrid
var stash: Array[ItemData] = []
var max_hp: int = BASE_MAX_HP
var current_hp: int = BASE_MAX_HP


func _init() -> void:
	_bind_grid(BodyGrid.new(4, 4))


func reset_run() -> void:
	_bind_grid(BodyGrid.new(4, 4))
	stash.clear()
	max_hp = BASE_MAX_HP
	current_hp = BASE_MAX_HP


func _bind_grid(new_grid: BodyGrid) -> void:
	if grid != null and grid.item_unequipped.is_connected(_on_grid_item_unequipped):
		grid.item_unequipped.disconnect(_on_grid_item_unequipped)
	grid = new_grid
	grid.item_unequipped.connect(_on_grid_item_unequipped)


func _on_grid_item_unequipped(item: ItemData, _reason: String) -> void:
	## Corruption (and similar) force-unequip → return blueprint to stash.
	if item:
		stash.append(item)


func add_to_stash(item: ItemData) -> void:
	if item:
		stash.append(item)
		EventBus.inventory_changed.emit()


func try_place_from_stash(stash_index: int, origin: Vector2i) -> bool:
	if stash_index < 0 or stash_index >= stash.size():
		EventBus.placement_failed.emit("Invalid stash index.")
		return false
	var data: ItemData = stash[stash_index]
	var placed = grid.place_item(data, origin)
	if placed == null:
		return false
	stash.remove_at(stash_index)
	return true


func extract_from_stash(stash_index: int) -> ItemData:
	## Pull item out of stash for a drag session (silent — UI owns refresh).
	if stash_index < 0 or stash_index >= stash.size():
		return null
	var data: ItemData = stash[stash_index]
	stash.remove_at(stash_index)
	return data


func extract_from_grid(origin: Vector2i) -> ItemData:
	## Clear occupied cells for a drag pickup; silent remove until drop commits.
	var occ := grid.get_occupant(origin)
	if occ == null:
		return null
	var data: ItemData = occ.data
	grid.remove_item(occ, false)
	return data


func return_to_stash(item: ItemData, index: int = -1) -> void:
	if item == null:
		return
	if index < 0 or index > stash.size():
		stash.append(item)
	else:
		stash.insert(index, item)
	EventBus.inventory_changed.emit()


func place_dragged(item: ItemData, origin: Vector2i, footprint: Vector2i = Vector2i.ZERO) -> bool:
	return grid.place_item(item, origin, footprint) != null


func unequip_to_stash(origin: Vector2i) -> void:
	var occ := grid.get_occupant(origin)
	if occ == null:
		return
	var data: ItemData = occ.data
	grid.remove_item(occ)
	stash.append(data)


func get_max_ap() -> int:
	return BASE_MAX_AP + grid.get_total_max_ap_bonus()


func apply_damage(amount: int, block: int = 0) -> int:
	var absorbed := mini(block, amount)
	var remaining := amount - absorbed
	current_hp = maxi(0, current_hp - remaining)
	EventBus.player_hp_changed.emit(current_hp, max_hp)
	return remaining


func heal_full() -> void:
	current_hp = max_hp
	EventBus.player_hp_changed.emit(current_hp, max_hp)


func is_dead() -> bool:
	return current_hp <= 0
