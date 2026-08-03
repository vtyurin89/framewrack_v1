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
	p_inventory_ui: Control
) -> void:
	inventory = p_inventory
	inventory_ui = p_inventory_ui
	_clear_floating()
	RewardManager.begin_session(loot)
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
	RewardManager.clear_session()


func can_accept_item_to_inventory(item: ItemData, show_notice: bool = false) -> bool:
	if not RewardManager.can_pick_new_item(item):
		if show_notice:
			_show_notice(tr("KEY_REWARD_PICK_LIMIT"))
			RewardManager.pick_limit_reached.emit()
		return false
	return true


func on_item_placed_in_inventory(item: ItemData) -> void:
	RewardManager.notify_new_item_picked(item)
	_remove_floating_for_item(item)


func on_item_extracted_to_space(item: ItemData, at_global: Vector2) -> void:
	if item == null:
		return
	RewardManager.notify_new_item_unpicked(item)
	_add_floating_item(item, at_global, RewardManager.is_new_loot(item))


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
	ui.global_position = global_pos
	var base_y := ui.position.y
	var tween := create_tween().set_loops()
	tween.tween_property(ui, "position:y", base_y - FLOAT_AMPLITUDE, FLOAT_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(ui, "position:y", base_y + FLOAT_AMPLITUDE, FLOAT_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_floating_entries.append({"item": item, "ui": ui, "tween": tween, "is_new": is_new, "base_y": base_y})


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
	if inventory_ui != null and inventory_ui.has_method("inspect_item"):
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
	if inventory_ui != null and inventory_ui.has_method("commit_external_drop"):
		inventory_ui.commit_external_drop()
	var global_pos := _space.get_global_transform() * at_position
	global_pos -= Vector2(40, 30)
	on_item_extracted_to_space(item, global_pos)


func _clear_floating() -> void:
	for entry in _floating_entries:
		var tween: Tween = entry.get("tween")
		if tween != null and tween.is_valid():
			tween.kill()
		var ui: Control = entry.get("ui")
		if ui != null and is_instance_valid(ui):
			ui.queue_free()
	_floating_entries.clear()


func _remove_floating_for_item(item: ItemData) -> void:
	var keep: Array[Dictionary] = []
	for entry in _floating_entries:
		if entry.get("item") == item:
			var tween: Tween = entry.get("tween")
			if tween != null and tween.is_valid():
				tween.kill()
			var ui: Control = entry.get("ui")
			if ui != null and is_instance_valid(ui):
				ui.queue_free()
		else:
			keep.append(entry)
	_floating_entries = keep


func _kill_float_tween(wrap: Control) -> void:
	for entry in _floating_entries:
		if entry.get("ui") == wrap:
			var tween: Tween = entry.get("tween")
			if tween != null and tween.is_valid():
				tween.kill()
			break


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
