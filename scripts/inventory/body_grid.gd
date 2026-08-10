class_name BodyGrid
extends RefCounted
## Spatial inventory — the player's body (core Inventory Body Grid logic).
## Supports irregular unlocked shapes, edge placement rules,
## adjacency queries, and temporary corruption locks.
##
## Cell occupancy is tracked as EMPTY / OCCUPIED / CORRUPTED.
## UI lives in inventory_grid_ui.gd; this class is the authoritative model.

signal changed
signal item_unequipped(item: ItemData, reason: String)
signal grid_layout_updated

enum CellState {
	EMPTY,
	OCCUPIED,
	CORRUPTED,
}

## Active starter hull at Level 1 (3x4 = 12 cells).
const STARTER_SIZE := Vector2i(3, 4)
## Full expandable matrix (7x8 = 56 slots). Room for +2 cells in each direction.
const MAX_SIZE := Vector2i(7, 8)
## Starter origin centered inside MAX_SIZE: (7-3)/2=2, (8-4)/2=2.
const STARTER_ORIGIN := Vector2i(2, 2)
## Back-compat alias for older callers.
const DEFAULT_SIZE := STARTER_SIZE
## Cells unlocked per level-up expansion.
const LEVEL_UP_CELL_GAIN := 3

## Bounding box of the grid (locked + unlocked cells inside MAX_SIZE).
var width: int = MAX_SIZE.x
var height: int = MAX_SIZE.y

## Cells the player may use. Key = "x,y"
var _unlocked: Dictionary = {}

## Corrupted cells: Key = "x,y" → remaining turns (>0).
var _corruption: Dictionary = {}

## Derived cell-state cache Key = "x,y" → CellState (rebuilt on mutations).
var _cell_states: Dictionary = {}

## Placed modules.
var items: Array[PlacedItem] = []


func _init(_p_width: int = STARTER_SIZE.x, _p_height: int = STARTER_SIZE.y) -> void:
	## Always allocate the full MAX_SIZE matrix; only the starter hull starts unlocked.
	width = MAX_SIZE.x
	height = MAX_SIZE.y
	_unlock_rectangle(STARTER_ORIGIN.x, STARTER_ORIGIN.y, STARTER_SIZE.x, STARTER_SIZE.y)
	_rebuild_cell_states()


# ---------------------------------------------------------------------------
# Cell state helpers
# ---------------------------------------------------------------------------

static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func is_unlocked(cell: Vector2i) -> bool:
	return _unlocked.has(cell_key(cell))


func is_corrupted(cell: Vector2i) -> bool:
	return _corruption.get(cell_key(cell), 0) > 0


func get_corruption_turns(cell: Vector2i) -> int:
	return int(_corruption.get(cell_key(cell), 0))


func get_cell_state(cell: Vector2i) -> CellState:
	## Public read of EMPTY / OCCUPIED / CORRUPTED for unlocked in-bounds cells.
	## Unlocked-but-missing keys are treated as EMPTY; locked/out-of-bounds → EMPTY.
	if is_corrupted(cell):
		return CellState.CORRUPTED
	if get_occupant(cell) != null:
		return CellState.OCCUPIED
	return CellState.EMPTY


func is_edge_cell(cell: Vector2i) -> bool:
	## Edge relative to the unlocked shape: missing orthogonal unlocked neighbour,
	## or bounding-box border of the grid.
	if not is_unlocked(cell):
		return false
	var neighbors := [
		cell + Vector2i.LEFT,
		cell + Vector2i.RIGHT,
		cell + Vector2i.UP,
		cell + Vector2i.DOWN,
	]
	for n: Vector2i in neighbors:
		if not is_unlocked(n):
			return true
	return cell.x == 0 or cell.y == 0 or cell.x == width - 1 or cell.y == height - 1


func get_occupant(cell: Vector2i) -> PlacedItem:
	for item: PlacedItem in items:
		if cell in item.occupied_cells():
			return item
	return null


func is_cell_free(cell: Vector2i) -> bool:
	return (
		is_unlocked(cell)
		and get_cell_state(cell) == CellState.EMPTY
	)


func _rebuild_cell_states() -> void:
	_cell_states.clear()
	for cell: Vector2i in get_unlocked_cells():
		_cell_states[cell_key(cell)] = get_cell_state(cell)


# ---------------------------------------------------------------------------
# Unlock / expand (mutation hook)
# ---------------------------------------------------------------------------

func _unlock_rectangle(ox: int, oy: int, w: int, h: int) -> void:
	for y in h:
		for x in w:
			_unlocked[cell_key(Vector2i(ox + x, oy + y))] = true


