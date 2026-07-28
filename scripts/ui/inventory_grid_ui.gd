class_name InventoryGridUI
extends Control
## Body-grid inventory UI — no external stash.
## Drag modules on the grid; RMB while dragging rotates; invalid drops snap back.

signal cell_clicked(cell: Vector2i)
signal item_drag_started(item: ItemData, source: String)
signal item_drag_ended(item: ItemData, success: bool)
signal item_moved(item: ItemData, from_origin: Vector2i, to_origin: Vector2i)
signal item_inspected(item: ItemData)
signal item_activated(placed: PlacedItem)
signal close_requested
signal layout_fitted(min_size: Vector2)

const CELL_SIZE := 48.0
const CELL_GAP := 4.0
const RESERVED_ROWS_TOP := 2
const RESERVED_ROWS_BOTTOM := 2
const DRAG_TYPE := "framewrack_item"
const INSPECT_MODAL_SCENE := preload("res://scenes/UI/item_inspect_modal.tscn")

var inventory: InventoryController
## When set, LMB on items activates combat modules instead of dragging.
var combat_manager: Node
var combat_click_mode: bool = false

## Active drag session (shared Dictionary mutated for rotation).
var _drag: Dictionary = {}
var _drop_committed: bool = false
var _suppress_refresh: bool = false
var _hover_origin: Vector2i = Vector2i(-1, -1)

var _slots: Dictionary = {}  # "x,y" -> InventorySlotUI
var _item_uis: Array[ItemUI] = []
var _hover_tooltip: ItemHoverTooltip
var _hovered_item_ui: ItemUI
var _context_menu: ItemContextMenu
var _inspect_modal: ItemInspectModal

@onready var _grid_host: Control = %GridHost
@onready var _grid_root: GridContainer = %GridRoot
@onready var _mutation_label: Label = %MutationLabel
@onready var _item_layer: Control = %ItemLayer
@onready var _title: Label = %Title
@onready var _close_button: Button = %CloseButton
@onready var _padding: MarginContainer = %Padding


func setup(p_inventory: InventoryController) -> void:
	inventory = p_inventory
	_ensure_hover_tooltip()
	_ensure_context_menu()
	_ensure_inspect_modal()
	if not EventBus.inventory_changed.is_connected(_on_inventory_changed):
		EventBus.inventory_changed.connect(_on_inventory_changed)
	if not EventBus.grid_expanded.is_connected(_on_grid_expanded):
		EventBus.grid_expanded.connect(_on_grid_expanded)
	if not EventBus.placement_failed.is_connected(_on_placement_failed):
		EventBus.placement_failed.connect(_on_placement_failed)
	if not LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.connect(_on_language_changed)
	if not EventBus.combat_item_availability_changed.is_connected(_refresh_combat_item_visuals):
		EventBus.combat_item_availability_changed.connect(_refresh_combat_item_visuals)
	if not EventBus.ap_changed.is_connected(_on_ap_changed_visuals):
		EventBus.ap_changed.connect(_on_ap_changed_visuals)
	if _close_button and not _close_button.pressed.is_connected(_on_close_pressed):
		_close_button.pressed.connect(_on_close_pressed)
	_apply_static_locale()
	refresh()


func set_combat_mode(enabled: bool, p_combat: Node = null) -> void:
	combat_click_mode = enabled
	combat_manager = p_combat if enabled else null
	_hide_hover_tooltip()
	_close_context_menu()
	refresh()


func _on_ap_changed_visuals(_current: int, _maximum: int) -> void:
	_refresh_combat_item_visuals()


func _ensure_hover_tooltip() -> void:
	if _hover_tooltip != null and is_instance_valid(_hover_tooltip):
		return
	_hover_tooltip = ItemHoverTooltip.new()
	_hover_tooltip.name = "ItemHoverTooltip"
	add_child(_hover_tooltip)


func _ensure_context_menu() -> void:
	if _context_menu != null and is_instance_valid(_context_menu):
		return
	_context_menu = ItemContextMenu.new()
	_context_menu.name = "ItemContextMenu"
	_context_menu.inspect_pressed.connect(_on_context_inspect_pressed)
	add_child(_context_menu)


func _ensure_inspect_modal() -> void:
	if _inspect_modal != null and is_instance_valid(_inspect_modal):
		return
	_inspect_modal = INSPECT_MODAL_SCENE.instantiate() as ItemInspectModal
	_inspect_modal.name = "ItemInspectModal"
	_inspect_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inspect_modal.offset_left = 0
	_inspect_modal.offset_top = 0
	_inspect_modal.offset_right = 0
	_inspect_modal.offset_bottom = 0
	## Parent to the current scene root so the overlay covers the whole UI.
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	host.add_child(_inspect_modal)


func _hide_hover_tooltip() -> void:
	_hovered_item_ui = null
	if _hover_tooltip:
		_hover_tooltip.hide_tooltip()


func _close_context_menu() -> void:
	if _context_menu:
		_context_menu.close()


func _on_language_changed(_locale: String) -> void:
	_apply_static_locale()
	_hide_hover_tooltip()
	refresh()


