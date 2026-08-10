class_name ShopScreen
extends Control
## Merchant shop UI: floating stock + drag-to-Body-Grid. Trade logic lives in ShopManager.

signal finished
signal notice_requested(message: String)

const CELL := 48.0
const GAP := 4.0
const FLOAT_AMPLITUDE := 6.0
const FLOAT_DURATION := 1.4
const RETURN_DURATION := 0.38

@onready var _fog: ColorRect = %Fog
@onready var _title: Label = %TitleLabel
@onready var _chips_label: Label = %ChipsLabel
@onready var _notice: Label = %NoticeLabel
@onready var _continue_btn: Button = %ContinueButton
@onready var _space: Control = %SpaceArea

var inventory: InventoryController
var inventory_ui: Control
var _floating_entries: Array[Dictionary] = []
var _hover_tooltip: ItemHoverTooltip
var _active: bool = false
var _pending_space_return: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	## Hosted in CombatUI LootStage like RewardScreen — no full-screen fog overlay.
	if _fog:
		_fog.visible = false
		_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _title:
		_title.visible = false
		_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _chips_label:
		_chips_label.visible = false
		_chips_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _continue_btn:
		## Continue lives on CombatUI (same as post-combat rewards).
		_continue_btn.visible = false
		if not _continue_btn.pressed.is_connected(_on_continue_pressed):
			_continue_btn.pressed.connect(_on_continue_pressed)
		_style_continue_button()
	if _notice:
		_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _space:
		_space.mouse_filter = Control.MOUSE_FILTER_STOP
		if _space is ShopSpaceArea:
			(_space as ShopSpaceArea).setup(self)
	if GameManager != null and not GameManager.chips_changed.is_connected(_on_chips_changed):
		GameManager.chips_changed.connect(_on_chips_changed)
	if ShopManager != null and not ShopManager.purchase_failed.is_connected(_on_purchase_failed):
		ShopManager.purchase_failed.connect(_on_purchase_failed)
	if not LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.connect(_on_language_changed)
	_ensure_tooltip()
	_apply_static_texts()


func is_active() -> bool:
	return _active


func open_session(
	p_inventory: InventoryController,
	p_inventory_ui: Control
) -> void:
	## Expects ShopManager.begin_session() already called with priced stock.
	## Layout: floating stock in CombatUI LootStage (left); Body Grid docked right.
	inventory = p_inventory
	inventory_ui = p_inventory_ui
	_clear_floating()
	_pending_space_return.clear()
	visible = true
	_active = true
	_apply_static_texts()
	_refresh_chips_label()
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
	var stock: Array[ItemData] = []
	if ShopManager != null:
		stock = ShopManager.stock_items.duplicate()
	_spawn_stock_in_space(stock)


func confirm_and_finish() -> void:
	## Called by Main when CombatUI Continue is pressed.
	if not _active:
		return
	_clear_floating()
	_pending_space_return.clear()
	_active = false
	visible = false
	if inventory_ui != null and inventory_ui.has_method("set_reward_handler"):
		inventory_ui.set_reward_handler(null)
	if ShopManager != null:
		ShopManager.clear_session()
	finished.emit()


func close_session() -> void:
	_active = false
	visible = false
	if inventory_ui != null and inventory_ui.has_method("set_reward_handler"):
		inventory_ui.set_reward_handler(null)
	_clear_floating()
	_pending_space_return.clear()
	if ShopManager != null:
		ShopManager.clear_session()


func get_item_price(item: ItemData) -> int:
	if ShopManager == null:
		return 0
	return ShopManager.get_item_price(item)


func can_accept_item_to_inventory(item: ItemData, show_notice: bool = false) -> bool:
	if item == null or not _active:
		return false
	if ShopManager == null or not ShopManager.is_shop_stock(item):
		## Already owned grid moves stay allowed when handler is attached.
		return true
	if ShopManager.can_purchase(item):
		return true
	if show_notice:
		_show_notice(tr("KEY_SHOP_NOT_ENOUGH_CHIPS"))
	return false


func on_item_placed_in_inventory(item: ItemData) -> void:
	if item == null:
		return
	if ShopManager != null and ShopManager.is_shop_stock(item):
		ShopManager.try_purchase(item)
	_detach_floating_entry(item, false)
	_refresh_chips_label()


func on_item_extracted_to_space(_item: ItemData, _at_global: Vector2) -> void:
	## Selling is disabled — inventory drops onto Space are rejected by _drop_data.
	pass


func return_floating_to_space(item: ItemData, from_global: Vector2) -> void:
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
		if ShopManager != null and ShopManager.is_shop_stock(item):
			_add_floating_item(item, target_global)
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
	if item == null:
		return
	if _item_in_inventory(item):
		_detach_floating_entry(item, false)
		return
	var entry: Dictionary = _find_entry(item)
	if not entry.is_empty():
		var ui: Control = entry.get("ui") as Control
		if ui != null and is_instance_valid(ui) and ui.visible:
			return
	return_floating_to_space(item, from_global)


func _on_continue_pressed() -> void:
	confirm_and_finish()


func _on_chips_changed(_amount: int) -> void:
	if _active:
		_refresh_chips_label()