func unlock_cells(cells: Array[Vector2i]) -> void:
	## Expand the body within MAX_SIZE — visual mutation reacts to EventBus.grid_expanded.
	var added: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if not _is_within_max_bounds(cell):
			continue
		var key := cell_key(cell)
		if not _unlocked.has(key):
			_unlocked[key] = true
			added.append(cell)
	if not added.is_empty():
		_rebuild_cell_states()
		EventBus.grid_expanded.emit(added)
		changed.emit()
		EventBus.inventory_changed.emit()


func expand_by_adjacent_cells(count: int = LEVEL_UP_CELL_GAIN) -> Array[Vector2i]:
	## Unlock up to `count` random locked cells that share an edge with the active hull.
	## Stays inside the 7x8 max matrix so shapes remain organic / non-rectangular.
	if count <= 0:
		return []
	var candidates: Array[Vector2i] = _collect_adjacent_locked_candidates()
	if candidates.is_empty():
		return []
	candidates.shuffle()
	var to_add: Array[Vector2i] = []
	for i in mini(count, candidates.size()):
		to_add.append(candidates[i])
	unlock_cells(to_add)
	return to_add


func unlock_random_adjacent_cells(count: int = LEVEL_UP_CELL_GAIN) -> Array[Vector2i]:
	## Spec alias used by LEVEL_UP UI reveal sequence.
	return expand_by_adjacent_cells(count)


func get_unlocked_cell_count() -> int:
	return _unlocked.size()


func get_unlocked_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for key: String in _unlocked.keys():
		var parts := key.split(",")
		result.append(Vector2i(int(parts[0]), int(parts[1])))
	return result


func _is_within_max_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < MAX_SIZE.x and cell.y < MAX_SIZE.y


func _collect_adjacent_locked_candidates() -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var seen: Dictionary = {}
	var dirs := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for cell: Vector2i in get_unlocked_cells():
		for d: Vector2i in dirs:
			var n := cell + d
			if not _is_within_max_bounds(n):
				continue
			if is_unlocked(n):
				continue
			var key := cell_key(n)
			if seen.has(key):
				continue
			seen[key] = true
			candidates.append(n)
	return candidates


# ---------------------------------------------------------------------------
# Placement validation & mutation
# ---------------------------------------------------------------------------

func can_place(data: ItemData, origin: Vector2i, footprint: Vector2i = Vector2i.ZERO) -> String:
	## Returns empty string on success, otherwise a translation key for the failure reason.
	## Optional footprint overrides data.size (used while rotating during drag).
	if data == null:
		return "KEY_PLACE_NO_DATA"
	var shape: Vector2i = data.size if footprint == Vector2i.ZERO else footprint
	if shape.x < 1 or shape.y < 1:
		return "KEY_PLACE_INVALID_FOOTPRINT"
	var cells := data.footprint_for(shape, origin)
	var touches_edge := false
	for cell: Vector2i in cells:
		if not is_in_bounds(cell) or not is_unlocked(cell):
			return "KEY_PLACE_OUTSIDE"
		match get_cell_state(cell):
			CellState.OCCUPIED:
				return "KEY_PLACE_OCCUPIED"
			CellState.CORRUPTED:
				return "KEY_PLACE_CORRUPTED"
			_:
				pass
		if is_edge_cell(cell):
			touches_edge = true
	if data.is_edge_only and not touches_edge:
		return "KEY_PLACE_EDGE"
	return ""


func can_place_item(item: ItemData, top_left_pos: Vector2i, footprint: Vector2i = Vector2i.ZERO) -> bool:
	## Spec API: boundary + EMPTY cells + optional edge-touch for is_edge_only.
	return can_place(item, top_left_pos, footprint) == ""


func place_item(item: ItemData, top_left_pos: Vector2i, footprint: Vector2i = Vector2i.ZERO) -> Variant:
	## Places item if valid. Returns PlacedItem on success, null on fail.
	## If footprint is provided and differs from item.size, item.size is updated (rotation commit).
	var reason := can_place(item, top_left_pos, footprint)
	if reason != "":
		EventBus.placement_failed.emit(reason)
		return null
	if footprint != Vector2i.ZERO and footprint != item.size:
		item.size = footprint
	var placed := PlacedItem.new(item, top_left_pos)
	items.append(placed)
	_rebuild_cell_states()
	recalculate_grid_adjacencies()
	changed.emit()
	EventBus.item_placed.emit(item.id, top_left_pos)
	EventBus.inventory_changed.emit()
	return placed


