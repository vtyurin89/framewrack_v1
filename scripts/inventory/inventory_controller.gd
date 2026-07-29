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
	if item_id == NeuroChipItem.ITEM_ID:
		max_stack = maxi(max_stack, NeuroChipItem.DEFAULT_MAX_STACK)
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


func unlock_random_adjacent_cells(count: int = BodyGrid.LEVEL_UP_CELL_GAIN) -> Array[Vector2i]:
	## LEVEL_UP reveal helper used by Body Grid UI.
	if grid == null:
		return []
	return grid.unlock_random_adjacent_cells(count)
