class_name DebugCatalogChip
extends Control
## Fixed-size drag source for DebugItemsModal rows (icon only, clipped).

const CHIP := 44.0

var catalog: DebugItemsModal
var proto: ItemData
var _dragging: bool = false


func setup(p_proto: ItemData, p_catalog: DebugItemsModal, _cell: float = 40.0, _gap: float = 3.0) -> void:
	proto = p_proto
	catalog = p_catalog
	custom_minimum_size = Vector2(CHIP, CHIP)
	size = custom_minimum_size
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	_build_icon()


func _build_icon() -> void:
	for child in get_children():
		child.queue_free()
	if proto == null:
		return

	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	InventoryTheme.apply_item_panel(panel, proto, 1)

	var tex := proto.get_texture()
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 3.0
		icon.offset_top = 3.0
		icon.offset_right = -3.0
		icon.offset_bottom = -3.0
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon)
	else:
		var lbl := Label.new()
		lbl.text = proto.get_localized_name().left(2).to_upper()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lbl)


func _get_drag_data(at_position: Vector2) -> Variant:
	if catalog == null or proto == null or ItemDatabase == null:
		return null
	var inv_ui: Control = catalog.inventory_ui
	if inv_ui == null or not inv_ui.has_method("begin_debug_item_drag"):
		return null
	var inst: ItemData = ItemDatabase.create_instance(proto.id)
	if inst == null:
		return null
	if inv_ui.has_method("set_reward_handler"):
		inv_ui.set_reward_handler(catalog)
	var shape: Array = inst.get_effective_shape() if inst.has_custom_shape() else []
	var grab := (
		ItemData.icon_anchor_of(inst.get_effective_shape())
		if inst.has_custom_shape()
		else Vector2i.ZERO
	)
	var session: Dictionary = inv_ui.begin_debug_item_drag(inst, grab)
	if session.is_empty():
		return null
	_dragging = true
	## Chip is not footprint-sized — pin the hub/elbow cell under the cursor.
	var preview := ItemUI.build_drag_preview(
		inst,
		inst.size,
		InventoryGridUI.CELL_SIZE,
		InventoryGridUI.CELL_GAP,
		shape
	)
	var wrapped := ItemUI.wrap_preview_cell_at_cursor(
		preview,
		at_position,
		grab,
		InventoryGridUI.CELL_SIZE,
		InventoryGridUI.CELL_GAP
	)
	session["preview"] = preview
	set_drag_preview(wrapped)
	return session


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _dragging:
		_dragging = false
		if catalog != null and catalog.inventory_ui != null:
			if catalog.inventory_ui.has_method("end_item_drag"):
				catalog.inventory_ui.end_item_drag(get_viewport().gui_is_drag_successful())
