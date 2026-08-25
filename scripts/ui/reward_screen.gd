class_name RewardScreen
extends Control
## Floating loot hosted inside CombatUI's LootStage (same fight window).
## Continue is the combat UI button — this panel only owns Space + pick rules.

signal finished
signal notice_requested(message: String)

const CELL := 48.0
const GAP := 4.0
const FLOAT_AMPLITUDE := 6.0
const FLOAT_DURATION := 1.4
const RETURN_DURATION := 0.38

@onready var _fog: ColorRect = %Fog
@onready var _title: Label = %TitleLabel
@onready var _notice: Label = %NoticeLabel
@onready var _continue_btn: Button = %ContinueButton
@onready var _space: Control = %SpaceArea
@onready var _inventory_host: Control = %InventoryHost

var inventory: InventoryController
var inventory_ui: Control
var _floating_entries: Array[Dictionary] = []
var _hover_tooltip: ItemHoverTooltip
var _active: bool = false
## Space→Space drop target (global), consumed by return_floating_to_space.
var _pending_space_return: Dictionary = {}  # instance_id -> Vector2


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _fog:
		_fog.visible = false
	if _title:
		_title.visible = false
	if _continue_btn:
		_continue_btn.visible = false
	if _notice:
		_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _space:
		_space.mouse_filter = Control.MOUSE_FILTER_STOP
		if _space is RewardSpaceArea:
			(_space as RewardSpaceArea).setup(self)
	_ensure_tooltip()


func is_active() -> bool:
	return _active


func open_session(
	loot: Array[ItemData],
	p_inventory: InventoryController,
	p_inventory_ui: Control,
	max_picks: int = -1
) -> void:
	inventory = p_inventory
	inventory_ui = p_inventory_ui
	_clear_floating()
	_pending_space_return.clear()
	var picks := max_picks if max_picks > 0 else RewardManager.MAX_PICKS
	RewardManager.begin_session(loot, picks)
	visible = true
	_active = true
	if _notice:
		_notice.text = ""
		_notice.visible = false
	if inventory_ui != null:
		if inventory_ui.has_method("set_reward_handler"):
			inventory_ui.set_reward_handler(self)
		if inventory_ui.has_method("set_combat_mode"):
			inventory_ui.set_combat_mode(false)
		inventory_ui.refresh()
	await get_tree().process_frame
	if not _active:
		return
	_spawn_loot_in_space(loot)


func confirm_and_finish() -> void:
	## Called by Main when the combat Continue button is pressed.
	if not _active:
		return
	_clear_floating()
	_pending_space_return.clear()
	_active = false
	visible = false
	if inventory_ui != null and inventory_ui.has_method("set_reward_handler"):
		inventory_ui.set_reward_handler(null)
	RewardManager.clear_session()
	finished.emit()


func close_session() -> void:
	_active = false
	visible = false
	if inventory_ui != null and inventory_ui.has_method("set_reward_handler"):
		inventory_ui.set_reward_handler(null)
	_clear_floating()
	_pending_space_return.clear()
	RewardManager.clear_session()


func can_accept_item_to_inventory(item: ItemData, show_notice: bool = false) -> bool:
	if not RewardManager.can_pick_new_item(item):
		if show_notice:
			if RewardManager.session_max_picks <= 1:
				_show_notice(tr("KEY_REWARD_PICK_LIMIT_ONE"))
			else:
				_show_notice(tr("KEY_REWARD_PICK_LIMIT"))
			RewardManager.pick_limit_reached.emit()
		return false
	return true


func on_item_placed_in_inventory(item: ItemData) -> void:
	RewardManager.notify_new_item_picked(item)
	## Detach tracking only — FloatingLootItem queue_frees itself on committed drag end.
	_detach_floating_entry(item, false)


func on_item_extracted_to_space(item: ItemData, at_global: Vector2) -> void:
	## Grid → Space (new chip). Space → Space uses return_floating_to_space instead.
	if item == null:
		return
	RewardManager.notify_new_item_unpicked(item)
	_add_floating_item(item, _clamp_global_to_space(at_global, item), RewardManager.is_new_loot(item))


