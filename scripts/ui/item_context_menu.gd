class_name ItemContextMenu
extends PanelContainer
## Floating RMB context menu for a statically placed inventory item.

signal inspect_pressed(item: ItemData)
signal use_pressed(item: ItemData)
signal closed

const MENU_MIN_WIDTH := 180.0

var _item: ItemData
var _inspect_btn: Button
var _use_btn: Button
var _open: bool = false
## When true, show/enable out-of-combat [Use] for eligible consumables.
var allow_out_of_combat_use: bool = true


func _ready() -> void:
	top_level = true
	z_index = 120
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_style()
	_build()
	set_process_unhandled_input(false)
	if not LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.connect(_on_language_changed)


func is_open() -> bool:
	return _open


func open_for_item(item: ItemData, global_pos: Vector2, in_combat: bool = false) -> void:
	if item == null:
		close()
		return
	var tree := UiOverlayLayer.get_scene_tree(self)
	UiOverlayLayer.mount(self, tree.current_scene if tree != null else null)
	_item = item
	allow_out_of_combat_use = not in_combat
	_refresh_labels()
	_refresh_use_button()
	visible = true
	_open = true
	set_process_unhandled_input(true)
	global_position = global_pos
	tree = UiOverlayLayer.get_scene_tree(self)
	if tree != null:
		await tree.process_frame
	if not is_instance_valid(self) or not _open:
		return
	_clamp_to_viewport()


func close() -> void:
	if not _open and not visible:
		return
	_open = false
	_item = null
	visible = false
	set_process_unhandled_input(false)
	closed.emit()


func _on_language_changed(_locale: String) -> void:
	_refresh_labels()
	_refresh_use_button()


func _refresh_labels() -> void:
	if _inspect_btn:
		_inspect_btn.text = tr("KEY_INSPECT")
	if _use_btn:
		_use_btn.text = tr("KEY_APPLY_ITEM")


func _refresh_use_button() -> void:
	if _use_btn == null:
		return
	var show_use := (
		_item != null
		and _item.usable
		and _item.is_consumable_item()
		and not _item.is_harmful
		and not _item.is_quest_item()
	)
	_use_btn.visible = show_use and allow_out_of_combat_use
	if not _use_btn.visible:
		_use_btn.disabled = true
		_use_btn.modulate = Color.WHITE
		_use_btn.tooltip_text = ""
		_use_btn.set_meta("blocked", false)
		return

	## Keep the control hoverable when blocked — Godot skips tooltips on disabled Buttons.
	if _item.is_combat_only:
		_use_btn.disabled = false
		_use_btn.modulate = Color(0.55, 0.55, 0.55, 1.0)
		_use_btn.tooltip_text = tr("KEY_ITEM_COMBAT_ONLY")
		_use_btn.set_meta("blocked", true)
	elif not _item.can_use_out_of_combat():
		_use_btn.disabled = false
		_use_btn.modulate = Color(0.55, 0.55, 0.55, 1.0)
		_use_btn.tooltip_text = tr("KEY_ITEM_CANNOT_USE")
		_use_btn.set_meta("blocked", true)
	else:
		_use_btn.disabled = false
		_use_btn.modulate = Color.WHITE
		_use_btn.tooltip_text = ""
		_use_btn.set_meta("blocked", false)


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		## Close when clicking outside the menu.
		if not get_global_rect().has_point(event.global_position):
			close()
			get_viewport().set_input_as_handled()


func _build() -> void:
	for child in get_children():
		child.queue_free()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	_use_btn = _ContextUseButton.new()
	_use_btn.custom_minimum_size = Vector2(MENU_MIN_WIDTH, 28)
	_use_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_use_btn.pressed.connect(_on_use_pressed)
	_use_btn.text = tr("KEY_APPLY_ITEM")
	_use_btn.visible = false
	vbox.add_child(_use_btn)

	_inspect_btn = Button.new()
	_inspect_btn.custom_minimum_size = Vector2(MENU_MIN_WIDTH, 28)
	_inspect_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_inspect_btn.pressed.connect(_on_inspect_pressed)
	_inspect_btn.text = tr("KEY_INSPECT")
	vbox.add_child(_inspect_btn)


func _on_inspect_pressed() -> void:
	var selected: ItemData = _item
	close()
	if selected != null:
		inspect_pressed.emit(selected)


func _on_use_pressed() -> void:
	if _use_btn != null and bool(_use_btn.get_meta("blocked", false)):
		return
	var selected: ItemData = _item
	close()
	if selected != null:
		use_pressed.emit(selected)


func _apply_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.11, 0.98)
	style.set_border_width_all(1)
	style.border_color = Color(0.4, 0.4, 0.45)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(2)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 6
	add_theme_stylebox_override("panel", style)


func _clamp_to_viewport() -> void:
	var vp := get_viewport().get_visible_rect().size
	var tip_size := size
	if tip_size.x < 1.0 or tip_size.y < 1.0:
		tip_size = get_combined_minimum_size()
	var pos := global_position
	pos.x = clampf(pos.x, 0.0, maxf(0.0, vp.x - tip_size.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, vp.y - tip_size.y))
	global_position = pos


## Button subclass so disabled [Apply] can show BBCode combat-only tooltips.
class _ContextUseButton extends Button:
	func _make_custom_tooltip(for_text: String) -> Object:
		if for_text.is_empty():
			return null
		var tip := RichTextLabel.new()
		tip.bbcode_enabled = true
		tip.fit_content = true
		tip.scroll_active = false
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.custom_minimum_size = Vector2(220, 0)
		tip.text = for_text
		tip.add_theme_font_size_override("normal_font_size", 12)
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.08, 0.09, 0.96)
		style.set_border_width_all(1)
		style.border_color = Color(0.45, 0.45, 0.5)
		style.set_content_margin_all(8)
		style.set_corner_radius_all(4)
		panel.add_theme_stylebox_override("panel", style)
		panel.add_child(tip)
		return panel
