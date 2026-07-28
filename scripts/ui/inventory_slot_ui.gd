class_name InventorySlotUI
extends Control
## Single body-grid cell: drop target, coordinate mapping, hover highlight.

signal hover_with_drag(cell: Vector2i, drag_data: Variant)
signal drop_requested(cell: Vector2i, drag_data: Variant)

enum Highlight {
	NONE,
	VALID,
	INVALID,
	BASE,
	CORRUPTED,
	LOCKED,
}

const DRAG_TYPE := "framewrack_item"
const UNLOCK_FLASH_COLOR := Color(0.945, 0.765, 0.059, 1.0) ## #F1C40F
const UNLOCK_SCALE_DURATION := 0.35
const UNLOCK_FLASH_DURATION := 0.4

var cell: Vector2i = Vector2i.ZERO
var unlocked: bool = true
var _highlight: Highlight = Highlight.NONE
var _base_panel: Panel
var _label: Label
var _grid_ui: Node  # InventoryGridUI
var _unlock_tween: Tween


func setup(p_cell: Vector2i, p_grid_ui: Node, cell_size: float) -> void:
	cell = p_cell
	_grid_ui = p_grid_ui
	custom_minimum_size = Vector2(cell_size, cell_size)
	size = custom_minimum_size
	_ensure_center_pivot()
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	_ensure_visuals()
	set_highlight(Highlight.BASE)


func _ensure_center_pivot() -> void:
	## Scale unlock pop from the cell center.
	pivot_offset = custom_minimum_size * 0.5


func _ensure_visuals() -> void:
	if _base_panel:
		return
	_base_panel = Panel.new()
	_base_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_base_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_base_panel)

	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func apply_cell_state(is_unlocked: bool, is_corrupted: bool, is_edge: bool, corruption_turns: int = 0) -> void:
	unlocked = is_unlocked
	_ensure_visuals()
	_ensure_center_pivot()
	if not is_unlocked:
		## Locked / inactive cells stay in the matrix for layout, but are hidden by default.
		_kill_unlock_tween()
		scale = Vector2.ONE
		set_highlight(Highlight.LOCKED)
		_label.text = ""
		tooltip_text = ""
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		modulate = Color(1, 1, 1, 0)
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	## Don't clobber an in-flight unlock pop.
	if _unlock_tween == null or not is_instance_valid(_unlock_tween) or not _unlock_tween.is_running():
		modulate = Color(1, 1, 1, 1)
		scale = Vector2.ONE
	if is_corrupted:
		set_highlight(Highlight.CORRUPTED)
		_label.text = "X"
		_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.45))
		tooltip_text = tr("KEY_CORRUPTED_TURNS_FMT") % [tr("KEY_CORRUPTED"), corruption_turns]
		return
	set_highlight(Highlight.BASE)
	_label.text = ""
	tooltip_text = tr("KEY_EDGE_CELL") if is_edge else tr("KEY_BODY_CELL")


func play_unlock_pop(stagger_delay: float = 0.0) -> void:
	## Punchy scale pop + gold flash used when a locked cell becomes active.
	_kill_unlock_tween()
	_ensure_visuals()
	_ensure_center_pivot()
	mouse_filter = Control.MOUSE_FILTER_STOP
	scale = Vector2.ZERO
	modulate = UNLOCK_FLASH_COLOR
	## Bright gold panel flash, then restored by the modulate fade + final highlight.
	_apply_unlock_flash_style()

	_unlock_tween = create_tween()
	_unlock_tween.set_parallel(false)
	if stagger_delay > 0.0:
		_unlock_tween.tween_interval(stagger_delay)
	_unlock_tween.set_parallel(true)
	_unlock_tween.tween_property(self, "scale", Vector2.ONE, UNLOCK_SCALE_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_unlock_tween.tween_property(self, "modulate", Color.WHITE, UNLOCK_FLASH_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _unlock_tween.finished
	if not is_instance_valid(self):
		return
	scale = Vector2.ONE
	modulate = Color.WHITE
	if unlocked and _highlight == Highlight.BASE:
		set_highlight(Highlight.BASE)
	_unlock_tween = null


func _apply_unlock_flash_style() -> void:
	if _base_panel == null:
		return
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(2)
	style.set_border_width_all(2)
	style.bg_color = Color(0.945, 0.765, 0.059, 0.95)
	style.border_color = Color(1.0, 1.0, 1.0, 1.0)
	_base_panel.add_theme_stylebox_override("panel", style)


func _kill_unlock_tween() -> void:
	if _unlock_tween != null and is_instance_valid(_unlock_tween):
		_unlock_tween.kill()
	_unlock_tween = null


func set_highlight(mode: Highlight) -> void:
	_highlight = mode
	_ensure_visuals()
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(2)
	style.set_border_width_all(1)
	match mode:
		Highlight.VALID:
			style.bg_color = Color(0.2, 0.65, 0.35, 0.85)
			style.border_color = Color(0.45, 0.95, 0.55)
		Highlight.INVALID:
			style.bg_color = Color(0.65, 0.18, 0.22, 0.85)
			style.border_color = Color(0.95, 0.4, 0.4)
		Highlight.CORRUPTED:
			style.bg_color = Color(0.45, 0.2, 0.5, 0.9)
			style.border_color = Color(0.85, 0.4, 0.9)
		Highlight.LOCKED:
			## Fully transparent — inactive cells must not be visible by default.
			style.bg_color = Color(0, 0, 0, 0)
			style.border_color = Color(0, 0, 0, 0)
			style.set_border_width_all(0)
		_:
			style.bg_color = Color(0.22, 0.22, 0.22, 1)
			style.border_color = Color(0.08, 0.08, 0.08)
	_base_panel.add_theme_stylebox_override("panel", style)


func clear_drag_highlight() -> void:
	if _highlight == Highlight.VALID or _highlight == Highlight.INVALID:
		# Restored properly on next refresh / apply_cell_state.
		set_highlight(Highlight.BASE if unlocked else Highlight.LOCKED)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not _is_item_drag(data):
		return false
	if _grid_ui and _grid_ui.has_method("on_slot_drag_hover"):
		_grid_ui.on_slot_drag_hover(cell, data)
	if _grid_ui and _grid_ui.has_method("can_drop_on_cell"):
		return _grid_ui.can_drop_on_cell(cell, data)
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not _is_item_drag(data):
		return
	drop_requested.emit(cell, data)
	if _grid_ui and _grid_ui.has_method("drop_on_cell"):
		_grid_ui.drop_on_cell(cell, data)


static func _is_item_drag(data: Variant) -> bool:
	return data is Dictionary and data.get("type", "") == DRAG_TYPE
