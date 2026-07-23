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
	grid = BodyGrid.new(4, 4)


func reset_run() -> void:
	grid = BodyGrid.new(4, 4)
	stash.clear()
	max_hp = BASE_MAX_HP
	current_hp = BASE_MAX_HP


func add_to_stash(item: ItemData) -> void:
	if item:
		stash.append(item)
		EventBus.inventory_changed.emit()


func try_place_from_stash(stash_index: int, origin: Vector2i) -> bool:
	if stash_index < 0 or stash_index >= stash.size():
		EventBus.placement_failed.emit("Invalid stash index.")
		return false
	var data: ItemData = stash[stash_index]
	var placed := grid.place_item(data, origin)
	if placed == null:
		return false
	stash.remove_at(stash_index)
	return true


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
