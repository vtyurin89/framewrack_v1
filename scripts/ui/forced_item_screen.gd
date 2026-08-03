class_name ForcedItemScreen
extends Control
## Mid-combat harmful item insertion: drag parasite from Space into Body Grid.

signal finished
signal notice_requested(message: String)
signal continue_availability_changed(can_continue: bool)

const CELL := 48.0
const GAP := 4.0
const FLOAT_AMPLITUDE := 6.0
const FLOAT_DURATION := 1.4

@onready var _space: Control = %SpaceArea
@onready var _notice: Label = %NoticeLabel

var inventory: InventoryController
var inventory_ui: Control
var required_item: ItemData
var _floating_entries: Array[Dictionary] = []
var _hover_tooltip: ItemHoverTooltip
var _active: bool = false
var _required_instance_id: int = 0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _notice:
		_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _space:
		_space.mouse_filter = Control.MOUSE_FILTER_STOP
		if _space.has_method("setup"):
			_space.call("setup", self)


func is_active() -> bool:
	return _active


func can_continue() -> bool:
	return _active and required_item != null and _is_required_in_grid()


func open_session(
	item: ItemData,
	p_inventory: InventoryController,
	p_inventory_ui: Control
) -> void:
	inventory = p_inventory
	inventory_ui = p_inventory_ui
	required_item = item
	_required_instance_id = item.get_instance_id() if item != null else 0
	_clear_floating()
	visible = true
	_active = true
	if inventory_ui != null:
		if inventory_ui.has_method("set_reward_handler"):
			inventory_ui.set_reward_handler(self)
		if inventory_ui.has_method("set_combat_mode"):
			inventory_ui.set_combat_mode(false)
		inventory_ui.refresh()
	await get_tree().process_frame
	if not _active:
		return
	_spawn_required_in_space()
	_emit_continue_state()


func confirm_and_finish() -> bool:
	## Destroys leftover Space items; requires harmful item already in the grid.
	if not can_continue():
		notice_requested.emit(tr("KEY_FORCED_INSERT_MUST_PLACE"))
		return false
	_destroy_space_items()
	_shutdown()
	finished.emit()
	return true


func close_session() -> void:
	_shutdown()


func can_accept_item_to_inventory(_item: ItemData, _show_notice: bool = false) -> bool:
	## No pick limit during forced insertion.
	return true


func on_item_placed_in_inventory(item: ItemData) -> void:
	_remove_floating_for_item(item)
	_emit_continue_state()


func on_item_extracted_to_space(item: ItemData, at_global: Vector2) -> void:
	if item == null:
		return
	_add_floating_item(item, at_global)
	_emit_continue_state()


func _spawn_required_in_space() -> void:
	if required_item == null or _space == null:
		return
	var area := _space.size
	if area.x < 8.0 or area.y < 8.0:
		area = Vector2(520, 260)
	var pos := Vector2(area.x * 0.5 - 24.0, area.y * 0.35)
	_add_floating_item(required_item, _space.global_position + pos)


func _add_floating_item(item: ItemData, global_pos: Vector2) -> void:
	if item == null or _space == null:
		return
	for entry in _floating_entries:
		if entry.get("item") == item:
			return
	var ui := _make_floating_item_ui(item)
	_space.add_child(ui)
	ui.global_position = global_pos
	var base_y := ui.position.y
	var tween := create_tween().set_loops()
	tween.tween_property(ui, "position:y", base_y - FLOAT_AMPLITUDE, FLOAT_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(ui, "position:y", base_y + FLOAT_AMPLITUDE, FLOAT_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_floating_entries.append({"item": item, "ui": ui, "tween": tween, "base_y": base_y})


func _make_floating_item_ui(item: ItemData) -> Control:
	var wrap := FloatingLootItem.new()
	wrap.setup(item, inventory_ui, CELL, GAP)
	wrap.hover_entered.connect(_on_floating_hover)
	wrap.hover_exited.connect(_on_floating_hover_exit)
	wrap.context_pressed.connect(_on_floating_context)
	wrap.drag_begun.connect(_on_floating_drag_begun)
	return wrap


func _on_floating_drag_begun(wrap: Control, _item: ItemData) -> void:
	if _hover_tooltip:
		_hover_tooltip.hide_tooltip()
	_kill_float_tween(wrap)
	_floating_entries = _floating_entries.filter(
		func(e: Dictionary) -> bool: return e.get("ui") != wrap
	)


func _on_floating_context(item: ItemData) -> void:
	if inventory_ui != null and inventory_ui.has_method("open_item_context_menu"):
		inventory_ui.open_item_context_menu(item)
	elif inventory_ui != null and inventory_ui.has_method("inspect_item"):
		inventory_ui.inspect_item(item)
	else:
		_on_floating_hover(item)


func _on_floating_hover(item: ItemData) -> void:
	_ensure_tooltip()
	if _hover_tooltip:
		_hover_tooltip.request_show_for_item(item)


func _on_floating_hover_exit() -> void:
	if _hover_tooltip:
		_hover_tooltip.hide_tooltip()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and str(data.get("type", "")) == ItemUI.DRAG_TYPE


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return
	var item: ItemData = data.get("item")
	if item == null:
		return
	## During forced insertion, beneficial items may be ejected to Space.
	## The required harmful item may also return to Space (Continue stays locked).
	if inventory_ui != null and inventory_ui.has_method("commit_external_drop"):
		inventory_ui.commit_external_drop()
	var global_pos := _space.get_global_transform() * at_position
	global_pos -= Vector2(40, 30)
	on_item_extracted_to_space(item, global_pos)


func _is_required_in_grid() -> bool:
	if inventory == null or inventory.grid == null or required_item == null:
		return false
	for placed: PlacedItem in inventory.grid.items:
		if placed == null or placed.data == null:
			continue
		if placed.data == required_item:
			return true
		if placed.data.get_instance_id() == _required_instance_id:
			return true
		if (
			placed.data.id.strip_edges().to_upper() == required_item.id.strip_edges().to_upper()
			and placed.data.is_harmful
		):
			return true
	return false


func _destroy_space_items() -> void:
	## Anything still floating is permanently destroyed.
	for entry in _floating_entries:
		var ui: Control = entry.get("ui") as Control
		if ui != null and is_instance_valid(ui):
			ui.queue_free()
	_floating_entries.clear()


func _remove_floating_for_item(item: ItemData) -> void:
	var keep: Array[Dictionary] = []
	for entry in _floating_entries:
		if entry.get("item") == item:
			var ui: Control = entry.get("ui") as Control
			_kill_float_tween(ui)
			if ui != null and is_instance_valid(ui):
				ui.queue_free()
			continue
		keep.append(entry)
	_floating_entries = keep


func _kill_float_tween(ui: Control) -> void:
	for entry in _floating_entries:
		if entry.get("ui") == ui:
			var tw: Tween = entry.get("tween") as Tween
			if tw != null:
				tw.kill()
			break


func _clear_floating() -> void:
	_destroy_space_items()


func _emit_continue_state() -> void:
	continue_availability_changed.emit(can_continue())


func _shutdown() -> void:
	_active = false
	visible = false
	if inventory_ui != null and inventory_ui.has_method("set_reward_handler"):
		inventory_ui.set_reward_handler(null)
	_clear_floating()
	required_item = null
	_required_instance_id = 0
	continue_availability_changed.emit(false)


func _ensure_tooltip() -> void:
	if _hover_tooltip != null and is_instance_valid(_hover_tooltip):
		return
	_hover_tooltip = ItemHoverTooltip.new()
	add_child(_hover_tooltip)
