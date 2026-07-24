class_name InventoryGrid
extends Control
## Control-facing facade over BodyGrid (the authoritative body inventory model).
## Prefer wiring UI through InventoryController; use this node when you want
## grid signals and placement helpers directly on a scene Control.
##
## Cell states: EMPTY | OCCUPIED | CORRUPTED (see BodyGrid.CellState).

signal grid_changed
signal grid_layout_updated
signal item_placed(item: ItemData, origin: Vector2i)
signal item_unequipped(item: ItemData, reason: String)
signal placement_rejected(reason: String)

@export var grid_width: int = 4
@export var grid_height: int = 4

var model: BodyGrid


func _ready() -> void:
	if model == null:
		bind_model(BodyGrid.new(grid_width, grid_height))


func bind_model(grid: BodyGrid) -> void:
	if model != null:
		if model.changed.is_connected(_on_model_changed):
			model.changed.disconnect(_on_model_changed)
		if model.item_unequipped.is_connected(_on_model_unequipped):
			model.item_unequipped.disconnect(_on_model_unequipped)
		if model.grid_layout_updated.is_connected(_on_model_layout_updated):
			model.grid_layout_updated.disconnect(_on_model_layout_updated)
	model = grid
	model.changed.connect(_on_model_changed)
	model.item_unequipped.connect(_on_model_unequipped)
	model.grid_layout_updated.connect(_on_model_layout_updated)
	grid_changed.emit()


func get_cell_state(cell: Vector2i) -> BodyGrid.CellState:
	return model.get_cell_state(cell)


func can_place_item(item: ItemData, top_left_pos: Vector2i) -> bool:
	return model.can_place_item(item, top_left_pos)


func place_item(item: ItemData, top_left_pos: Vector2i) -> bool:
	var reason := model.can_place(item, top_left_pos)
	if reason != "":
		placement_rejected.emit(reason)
		EventBus.placement_failed.emit(reason)
		return false
	var placed = model.place_item(item, top_left_pos)
	if placed == null:
		return false
	item_placed.emit(item, top_left_pos)
	return true


func corrupt_cell(cell_pos: Vector2i, duration: int = 1) -> bool:
	## Locks cell as CORRUPTED and force-unequips any covering item.
	return model.corrupt_cell(cell_pos, duration)


func get_adjacent_bonuses() -> Dictionary:
	## { "damage_bonus": int, "ap_bonus": int, "per_weapon": Dictionary }
	return model.get_adjacent_bonuses()


func recalculate_grid_adjacencies() -> void:
	## For each placed item: gather orthogonal neighbours, evaluate traits,
	## then notify UI (gray-out inactive traits / disabled icons).
	if model == null:
		return
	model.recalculate_grid_adjacencies()


func _on_model_changed() -> void:
	grid_changed.emit()


func _on_model_layout_updated() -> void:
	grid_layout_updated.emit()


func _on_model_unequipped(item: ItemData, reason: String) -> void:
	item_unequipped.emit(item, reason)
