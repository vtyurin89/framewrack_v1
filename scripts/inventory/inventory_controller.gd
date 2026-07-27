class_name InventoryController
extends RefCounted
## Owns the player's BodyGrid and HP.
## No external stash — modules exist only on the active body grid.

const BASE_MAX_AP := 3
const BASE_MAX_HP := 40

var grid: BodyGrid
var max_hp: int = BASE_MAX_HP
var current_hp: int = BASE_MAX_HP


func _init() -> void:
	_bind_grid(BodyGrid.new(4, 4))


func reset_run() -> void:
	_bind_grid(BodyGrid.new(4, 4))
	max_hp = BASE_MAX_HP
	current_hp = BASE_MAX_HP


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
	if item == null:
		return false
	for y in grid.height:
		for x in grid.width:
			var origin := Vector2i(x, y)
			if grid.can_place_item(item, origin):
				return place_item(item, origin)
	EventBus.placement_failed.emit("KEY_PLACE_OCCUPIED")
	return false


func get_max_ap() -> int:
	return BASE_MAX_AP + grid.get_total_max_ap_bonus()


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


func is_dead() -> bool:
	return current_hp <= 0
