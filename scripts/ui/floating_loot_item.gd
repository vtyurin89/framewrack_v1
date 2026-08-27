class_name FloatingLootItem
extends Control
## Draggable loot chip in the post-combat Space area.

signal context_pressed(item: ItemData)
signal hover_entered(item: ItemData)
signal hover_exited
signal drag_begun(wrap: Control, item: ItemData)

const CELL := 48.0
const GAP := 4.0

var item: ItemData
var inventory_ui: Node
var _dragging: bool = false
var _cell: float = CELL
var _gap: float = GAP
## Rest position in Space local coords (bob tween oscillates around this).
var home_local: Vector2 = Vector2.ZERO


func setup(p_item: ItemData, p_inventory_ui: Node, cell: float, gap: float) -> void:
	item = p_item
	inventory_ui = p_inventory_ui
	_cell = cell
	_gap = gap
	custom_minimum_size = Vector2(
		float(item.size.x) * (cell + gap) - gap,
		float(item.size.y) * (cell + gap) - gap
	)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var visual := ItemUI.new()
	visual.setup(item, inventory_ui, cell, gap, Vector2i(-1, -1))
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(visual)
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)


func _on_mouse_entered() -> void:
	hover_entered.emit(item)


func _on_mouse_exited() -> void:
	hover_exited.emit()


func _gui_input(event: InputEvent) -> void:
	## LMB drag is handled by `_get_drag_data` (viewport DnD). RMB = context menu.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			context_pressed.emit(item)
			accept_event()


func _get_drag_data(at_position: Vector2) -> Variant:
	if item == null or inventory_ui == null:
		return null
	if not inventory_ui.has_method("begin_reward_space_drag"):
		return null
	var shape: Array = item.get_effective_shape() if item.has_custom_shape() else []
	var grab := ItemUI.cell_offset_at(at_position, item, _cell, _gap, shape)
	var session: Dictionary = inventory_ui.begin_reward_space_drag(item, grab)
	if session.is_empty():
		return null
	_dragging = true
	drag_begun.emit(self, item)
	visible = false
	var preview := ItemUI.build_drag_preview(item, item.size, _cell, _gap, shape)
	session["preview"] = preview
	set_drag_preview(preview)
	return session


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _dragging:
		_dragging = false
		var committed := false
		if inventory_ui != null and inventory_ui.has_method("end_item_drag"):
			var result: Variant = inventory_ui.end_item_drag(
				get_viewport().gui_is_drag_successful()
			)
			if typeof(result) == TYPE_BOOL:
				committed = bool(result)
		if committed:
			## Inventory accepted the item — Space chip can go away.
			queue_free()
		## else: RewardScreen/ForcedItemScreen animates this wrap back home.


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	## Allow dropping onto another floating chip (treat as Space).
	var space := get_parent()
	if space != null and space.has_method("_can_drop_data"):
		return space._can_drop_data(position + at_position, data)
	return false


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var space := get_parent()
	if space != null and space.has_method("_drop_data"):
		space._drop_data(position + at_position, data)
