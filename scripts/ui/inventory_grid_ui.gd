class_name InventoryGridUI
extends Control
## Body-grid inventory UI — no external stash.
## Drag modules on the grid; RMB while dragging rotates; invalid drops snap back.

signal cell_clicked(cell: Vector2i)
signal item_drag_started(item: ItemData, source: String)
signal item_drag_ended(item: ItemData, success: bool)
signal item_moved(item: ItemData, from_origin: Vector2i, to_origin: Vector2i)

const CELL_SIZE := 48.0
const CELL_GAP := 4.0
const DRAG_TYPE := "framewrack_item"

var inventory: InventoryController

## Active drag session (shared Dictionary mutated for rotation).
var _drag: Dictionary = {}
var _drop_committed: bool = false
var _suppress_refresh: bool = false
var _hover_origin: Vector2i = Vector2i(-1, -1)

var _slots: Dictionary = {}  # "x,y" -> InventorySlotUI
var _item_uis: Array[ItemUI] = []

@onready var _grid_host: Control = %GridHost
@onready var _grid_root: GridContainer = %GridRoot
@onready var _mutation_label: Label = %MutationLabel
@onready var _item_layer: Control = %ItemLayer
@onready var _title: Label = %Title


func setup(p_inventory: InventoryController) -> void:
	inventory = p_inventory
	if not EventBus.inventory_changed.is_connected(_on_inventory_changed):
		EventBus.inventory_changed.connect(_on_inventory_changed)
	if not EventBus.grid_expanded.is_connected(_on_grid_expanded):
		EventBus.grid_expanded.connect(_on_grid_expanded)
	if not EventBus.placement_failed.is_connected(_on_placement_failed):
		EventBus.placement_failed.connect(_on_placement_failed)
	if not LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.connect(_on_language_changed)
	_apply_static_locale()
	refresh()


func _on_language_changed(_locale: String) -> void:
	_apply_static_locale()
	refresh()


func _apply_static_locale() -> void:
	if _title:
		_title.text = tr("KEY_BODY_GRID_TITLE")
	if _mutation_label and _drag.is_empty():
		if (
			_mutation_label.text.is_empty()
			or _mutation_label.text.begins_with("MUTATION: mechanical")
			or _mutation_label.text.begins_with("МУТАЦИЯ: механический")
		):
			_mutation_label.text = tr("KEY_MUTATION_DEFAULT")


func refresh() -> void:
	if inventory == null or _suppress_refresh:
		return
	_rebuild_grid()
	_rebuild_items()


func _on_inventory_changed() -> void:
	refresh()


func _on_grid_expanded(new_cells: Array[Vector2i]) -> void:
	_mutation_label.text = tr("KEY_MUTATION_OVERLAY_FMT") % new_cells.size()
	refresh()


func _on_placement_failed(_reason: String) -> void:
	pass


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _rebuild_grid() -> void:
	for child in _grid_root.get_children():
		child.queue_free()
	_slots.clear()

	var g: BodyGrid = inventory.grid
	_grid_root.columns = g.width
	_grid_root.add_theme_constant_override("h_separation", int(CELL_GAP))
	_grid_root.add_theme_constant_override("v_separation", int(CELL_GAP))

	for y in g.height:
		for x in g.width:
			var cell := Vector2i(x, y)
			var slot := InventorySlotUI.new()
			slot.setup(cell, self, CELL_SIZE)
			slot.apply_cell_state(
				g.is_unlocked(cell),
				g.is_corrupted(cell),
				g.is_edge_cell(cell),
				g.get_corruption_turns(cell),
			)
			slot.gui_input.connect(_on_slot_gui_input.bind(cell))
			_grid_root.add_child(slot)
			_slots[BodyGrid.cell_key(cell)] = slot

	call_deferred("_fit_layers")


func _rebuild_items() -> void:
	_item_uis.clear()
	if _item_layer == null:
		return

	for child in _item_layer.get_children():
		child.queue_free()

	var g: BodyGrid = inventory.grid
	for placed: PlacedItem in g.items:
		var ui := ItemUI.new()
		ui.setup(placed.data, self, CELL_SIZE, CELL_GAP, placed.origin)
		ui.position = _origin_to_layer_pos(placed.origin)
		_item_layer.add_child(ui)
		_item_uis.append(ui)

	call_deferred("_fit_layers")