func return_floating_to_space(item: ItemData, from_global: Vector2) -> void:
	## Failed inventory drop / cancelled drag: fly the existing chip back into Space.
	if item == null or _space == null:
		return
	var id := item.get_instance_id()
	var target_global: Vector2
	if _pending_space_return.has(id):
		target_global = _clamp_global_to_space(_pending_space_return[id] as Vector2, item)
		_pending_space_return.erase(id)
	else:
		var entry: Dictionary = _find_entry(item)
		if not entry.is_empty():
			var home: Vector2 = entry.get("home_pos", Vector2.ZERO) as Vector2
			target_global = _space.global_position + home
		else:
			target_global = _clamp_global_to_space(from_global, item)

	var entry2: Dictionary = _find_entry(item)
	var ui: Control = null
	if not entry2.is_empty():
		ui = entry2.get("ui") as Control
	if ui == null or not is_instance_valid(ui):
		_add_floating_item(item, target_global, RewardManager.is_new_loot(item))
		return

	_kill_float_tween(ui)
	ui.visible = true
	ui.z_index = 30
	ui.global_position = from_global
	var target_local: Vector2 = _clamp_local_in_space(ui, _global_to_space_local(target_global))
	if not entry2.is_empty():
		entry2["home_pos"] = target_local
		entry2["base_y"] = target_local.y
		entry2["dragging"] = false

	var fly := create_tween()
	fly.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	fly.tween_property(ui, "position", target_local, RETURN_DURATION)
	fly.finished.connect(_on_return_fly_finished.bind(item), CONNECT_ONE_SHOT)


func recover_space_item_if_lost(item: ItemData, from_global: Vector2) -> void:
	## Safety net: drag marked committed but item is neither in grid nor visible in Space.
	if item == null:
		return
	if _item_in_inventory(item):
		## Placed successfully — leave UI freeing to FloatingLootItem drag-end.
		_detach_floating_entry(item, false)
		return
	var entry: Dictionary = _find_entry(item)
	if not entry.is_empty():
		var ui: Control = entry.get("ui") as Control
		if ui != null and is_instance_valid(ui) and ui.visible:
			return
	return_floating_to_space(item, from_global)


func _on_return_fly_finished(item: ItemData) -> void:
	var entry: Dictionary = _find_entry(item)
	if entry.is_empty():
		return
	var ui: Control = entry.get("ui") as Control
	if ui == null or not is_instance_valid(ui):
		return
	ui.z_index = 0
	_start_bob(entry)


func _spawn_loot_in_space(loot: Array[ItemData]) -> void:
	if _space == null:
		return
	var area := _space.size
	if area.x < 8.0 or area.y < 8.0:
		area = Vector2(520, 260)
	var count := loot.size()
	var i := 0
	for item in loot:
		if item == null:
			continue
		var cols := mini(maxi(count, 1), 4)
		var col := i % cols
		var row := int(i / cols)
		var pos := Vector2(
			area.x * 0.12 + float(col) * (area.x * 0.22) + randf_range(-14.0, 14.0),
			area.y * 0.15 + float(row) * 90.0 + randf_range(-10.0, 10.0)
		)
		pos.x = clampf(pos.x, 16.0, maxf(area.x - 80.0, 16.0))
		pos.y = clampf(pos.y, 12.0, maxf(area.y - 70.0, 12.0))
		_add_floating_item(item, _space.global_position + pos, true)
		i += 1


func _add_floating_item(item: ItemData, global_pos: Vector2, is_new: bool) -> void:
	if item == null or _space == null:
		return
	for entry in _floating_entries:
		if entry.get("item") == item:
			return
	var ui := _make_floating_item_ui(item)
	_space.add_child(ui)
	ui.global_position = _clamp_global_to_space(global_pos, item)
	var home := ui.position
	if ui is FloatingLootItem:
		(ui as FloatingLootItem).home_local = home
	var entry := {
		"item": item,
		"ui": ui,
		"tween": null,
		"is_new": is_new,
		"base_y": home.y,
		"home_pos": home,
		"dragging": false,
	}
	_floating_entries.append(entry)
	_start_bob(entry)


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
	## Keep the entry so a rejected drop can fly the same chip home.
	_kill_float_tween(wrap)
	for entry in _floating_entries:
		if entry.get("ui") != wrap:
			continue
		entry["dragging"] = true
		if wrap is FloatingLootItem:
			var fl := wrap as FloatingLootItem
			## Capture rest pose (not bob peak).
			var home: Vector2 = entry.get("home_pos", fl.home_local)
			if home == Vector2.ZERO:
				home = Vector2(wrap.position.x, float(entry.get("base_y", wrap.position.y)))
			entry["home_pos"] = home
			fl.home_local = home
		break


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
	var source := str(data.get("source", ""))
	var global_pos := _space.get_global_transform() * at_position
	global_pos -= Vector2(40, 30)
	if source == "grid":
		## Inventory → Space discard respects dropable (reject without commit → snap back).
		if not item.dropable:
			_show_notice(tr("KEY_REWARD_NOT_DROPPABLE"))
			return
		if inventory_ui != null and inventory_ui.has_method("commit_external_drop"):
			inventory_ui.commit_external_drop()
		on_item_extracted_to_space(item, global_pos)
		return
	## Space → Space: reposition existing chip on drag end (do not mark inventory-committed).
	_pending_space_return[item.get_instance_id()] = global_pos


