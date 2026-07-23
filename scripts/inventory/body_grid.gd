class_name BodyGrid
extends RefCounted
## Spatial inventory — the player's body.
## Supports irregular unlocked shapes, edge placement rules,
## adjacency queries, and temporary corruption locks.

signal changed

const DEFAULT_SIZE := Vector2i(4, 4)

## Bounding box of the grid (may contain locked/unavailable cells).
var width: int = DEFAULT_SIZE.x
var height: int = DEFAULT_SIZE.y

## Cells the player may use. Key = "x,y"
var _unlocked: Dictionary = {}

## Corrupted cells: Key = "x,y" → remaining turns (>0).
var _corruption: Dictionary = {}

## Placed modules.
var items: Array[PlacedItem] = []


func _init(p_width: int = DEFAULT_SIZE.x, p_height: int = DEFAULT_SIZE.y) -> void:
	width = p_width
	height = p_height
	_unlock_rectangle(0, 0, width, height)


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


func is_edge_cell(cell: Vector2i) -> bool:
	## Edge relative to the unlocked shape's bounding extremes among unlocked cells.
	## For MVP: edge of the rectangular bounding box of unlocked cells,
	## OR any unlocked cell that has a missing orthogonal unlocked neighbour.
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
	# Also treat bounding-box border as edge.
	return cell.x == 0 or cell.y == 0 or cell.x == width - 1 or cell.y == height - 1


func get_occupant(cell: Vector2i) -> PlacedItem:
	for item: PlacedItem in items:
		if cell in item.occupied_cells():
			return item
	return null


func is_cell_free(cell: Vector2i) -> bool:
	return is_unlocked(cell) and get_occupant(cell) == null


# ---------------------------------------------------------------------------
# Unlock / expand (mutation hook)
# ---------------------------------------------------------------------------

func _unlock_rectangle(ox: int, oy: int, w: int, h: int) -> void:
	for y in h:
		for x in w:
			_unlocked[cell_key(Vector2i(ox + x, oy + y))] = true


func unlock_cells(cells: Array[Vector2i]) -> void:
	## Expand the body — visual mutation should react to EventBus.grid_expanded.
	var added: Array[Vector2i] = []
	for cell: Vector2i in cells:
		# Grow bounding box if needed.
		if cell.x >= width:
			width = cell.x + 1
		if cell.y >= height:
			height = cell.y + 1
		var key := cell_key(cell)
		if not _unlocked.has(key):
			_unlocked[key] = true
			added.append(cell)
	if not added.is_empty():
		EventBus.grid_expanded.emit(added)
		changed.emit()
		EventBus.inventory_changed.emit()


func get_unlocked_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for key: String in _unlocked.keys():
		var parts := key.split(",")
		result.append(Vector2i(int(parts[0]), int(parts[1])))
	return result


# ---------------------------------------------------------------------------
# Placement validation & mutation
# ---------------------------------------------------------------------------

func can_place(data: ItemData, origin: Vector2i) -> String:
	## Returns empty string on success, otherwise a human-readable failure reason.
	if data == null:
		return "No item data."
	var cells := data.footprint_cells(origin)
	var touches_edge := false
	for cell: Vector2i in cells:
		if not is_in_bounds(cell) or not is_unlocked(cell):
			return "Outside unlocked body grid."
		if get_occupant(cell) != null:
			return "Cell occupied."
		if is_corrupted(cell):
			return "Cell corrupted — repair required."
		if is_edge_cell(cell):
			touches_edge = true
	if data.requires_edge and not touches_edge:
		return "Item requires edge placement."
	return ""


func place_item(data: ItemData, origin: Vector2i) -> PlacedItem:
	var reason := can_place(data, origin)
	if reason != "":
		EventBus.placement_failed.emit(reason)
		return null
	var placed := PlacedItem.new(data, origin)
	items.append(placed)
	changed.emit()
	EventBus.item_placed.emit(data.id, origin)
	EventBus.inventory_changed.emit()
	return placed


func remove_item(placed: PlacedItem) -> void:
	if placed == null:
		return
	items.erase(placed)
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
		if is_corrupted(cell):
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


func get_adjacency_damage_bonus_for(weapon: PlacedItem) -> int:
	## Sum adjacency_damage_bonus from functional neighbours (e.g. Micro-Reactor).
	var bonus := 0
	for neighbour: PlacedItem in get_adjacent_items(weapon):
		if not is_item_functional(neighbour):
			continue
		bonus += neighbour.data.adjacency_damage_bonus
	return bonus


func get_total_max_ap_bonus() -> int:
	var bonus := 0
	for item: PlacedItem in get_functional_items():
		bonus += item.data.max_ap_bonus
		# Adjacency AP: reactors grant adjacency_ap_bonus once if next to any weapon.
		if item.data.adjacency_ap_bonus > 0:
			for neighbour: PlacedItem in get_adjacent_items(item):
				if neighbour.data.is_weapon() and is_item_functional(neighbour):
					bonus += item.data.adjacency_ap_bonus
					break
	return bonus


# ---------------------------------------------------------------------------
# Corruption lifecycle
# ---------------------------------------------------------------------------

func corrupt_cell(cell: Vector2i, duration: int) -> bool:
	if not is_unlocked(cell):
		return false
	var key := cell_key(cell)
	# Refresh duration if already corrupted.
	_corruption[key] = maxi(int(_corruption.get(key, 0)), duration)
	EventBus.cell_corrupted.emit(cell, duration)
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
		changed.emit()
		EventBus.inventory_changed.emit()


func clear_all_corruption() -> void:
	## Repair station.
	var keys: Array = _corruption.keys()
	_corruption.clear()
	for key in keys:
		var parts: PackedStringArray = str(key).split(",")
		EventBus.cell_corruption_cleared.emit(Vector2i(int(parts[0]), int(parts[1])))
	changed.emit()
	EventBus.inventory_changed.emit()
	EventBus.repair_station_used.emit()