func _on_purchase_failed(reason_key: String) -> void:
	if _active and not reason_key.is_empty():
		_show_notice(tr(reason_key))


func _on_language_changed(_lang: String = "") -> void:
	_apply_static_texts()
	_refresh_chips_label()
	_refresh_price_labels()


func _apply_static_texts() -> void:
	if _title:
		_title.text = tr("KEY_SHOP_TITLE")
	if _continue_btn:
		_continue_btn.text = tr("KEY_CONTINUE")


func _refresh_chips_label() -> void:
	if _chips_label == null:
		return
	var chips := GameManager.get_chips() if GameManager != null else 0
	_chips_label.text = tr("KEY_SHOP_CHIPS") % chips


func _refresh_price_labels() -> void:
	for entry in _floating_entries:
		var item: ItemData = entry.get("item")
		var ui: Control = entry.get("ui")
		if item == null or ui == null or not is_instance_valid(ui):
			continue
		var price_lbl := ui.get_node_or_null("PriceLabel") as Label
		if price_lbl:
			price_lbl.text = tr("KEY_SHOP_PRICE") % get_item_price(item)


func _style_continue_button() -> void:
	if _continue_btn == null:
		return
	_continue_btn.custom_minimum_size = Vector2(220, 52)
	_continue_btn.add_theme_font_size_override("font_size", 18)
	_continue_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.1, 0.12, 1)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.92, 0.55, 0.18, 1)
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(10)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16, 0.14, 0.12, 1)
	hover.border_color = Color(1.0, 0.7, 0.28, 1)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.08, 0.08, 0.09, 1)
	pressed.border_color = Color(0.75, 0.42, 0.12, 1)
	_continue_btn.add_theme_stylebox_override("normal", normal)
	_continue_btn.add_theme_stylebox_override("hover", hover)
	_continue_btn.add_theme_stylebox_override("pressed", pressed)
	_continue_btn.add_theme_stylebox_override("focus", hover)


func _spawn_stock_in_space(stock: Array[ItemData]) -> void:
	if _space == null:
		return
	var area := _space.size
	if area.x < 8.0 or area.y < 8.0:
		area = Vector2(520, 320)
	var count := stock.size()
	var i := 0
	for item in stock:
		if item == null:
			continue
		var cols := mini(maxi(count, 1), 3)
		var col := i % cols
		var row := int(i / cols)
		var pos := Vector2(
			area.x * 0.14 + float(col) * (area.x * 0.28) + randf_range(-10.0, 10.0),
			area.y * 0.18 + float(row) * 110.0 + randf_range(-8.0, 8.0)
		)
		pos.x = clampf(pos.x, 16.0, maxf(area.x - 80.0, 16.0))
		pos.y = clampf(pos.y, 12.0, maxf(area.y - 90.0, 12.0))
		_add_floating_item(item, _space.global_position + pos)
		i += 1


func _add_floating_item(item: ItemData, global_pos: Vector2) -> void:
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

	var price_lbl := Label.new()
	price_lbl.name = "PriceLabel"
	price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lbl.add_theme_font_size_override("font_size", 12)
	price_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1))
	price_lbl.text = tr("KEY_SHOP_PRICE") % get_item_price(item)
	price_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	price_lbl.offset_top = -2.0
	price_lbl.offset_bottom = 16.0
	wrap.add_child(price_lbl)
	## Extra height so the price sits under the icon without clipping.
	wrap.custom_minimum_size.y += 16.0
	wrap.size = wrap.custom_minimum_size
	return wrap


func _on_floating_drag_begun(wrap: Control, _item: ItemData) -> void:
	if _hover_tooltip:
		_hover_tooltip.hide_tooltip()
	_kill_float_tween(wrap)
	for entry in _floating_entries:
		if entry.get("ui") != wrap:
			continue
		entry["dragging"] = true
		if wrap is FloatingLootItem:
			var fl := wrap as FloatingLootItem
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
	## Allow repositioning shop chips; reject inventory dumps (no selling).
	if typeof(data) != TYPE_DICTIONARY or str(data.get("type", "")) != ItemUI.DRAG_TYPE:
		return false
	return str(data.get("source", "")) != "grid"


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		if typeof(data) == TYPE_DICTIONARY and str(data.get("source", "")) == "grid":
			_show_notice(tr("KEY_SHOP_NO_SELL"))
		return
	var item: ItemData = data.get("item")
	if item == null:
		return
	var global_pos := _space.get_global_transform() * at_position
	global_pos -= Vector2(40, 30)
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


func _on_return_fly_finished(item: ItemData) -> void:
	var entry: Dictionary = _find_entry(item)
	if entry.is_empty():
		return
	var ui: Control = entry.get("ui") as Control
	if ui == null or not is_instance_valid(ui):
		return
	ui.z_index = 0
	_start_bob(entry)


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
		return Vector2(CELL, CELL + 16.0)
	return Vector2(
		float(item.size.x) * (CELL + GAP) - GAP,
		float(item.size.y) * (CELL + GAP) - GAP + 16.0
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
	_hover_tooltip.name = "ShopHoverTooltip"
	add_child(_hover_tooltip)