func remove_item(placed: PlacedItem, notify: bool = true) -> void:
	if placed == null:
		return
	items.erase(placed)
	_rebuild_cell_states()
	recalculate_grid_adjacencies()
	if not notify:
		return
	changed.emit()
	EventBus.item_removed.emit(placed.data.id if placed.data else "")
	EventBus.inventory_changed.emit()


func remove_item_at(origin: Vector2i) -> void:
	var occ := get_occupant(origin)
	if occ:
		remove_item(occ)


# ---------------------------------------------------------------------------
# Functionality / adjacency / combat helpers
# ---------------------------------------------------------------------------

func is_item_functional(placed: PlacedItem) -> bool:
	## An item fails if ANY of its cells are corrupted.
	if placed == null or placed.data == null:
		return false
	for cell: Vector2i in placed.occupied_cells():
		if get_cell_state(cell) == CellState.CORRUPTED:
			return false
	return true


func get_functional_items() -> Array[PlacedItem]:
	var result: Array[PlacedItem] = []
	for item: PlacedItem in items:
		if is_item_functional(item):
			result.append(item)
	return result


func get_adjacent_items(placed: PlacedItem) -> Array[PlacedItem]:
	## Orthogonally adjacent modules (sharing an edge with any occupied cell).
	var found: Dictionary = {}
	var own_cells := placed.occupied_cells()
	var own_set: Dictionary = {}
	for c: Vector2i in own_cells:
		own_set[cell_key(c)] = true

	var dirs := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for cell: Vector2i in own_cells:
		for d: Vector2i in dirs:
			var n := cell + d
			if own_set.has(cell_key(n)):
				continue
			var occ := get_occupant(n)
			if occ and occ != placed:
				found[occ.instance_id] = occ

	var result: Array[PlacedItem] = []
	for v in found.values():
		result.append(v)
	return result


func get_adjacent_item_data(placed: PlacedItem) -> Array[ItemData]:
	## Neighbour ItemData list for trait / adjacency-rule evaluation.
	var result: Array[ItemData] = []
	for neighbour: PlacedItem in get_adjacent_items(placed):
		if neighbour != null and neighbour.data != null:
			result.append(neighbour.data)
	return result


func recalculate_grid_adjacencies() -> void:
	## Re-evaluate every placed item's traits against orthogonal neighbours.
	for placed: PlacedItem in items:
		if placed == null or placed.data == null:
			continue
		var neighbours: Array[ItemData] = get_adjacent_item_data(placed)
		for item_trait: TraitData in placed.data.traits:
			if item_trait == null:
				continue
			item_trait.evaluate_active_status(neighbours)
	grid_layout_updated.emit()
	EventBus.grid_layout_updated.emit()


func get_adjacency_damage_bonus_for(weapon: PlacedItem) -> int:
	## Sum adjacency_dmg_bonus from functional neighbours (e.g. Micro-Reactor).
	var bonus := 0
	for neighbour: PlacedItem in get_adjacent_items(weapon):
		if not is_item_functional(neighbour):
			continue
		bonus += neighbour.data.adjacency_dmg_bonus
	return bonus


func get_adjacent_dot_amplify_bonus(source: PlacedItem) -> int:
	## +N DoT stacks from each orthogonal amplifier with TRAIT_DOT_AMPLIFY.
	var bonus := 0
	if source == null:
		return 0
	for neighbour: PlacedItem in get_adjacent_items(source):
		if neighbour == null or neighbour.data == null:
			continue
		if not is_item_functional(neighbour):
			continue
		if not neighbour.data.is_amplifier():
			continue
		if not TraitManager.has_trait(neighbour.data, "TRAIT_DOT_AMPLIFY"):
			continue
		bonus += maxi(1, TraitManager.get_trait_value(neighbour.data, "TRAIT_DOT_AMPLIFY", 1))
	return bonus


func get_adjacent_heal_on_hit_bonus(source: PlacedItem) -> int:
	## +N healing from orthogonal amplifiers with TRAIT_HEAL_ON_HIT.
	var bonus := 0
	if source == null:
		return 0
	for neighbour: PlacedItem in get_adjacent_items(source):
		if neighbour == null or neighbour.data == null:
			continue
		if not is_item_functional(neighbour):
			continue
		if not neighbour.data.is_amplifier():
			continue
		if not TraitManager.has_trait(neighbour.data, "TRAIT_HEAL_ON_HIT"):
			continue
		bonus += maxi(1, TraitManager.get_trait_value(neighbour.data, "TRAIT_HEAL_ON_HIT", 1))
	return bonus


func find_placed_by_data(item: ItemData) -> PlacedItem:
	## Resolve a live grid placement from an ItemData instance reference.
	if item == null:
		return null
	for placed: PlacedItem in items:
		if placed != null and placed.data == item:
			return placed
	return null


