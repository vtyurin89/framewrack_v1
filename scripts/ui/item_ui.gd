class_name ItemUI
extends Control
## Draggable visual for a body-module on the grid.
## RMB opens the inventory context menu when not dragging;
## rotation is handled by InventoryGridUI only during an active LMB drag.

signal drag_begun(item_ui: ItemUI)
signal drag_finished(item_ui: ItemUI, success: bool)
signal context_menu_requested(item: ItemData)
signal pointer_down(item_ui: ItemUI)
signal activate_requested(item_ui: ItemUI)

const DRAG_TYPE := "framewrack_item"

var item: ItemData
var grid_origin: Vector2i = Vector2i(-1, -1)
var cell_size: float = 48.0
var cell_gap: float = 4.0
## When true, LMB activates the item instead of starting a drag (combat).
var combat_click_mode: bool = false
var combat_usable_glow: bool = false

var _grid_ui: Node  # InventoryGridUI
var _panel: Panel
var _icon: TextureRect
var _label: Label
var _dragging: bool = false


func setup(
	p_item: ItemData,
	p_grid_ui: Node,
	p_cell_size: float = 48.0,
	p_cell_gap: float = 4.0,
	p_grid_origin: Vector2i = Vector2i(-1, -1),
) -> void:
	item = p_item
	_grid_ui = p_grid_ui
	cell_size = p_cell_size
	cell_gap = p_cell_gap
	grid_origin = p_grid_origin
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_build_visual()
	_apply_footprint_size(item.size if item else Vector2i.ONE)


func _build_visual() -> void:
	for child in get_children():
		child.queue_free()

	_panel = Panel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var style := StyleBoxFlat.new()
	var col := item.placeholder_color if item else Color(0.7, 0.7, 0.7)
	style.bg_color = col
	style.set_border_width_all(2)
	style.border_color = col.lightened(0.25)
	style.set_corner_radius_all(3)
	_panel.add_theme_stylebox_override("panel", style)

	if item and item.get_texture():
		_icon = TextureRect.new()
		_icon.texture = item.get_texture()
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon)

	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08))
	_label.text = _display_label(item)
	add_child(_label)

	if item != null and item.is_stackable and item.current_stack > 1:
		var stack := Label.new()
		stack.text = "×%d" % item.current_stack
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stack.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.offset_right = -3.0
		stack.offset_bottom = -2.0
		stack.add_theme_font_size_override("font_size", 12)
		stack.add_theme_color_override("font_color", Color(1, 1, 1))
		stack.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		stack.add_theme_constant_override("outline_size", 4)
		add_child(stack)


func _apply_footprint_size(footprint: Vector2i) -> void:
	var w := footprint.x * cell_size + maxi(footprint.x - 1, 0) * cell_gap
	var h := footprint.y * cell_size + maxi(footprint.y - 1, 0) * cell_gap
	custom_minimum_size = Vector2(w, h)
	size = custom_minimum_size


func _display_label(p_item: ItemData) -> String:
	if p_item == null:
		return "?"
	if p_item.is_stackable:
		return _short_name(p_item.get_localized_name())
	return _short_name(p_item.get_localized_name())


func _short_name(full: String) -> String:
	var parts := full.split(" ")
	if parts.is_empty():
		return "?"
	return parts[0].substr(0, 4).to_upper()


func set_combat_visual(usable: bool) -> void:
	combat_usable_glow = usable
	if _panel == null:
		return
	var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return
	var col := item.placeholder_color if item else Color(0.7, 0.7, 0.7)
	if combat_click_mode and usable:
		style.border_color = Color(0.45, 0.95, 0.55)
		style.set_border_width_all(3)
		modulate = Color(1, 1, 1, 1)
	elif combat_click_mode:
		style.border_color = col.darkened(0.35)
		style.set_border_width_all(2)
		modulate = Color(0.55, 0.55, 0.55, 1)
	else:
		style.border_color = col.lightened(0.25)
		style.set_border_width_all(2)
		modulate = Color(1, 1, 1, 1)
	_panel.add_theme_stylebox_override("panel", style)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			pointer_down.emit(self)
			if combat_click_mode and not _dragging and item != null:
				activate_requested.emit(self)
				accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			## RMB on a static item opens the inventory context menu.
			if not _dragging and item != null:
				context_menu_requested.emit(item)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _dragging:
		_dragging = false
		var success := get_viewport().gui_is_drag_successful()
		drag_finished.emit(self, success)
		if _grid_ui and _grid_ui.has_method("end_item_drag"):
			_grid_ui.end_item_drag(success)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if combat_click_mode:
		return null
	if item == null or _grid_ui == null:
		return null
	if not _grid_ui.has_method("begin_item_drag"):
		return null

	var session: Dictionary = _grid_ui.begin_item_drag(self)
	if session.is_empty():
		return null

	_dragging = true
	visible = false
	drag_begun.emit(self)

	var preview := build_drag_preview(item, session["footprint"], cell_size, cell_gap)
	session["preview"] = preview
	set_drag_preview(preview)
	return session


static func build_drag_preview(
	p_item: ItemData,
	footprint: Vector2i,
	p_cell_size: float,
	p_cell_gap: float,
) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := footprint.x * p_cell_size + maxi(footprint.x - 1, 0) * p_cell_gap
	var h := footprint.y * p_cell_size + maxi(footprint.y - 1, 0) * p_cell_gap
	root.custom_minimum_size = Vector2(w, h)
	root.size = Vector2(w, h)
	root.modulate = Color(1, 1, 1, 0.55)

	for y in footprint.y:
		for x in footprint.x:
			var cell := Panel.new()
			cell.position = Vector2(
				x * (p_cell_size + p_cell_gap),
				y * (p_cell_size + p_cell_gap),
			)
			cell.size = Vector2(p_cell_size, p_cell_size)
			var style := StyleBoxFlat.new()
			var col := p_item.placeholder_color if p_item else Color(0.7, 0.7, 0.7)
			style.bg_color = col
			style.set_border_width_all(1)
			style.border_color = Color(1, 1, 1, 0.7)
			style.set_corner_radius_all(2)
			cell.add_theme_stylebox_override("panel", style)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(cell)

	var caption := Label.new()
	caption.text = p_item.get_localized_name() if p_item else ""
	caption.position = Vector2(4, 4)
	caption.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(caption)
	root.pivot_offset = Vector2.ZERO
	return root