func _fit_layers() -> void:
	if inventory == null or _grid_root == null:
		return
	var g: BodyGrid = inventory.grid
	var w := g.width * CELL_SIZE + maxi(g.width - 1, 0) * CELL_GAP
	var h := g.height * CELL_SIZE + maxi(g.height - 1, 0) * CELL_GAP
	if _grid_host:
		_grid_host.custom_minimum_size = Vector2(w, h)
		_grid_host.size = Vector2(w, h)
	_grid_root.position = Vector2.ZERO
	_grid_root.size = Vector2(w, h)
	if _item_layer:
		_item_layer.position = Vector2.ZERO
		_item_layer.custom_minimum_size = Vector2(w, h)
		_item_layer.size = Vector2(w, h)
		_item_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _origin_to_layer_pos(origin: Vector2i) -> Vector2:
	return Vector2(
		origin.x * (CELL_SIZE + CELL_GAP),
		origin.y * (CELL_SIZE + CELL_GAP),
	)


func _on_slot_gui_input(event: InputEvent, cell: Vector2i) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		cell_clicked.emit(cell)


# ---------------------------------------------------------------------------
# Drag session — grid only; invalid drop restores previous grid position
# ---------------------------------------------------------------------------

func begin_item_drag(item_ui: ItemUI) -> Dictionary:
	if inventory == null or item_ui == null or item_ui.item == null:
		return {}
	if not _drag.is_empty():
		return {}
	if item_ui.grid_origin.x < 0:
		return {}

	_suppress_refresh = true
	_drop_committed = false
	_hover_origin = Vector2i(-1, -1)

	var original_size := item_ui.item.size
	var original_origin := item_ui.grid_origin
	var extracted: ItemData = inventory.extract_from_grid(item_ui.grid_origin)
	if extracted == null:
		_suppress_refresh = false
		return {}

	_drag = {
		"type": DRAG_TYPE,
		"item": extracted,
		"footprint": extracted.size,
		"original_size": original_size,
		"source": "grid",
		"original_origin": original_origin,
		"preview": null,
	}

	_set_item_uis_pass_through(true)
	_refresh_slots_only()
	item_drag_started.emit(extracted, "grid")
	return _drag


func end_item_drag(_success: bool) -> void:
	if _drag.is_empty():
		_suppress_refresh = false
		_set_item_uis_pass_through(false)
		return

	var item: ItemData = _drag["item"]
	var committed := _drop_committed
	## Any failed / off-grid drop cancels and snaps back to the previous cell.
	if not committed:
		_restore_drag_item()
	item_drag_ended.emit(item, committed)

	_clear_highlights()
	_drag.clear()
	_drop_committed = false
	_hover_origin = Vector2i(-1, -1)
	_set_item_uis_pass_through(false)
	_suppress_refresh = false
	EventBus.inventory_changed.emit()
	refresh()


func _restore_drag_item() -> void:
	if _drag.is_empty():
		return
	var item: ItemData = _drag["item"]
	item.size = _drag["original_size"]
	var origin: Vector2i = _drag["original_origin"]
	inventory.grid.place_item(item, origin, item.size)


func _set_item_uis_pass_through(enabled: bool) -> void:
	var filter := Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP
	for ui in _item_uis:
		if is_instance_valid(ui):
			ui.mouse_filter = filter


# ---------------------------------------------------------------------------
# Hover validation / highlights
# ---------------------------------------------------------------------------

func on_slot_drag_hover(cell: Vector2i, data: Variant) -> void:
	if not _is_drag(data):
		return
	if cell == _hover_origin and data.get("footprint") == _drag.get("footprint"):
		return
	_hover_origin = cell
	_update_footprint_highlights(cell, data)


func can_drop_on_cell(cell: Vector2i, data: Variant) -> bool:
	if not _is_drag(data) or inventory == null:
		return false
	var item: ItemData = data["item"]
	var footprint: Vector2i = data["footprint"]
	return inventory.grid.can_place_item(item, cell, footprint)