func get_adjacent_bonuses() -> Dictionary:
	## Aggregate adjacency bonuses across the whole grid.
	## Returns { "damage_bonus": int, "ap_bonus": int, "per_weapon": Dictionary }.
	## per_weapon maps weapon instance_id → damage bonus from adjacent reactors/etc.
	var total_damage := 0
	var total_ap := 0
	var per_weapon: Dictionary = {}

	for item: PlacedItem in get_functional_items():
		if item.data.is_weapon():
			var dmg_bonus := get_adjacency_damage_bonus_for(item)
			per_weapon[item.instance_id] = dmg_bonus
			total_damage += dmg_bonus

		if item.data.adjacency_ap_bonus > 0:
			for neighbour: PlacedItem in get_adjacent_items(item):
				if neighbour.data.is_weapon() and is_item_functional(neighbour):
					total_ap += item.data.adjacency_ap_bonus
					break

	return {
		"damage_bonus": total_damage,
		"ap_bonus": total_ap,
		"per_weapon": per_weapon,
	}


func get_total_max_ap_bonus() -> int:
	var bonus := 0
	var adj := get_adjacent_bonuses()
	for item: PlacedItem in get_functional_items():
		bonus += item.data.max_ap_bonus
	bonus += int(adj["ap_bonus"])
	return bonus


# ---------------------------------------------------------------------------
# Corruption lifecycle
# ---------------------------------------------------------------------------

func corrupt_cell(cell_pos: Vector2i, duration: int = 1) -> bool:
	## Locks a cell as CORRUPTED ('X') and force-unequips any item covering it.
	if not is_unlocked(cell_pos):
		return false
	var key := cell_key(cell_pos)
	_corruption[key] = maxi(int(_corruption.get(key, 0)), duration)

	var occ := get_occupant(cell_pos)
	if occ != null and occ.data != null:
		var data: ItemData = occ.data
		# Remove without double inventory_changed; rebuild after.
		items.erase(occ)
		EventBus.item_removed.emit(data.id)
		item_unequipped.emit(data, "corrupted")

	_rebuild_cell_states()
	recalculate_grid_adjacencies()
	EventBus.cell_corrupted.emit(cell_pos, duration)
	changed.emit()
	EventBus.inventory_changed.emit()
	return true


func corrupt_random_unlocked_cell(duration: int) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for cell: Vector2i in get_unlocked_cells():
		candidates.append(cell)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	candidates.shuffle()
	var chosen: Vector2i = candidates[0]
	corrupt_cell(chosen, duration)
	return chosen


func tick_corruption() -> void:
	## Call at end of each combat round (after enemy turn).
	var cleared: Array[Vector2i] = []
	var keys: Array = _corruption.keys()
	for key in keys:
		_corruption[key] = int(_corruption[key]) - 1
		if _corruption[key] <= 0:
			_corruption.erase(key)
			var parts: PackedStringArray = str(key).split(",")
			cleared.append(Vector2i(int(parts[0]), int(parts[1])))
	for cell: Vector2i in cleared:
		EventBus.cell_corruption_cleared.emit(cell)
	if not cleared.is_empty():
		_rebuild_cell_states()
		changed.emit()
		EventBus.inventory_changed.emit()


func clear_all_corruption() -> void:
	## Repair station.
	var keys: Array = _corruption.keys()
	_corruption.clear()
	for key in keys:
		var parts: PackedStringArray = str(key).split(",")
		EventBus.cell_corruption_cleared.emit(Vector2i(int(parts[0]), int(parts[1])))
	_rebuild_cell_states()
	changed.emit()
	EventBus.inventory_changed.emit()
	EventBus.repair_station_used.emit()


func find_first_harmful_right_in_row(origin_item: PlacedItem) -> PlacedItem:
	## First harmful module sharing this row whose cells lie strictly right of origin_item.
	if origin_item == null or origin_item.data == null:
		return null
	var row_ys: Dictionary = {}
	var right_edge := origin_item.origin.x + origin_item.data.size.x - 1
	for cell: Vector2i in origin_item.occupied_cells():
		row_ys[cell.y] = true
	var best: PlacedItem = null
	var best_x := 1_000_000
	for other: PlacedItem in items:
		if other == null or other == origin_item or other.data == null:
			continue
		if not other.data.is_harmful:
			continue
		var min_x_right := 1_000_000
		for cell: Vector2i in other.occupied_cells():
			if not row_ys.has(cell.y):
				continue
			if cell.x <= right_edge:
				continue
			min_x_right = mini(min_x_right, cell.x)
		if min_x_right < best_x:
			best_x = min_x_right
			best = other
	return best