func _apply_static_locale() -> void:
	if _title:
		_title.text = tr("KEY_BODY_GRID_TITLE")
	if _close_button:
		_close_button.text = "✕"
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
	_hide_hover_tooltip()
	_close_context_menu()
	_item_uis.clear()
	if _item_layer == null:
		return

	for child in _item_layer.get_children():
		child.queue_free()

	var g: BodyGrid = inventory.grid
	g.recalculate_grid_adjacencies()
	for placed: PlacedItem in g.items:
		var ui := ItemUI.new()
		ui.setup(placed.data, self, CELL_SIZE, CELL_GAP, placed.origin)
		ui.position = _origin_to_layer_pos(placed.origin)
		ui.combat_click_mode = combat_click_mode
		ui.context_menu_requested.connect(_on_item_context_menu_requested)
		ui.pointer_down.connect(_on_item_pointer_down)
		ui.activate_requested.connect(_on_item_activate_requested)
		ui.mouse_entered.connect(_on_item_mouse_entered.bind(ui))
		ui.mouse_exited.connect(_on_item_mouse_exited.bind(ui))
		_item_layer.add_child(ui)
		_item_uis.append(ui)
		if combat_click_mode and combat_manager != null and combat_manager.has_method("can_activate_item"):
			ui.set_combat_visual(combat_manager.can_activate_item(placed))

	call_deferred("_fit_layers")


func _fit_layers() -> void:
	if inventory == null or _grid_root == null:
		return
	var g: BodyGrid = inventory.grid
	var w := g.width * CELL_SIZE + maxi(g.width - 1, 0) * CELL_GAP
	var h := g.height * CELL_SIZE + maxi(g.height - 1, 0) * CELL_GAP
	var row_stride := CELL_SIZE + CELL_GAP
	var top_pad := RESERVED_ROWS_TOP * row_stride
	var bottom_pad := RESERVED_ROWS_BOTTOM * row_stride
	var host_h := h + top_pad + bottom_pad
	if _grid_host:
		_grid_host.custom_minimum_size = Vector2(w, host_h)
		_grid_host.size = Vector2(w, host_h)
	_grid_root.position = Vector2(0, top_pad)
	_grid_root.size = Vector2(w, h)
	if _item_layer:
		_item_layer.position = Vector2(0, top_pad)
		_item_layer.custom_minimum_size = Vector2(w, h)
		_item_layer.size = Vector2(w, h)
		_item_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	update_minimum_size()
	var content_min := _padding.get_combined_minimum_size() if _padding else get_combined_minimum_size()
	custom_minimum_size = content_min
	layout_fitted.emit(content_min)


func _on_close_pressed() -> void:
	close_requested.emit()


func _origin_to_layer_pos(origin: Vector2i) -> Vector2:
	return Vector2(
		origin.x * (CELL_SIZE + CELL_GAP),
		origin.y * (CELL_SIZE + CELL_GAP),
	)


func _on_slot_gui_input(event: InputEvent, cell: Vector2i) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		cell_clicked.emit(cell)


func _on_item_context_menu_requested(item: ItemData) -> void:
	## RMB on a static item (ignored while a drag session is active).
	if not _drag.is_empty():
		return
	if item == null:
		return
	_hide_hover_tooltip()
	_ensure_context_menu()
	_context_menu.open_for_item(item, get_global_mouse_position())


func _on_context_inspect_pressed(item: ItemData) -> void:
	_close_context_menu()
	_hide_hover_tooltip()
	if item == null:
		return
	if inventory != null:
		inventory.grid.recalculate_grid_adjacencies()
	_ensure_inspect_modal()
	if _inspect_modal:
		_inspect_modal.open_item(item)
	item_inspected.emit(item)


func _on_item_activate_requested(item_ui: ItemUI) -> void:
	if not combat_click_mode or item_ui == null or inventory == null:
		return
	var placed: PlacedItem = inventory.grid.get_occupant(item_ui.grid_origin)
	if placed == null:
		return
	item_activated.emit(placed)


func _refresh_combat_item_visuals() -> void:
	if not combat_click_mode or combat_manager == null or inventory == null:
		return
	for ui: ItemUI in _item_uis:
		if not is_instance_valid(ui):
			continue
		ui.combat_click_mode = true
		var placed: PlacedItem = inventory.grid.get_occupant(ui.grid_origin)
		if placed != null and combat_manager.has_method("can_activate_item"):
			ui.set_combat_visual(combat_manager.can_activate_item(placed))
		else:
			ui.set_combat_visual(false)


func _on_item_pointer_down(_item_ui: ItemUI) -> void:
	## LMB pressed on an item — hide tooltip / menu before drag or activation.
	_hide_hover_tooltip()
	_close_context_menu()


func _on_item_mouse_entered(item_ui: ItemUI) -> void:
	if not _drag.is_empty():
		return
	if item_ui == null or item_ui.item == null:
		return
	_hovered_item_ui = item_ui
	_ensure_hover_tooltip()
	if inventory != null:
		inventory.grid.recalculate_grid_adjacencies()
	_hover_tooltip.request_show_for_item(item_ui.item)


func _on_item_mouse_exited(item_ui: ItemUI) -> void:
	if _hovered_item_ui == item_ui:
		_hide_hover_tooltip()


# ---------------------------------------------------------------------------
# Drag session — grid only; invalid drop restores previous grid position
# ---------------------------------------------------------------------------

func begin_item_drag(item_ui: ItemUI) -> Dictionary:
	if combat_click_mode:
		return {}
	if inventory == null or item_ui == null or item_ui.item == null:
		return {}
	if not _drag.is_empty():
		return {}
	if item_ui.grid_origin.x < 0:
		return {}

	## Tooltip / context menu must hide immediately on LMB pickup.
	_hide_hover_tooltip()
	_close_context_menu()

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
		_hide_hover_tooltip()
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
	_hide_hover_tooltip()
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
