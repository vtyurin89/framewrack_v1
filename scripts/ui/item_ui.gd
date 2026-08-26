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
var _cd_label: Label
var _status_icon: Label
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
	InventoryTheme.apply_item_panel(_panel, item, 1)
	modulate = Color.WHITE

	var has_icon := _item_has_custom_icon(item)

	if has_icon:
		_icon = TextureRect.new()
		_icon.texture = item.get_texture()
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_icon.offset_left = 3.0
		_icon.offset_top = 3.0
		_icon.offset_right = -3.0
		_icon.offset_bottom = -3.0
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon)

	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text_col := InventoryTheme.text_color_for_item(item)
	_label.add_theme_color_override("font_color", text_col)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 3)
	## Icon tiles stay text-free; item name lives in tooltip/inspect UI.
	_label.text = ""
	_label.visible = false
	add_child(_label)

	_cd_label = Label.new()
	_cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cd_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cd_label.add_theme_font_size_override("font_size", 18)
	_cd_label.add_theme_color_override("font_color", GamePalette.COLOR_WARN)
	_cd_label.add_theme_color_override("font_outline_color", GamePalette.BACKGROUND_DARK)
	_cd_label.add_theme_constant_override("outline_size", 5)
	_cd_label.visible = false
	add_child(_cd_label)

	_status_icon = Label.new()
	_status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status_icon.add_theme_font_size_override("font_size", 20)
	_status_icon.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_status_icon.add_theme_constant_override("outline_size", 5)
	_status_icon.visible = false
	add_child(_status_icon)

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
		stack.add_theme_color_override("font_color", text_col)
		stack.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		stack.add_theme_constant_override("outline_size", 4)
		add_child(stack)


func _item_has_custom_icon(p_item: ItemData) -> bool:
	if p_item == null:
		return false
	var tex := p_item.get_texture()
	if tex == null:
		return false
	var path := tex.resource_path
	if path.is_empty():
		return true
	return path != ItemData.FALLBACK_ICON_PATH


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
	## Rebuild base palette, then layer combat usability cues on the border only.
	var border_w := 1
	if combat_click_mode and usable:
		border_w = 3
	elif combat_click_mode:
		border_w = 2
	InventoryTheme.apply_item_panel(_panel, item, border_w)
	var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return
	var harmful := item != null and item.is_harmful
	if combat_click_mode and usable:
		if harmful:
			## Surgery-removable parasites stay danger-red, never usable-green.
			style.border_color = InventoryTheme.colors_for_kind(
				InventoryTheme.PaletteKind.HARMFUL
			)["border"] as Color
			modulate = Color(1, 1, 1, 1)
			GamePalette.apply_phosphor_glow(self, false)
		else:
			style.border_color = GamePalette.PHOSPHOR_ACTIVE
			modulate = Color(1, 1, 1, 1)
			GamePalette.apply_phosphor_glow(self, true)
	elif combat_click_mode:
		modulate = Color(0.7, 0.75, 0.7, 1)
		GamePalette.apply_phosphor_glow(self, false)
	else:
		modulate = Color(1, 1, 1, 1)
		GamePalette.apply_phosphor_glow(self, false)
	_panel.add_theme_stylebox_override("panel", style)
	_refresh_status_overlay()


func _refresh_status_overlay() -> void:
	## LIFO primary status drives which overlay is shown.
	if _cd_label == null or _status_icon == null:
		return
	_cd_label.visible = false
	_cd_label.text = ""
	_status_icon.visible = false
	_status_icon.text = ""
	if item == null:
		return
	var primary := item.get_primary_status()
	if primary == null:
		return
	match primary.type:
		ItemStatus.Type.OVERLOAD:
			_status_icon.text = "⚡"
			_status_icon.add_theme_color_override("font_color", GamePalette.COLOR_WARN)
			_status_icon.visible = true
			_cd_label.text = str(primary.remaining_turns)
			_cd_label.visible = true
		ItemStatus.Type.COOLDOWN:
			_cd_label.text = str(primary.remaining_turns)
			_cd_label.visible = true
		ItemStatus.Type.TAINTED:
			_status_icon.text = "☣"
			_status_icon.add_theme_color_override("font_color", GamePalette.COLOR_DANGER)
			_status_icon.visible = true
		ItemStatus.Type.INACTIVE:
			_cd_label.text = str(primary.remaining_turns)
			_cd_label.visible = true
			_status_icon.text = "OFF"
			_status_icon.add_theme_color_override("font_color", GamePalette.INACTIVE_ELEMENT)
			_status_icon.visible = true


func _refresh_cooldown_overlay() -> void:
	_refresh_status_overlay()


func refresh_status_overlay() -> void:
	_refresh_status_overlay()


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
	root.modulate = Color(1, 1, 1, 0.7)

	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	InventoryTheme.apply_item_panel(panel, p_item, 1)
	root.add_child(panel)

	if p_item != null and p_item.get_texture() != null:
		var icon := TextureRect.new()
		icon.texture = p_item.get_texture()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 4.0
		icon.offset_top = 4.0
		icon.offset_right = -4.0
		icon.offset_bottom = -4.0
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(icon)

	root.pivot_offset = Vector2.ZERO
	return root