func _clear_floating() -> void:
	for entry in _floating_entries:
		var tween: Tween = entry.get("tween")
		if tween != null and tween.is_valid():
			tween.kill()
		var ui: Control = entry.get("ui")
		if ui != null and is_instance_valid(ui):
			ui.queue_free()
	_floating_entries.clear()


func _detach_floating_entry(item: ItemData, free_ui: bool) -> void:
	var keep: Array[Dictionary] = []
	for entry in _floating_entries:
		if entry.get("item") == item:
			_kill_float_tween(entry.get("ui") as Control)
			var ui: Control = entry.get("ui")
			if free_ui and ui != null and is_instance_valid(ui):
				ui.queue_free()
		else:
			keep.append(entry)
	_floating_entries = keep


func _remove_floating_for_item(item: ItemData) -> void:
	_detach_floating_entry(item, true)


func _find_entry(item: ItemData) -> Dictionary:
	if item == null:
		return {}
	for entry: Dictionary in _floating_entries:
		if entry.get("item") == item:
			return entry
	return {}


func _item_in_inventory(item: ItemData) -> bool:
	if item == null or inventory == null or inventory.grid == null:
		return false
	for placed: PlacedItem in inventory.grid.items:
		if placed != null and placed.data == item:
			return true
	return false


func _start_bob(entry: Dictionary) -> void:
	var ui: Control = entry.get("ui") as Control
	if ui == null or not is_instance_valid(ui):
		return
	_kill_float_tween(ui)
	var base_y := float(entry.get("base_y", ui.position.y))
	ui.position.y = base_y
	var tween := create_tween().set_loops()
	tween.tween_property(ui, "position:y", base_y - FLOAT_AMPLITUDE, FLOAT_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(ui, "position:y", base_y + FLOAT_AMPLITUDE, FLOAT_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	entry["tween"] = tween


func _kill_float_tween(wrap: Control) -> void:
	if wrap == null:
		return
	for entry in _floating_entries:
		if entry.get("ui") != wrap:
			continue
		var tween: Tween = entry.get("tween")
		if tween != null and tween.is_valid():
			tween.kill()
		entry["tween"] = null
		break


func _clamp_global_to_space(global_pos: Vector2, item: ItemData) -> Vector2:
	if _space == null:
		return global_pos
	var local: Vector2 = _global_to_space_local(global_pos)
	var size: Vector2 = _item_pixel_size(item)
	local = _clamp_local_raw(local, size)
	return _space.global_position + local


func _global_to_space_local(global_pos: Vector2) -> Vector2:
	## UI Controls are axis-aligned; avoid CanvasItem.to_local (not available on all builds).
	if _space == null:
		return global_pos
	return global_pos - _space.global_position


func _clamp_local_in_space(ui: Control, local: Vector2) -> Vector2:
	var size := ui.size if ui != null else Vector2(CELL, CELL)
	return _clamp_local_raw(local, size)


func _clamp_local_raw(local: Vector2, item_size: Vector2) -> Vector2:
	if _space == null:
		return local
	var area := _space.size
	if area.x < 8.0 or area.y < 8.0:
		return local
	var max_x := maxf(area.x - item_size.x - 4.0, 4.0)
	var max_y := maxf(area.y - item_size.y - 4.0, 4.0)
	return Vector2(clampf(local.x, 4.0, max_x), clampf(local.y, 4.0, max_y))


func _item_pixel_size(item: ItemData) -> Vector2:
	if item == null:
		return Vector2(CELL, CELL)
	return Vector2(
		float(item.size.x) * (CELL + GAP) - GAP,
		float(item.size.y) * (CELL + GAP) - GAP
	)


func _show_notice(text: String) -> void:
	if _notice:
		_notice.text = text
		_notice.visible = true
	notice_requested.emit(text)


func _ensure_tooltip() -> void:
	if _hover_tooltip != null and is_instance_valid(_hover_tooltip):
		return
	_hover_tooltip = ItemHoverTooltip.new()
	_hover_tooltip.name = "RewardHoverTooltip"
	add_child(_hover_tooltip)