func drop_on_cell(cell: Vector2i, data: Variant) -> void:
	if not _is_drag(data) or inventory == null:
		return
	var item: ItemData = data["item"]
	var footprint: Vector2i = data["footprint"]
	if not inventory.place_dragged(item, cell, footprint):
		## Invalid cell — leave uncommitted so end_item_drag snaps back.
		return

	_drop_committed = true
	var from_origin: Vector2i = data.get("original_origin", Vector2i(-1, -1))
	if from_origin.x >= 0:
		item_moved.emit(item, from_origin, cell)
	_clear_highlights()


func _update_footprint_highlights(origin: Vector2i, data: Variant) -> void:
	_clear_highlights()
	if not _is_drag(data) or inventory == null:
		return
	var item: ItemData = data["item"]
	var footprint: Vector2i = data["footprint"]
	var valid := inventory.grid.can_place_item(item, origin, footprint)
	var cells: Array[Vector2i] = item.footprint_for(footprint, origin)
	var mode := (
		InventorySlotUI.Highlight.VALID if valid else InventorySlotUI.Highlight.INVALID
	)
	for cell: Vector2i in cells:
		var slot: InventorySlotUI = _slots.get(BodyGrid.cell_key(cell))
		if slot:
			slot.set_highlight(mode)


func _clear_highlights() -> void:
	_refresh_slots_only()


func _refresh_slots_only() -> void:
	if inventory == null:
		return
	var g: BodyGrid = inventory.grid
	for key: String in _slots.keys():
		var slot: InventorySlotUI = _slots[key]
		var cell := slot.cell
		slot.apply_cell_state(
			g.is_unlocked(cell),
			g.is_corrupted(cell),
			g.is_edge_cell(cell),
			g.get_corruption_turns(cell),
		)


# ---------------------------------------------------------------------------
# Rotation — RMB while dragging ONLY (static RMB does nothing)
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _drag.is_empty():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_rotate_drag()
			get_viewport().set_input_as_handled()


func _rotate_drag() -> void:
	if _drag.is_empty():
		return
	var footprint: Vector2i = _drag["footprint"]
	footprint = Vector2i(footprint.y, footprint.x)
	_drag["footprint"] = footprint

	var preview: Control = _drag.get("preview")
	var item: ItemData = _drag["item"]
	if preview and is_instance_valid(preview):
		_rebuild_preview_node(preview, item, footprint)

	if _hover_origin.x >= 0:
		_update_footprint_highlights(_hover_origin, _drag)


func _rebuild_preview_node(preview: Control, item: ItemData, footprint: Vector2i) -> void:
	while preview.get_child_count() > 0:
		var child := preview.get_child(0)
		preview.remove_child(child)
		child.free()

	var w := footprint.x * CELL_SIZE + maxi(footprint.x - 1, 0) * CELL_GAP
	var h := footprint.y * CELL_SIZE + maxi(footprint.y - 1, 0) * CELL_GAP
	preview.custom_minimum_size = Vector2(w, h)
	preview.size = Vector2(w, h)

	for y in footprint.y:
		for x in footprint.x:
			var cell := Panel.new()
			cell.position = Vector2(x * (CELL_SIZE + CELL_GAP), y * (CELL_SIZE + CELL_GAP))
			cell.size = Vector2(CELL_SIZE, CELL_SIZE)
			var style := StyleBoxFlat.new()
			var col := item.placeholder_color if item else Color(0.7, 0.7, 0.7)
			style.bg_color = col
			style.set_border_width_all(1)
			style.border_color = Color(1, 1, 1, 0.7)
			style.set_corner_radius_all(2)
			cell.add_theme_stylebox_override("panel", style)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			preview.add_child(cell)

	var caption := Label.new()
	caption.text = item.get_localized_name() if item else ""
	caption.position = Vector2(4, 4)
	caption.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(caption)


static func _is_drag(data: Variant) -> bool:
	return data is Dictionary and data.get("type", "") == DRAG_TYPE
