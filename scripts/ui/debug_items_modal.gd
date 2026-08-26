class_name DebugItemsModal
extends Control
## Left-docked debug catalog: drag any item into the Body Grid.
## Sized to the left panel only so inventory on lower CanvasLayers can receive drops.

signal inventory_open_requested

const PANEL_WIDTH := 360.0

var inventory_ui: Control
var _panel: PanelContainer
var _title: Label
var _list: VBoxContainer
var _is_open: bool = false


func _ready() -> void:
	visible = false
	## Root is the left dock only (not fullscreen) so Body Grid can receive DnD.
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(false)
	_build_layout()
	if not LocalizationManager.language_changed.is_connected(_on_locale_changed):
		LocalizationManager.language_changed.connect(_on_locale_changed)


func is_open() -> bool:
	return _is_open


func open_catalog(p_inventory_ui: Control) -> void:
	inventory_ui = p_inventory_ui
	_rebuild_list()
	_apply_locale()
	UiOverlayLayer.mount(self)
	## Left panel only — never fit_fullscreen (that forces STOP over the whole
	## viewport and steals Body Grid drops on OverlayLayer below).
	_fit_left_dock()
	visible = true
	_is_open = true
	set_process_unhandled_input(true)
	move_to_front()
	inventory_open_requested.emit()


func close() -> void:
	if not _is_open and not visible:
		return
	_is_open = false
	visible = false
	set_process_unhandled_input(false)
	if inventory_ui != null and inventory_ui.get("reward_handler") == self:
		if inventory_ui.has_method("set_reward_handler"):
			inventory_ui.set_reward_handler(null)


func _fit_left_dock() -> void:
	var vp_size := Vector2(1280, 720)
	if get_viewport() != null:
		vp_size = get_viewport().get_visible_rect().size
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	position = Vector2(12.0, 56.0)
	size = Vector2(PANEL_WIDTH, maxf(240.0, vp_size.y - 56.0 - 12.0))
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _panel != null:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_panel.offset_left = 0.0
		_panel.offset_top = 0.0
		_panel.offset_right = 0.0
		_panel.offset_bottom = 0.0


func can_accept_item_to_inventory(_item: ItemData, _show_notice: bool = false) -> bool:
	return true


func on_item_placed_in_inventory(_item: ItemData) -> void:
	## Catalog keeps prototypes; each drag uses a fresh create_instance copy.
	pass


func return_floating_to_space(_item: ItemData, _from_global: Vector2) -> void:
	## Failed drop — discard the temporary instance.
	pass


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_locale_changed(_locale: String = "") -> void:
	_apply_locale()


func _apply_locale() -> void:
	if _title:
		_title.text = tr("KEY_DEBUG_ITEMS_TITLE")
	var hint := _panel.find_child("HintLabel", true, false) as Label if _panel else null
	if hint:
		hint.text = tr("KEY_DEBUG_ITEMS_HINT")


func _build_layout() -> void:
	_panel = PanelContainer.new()
	_panel.name = "ItemsPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_theme_stylebox_override(
		"panel",
		GamePalette.make_panel_stylebox(
			GamePalette.PANEL_BG, GamePalette.MUTED_GREEN, 1, 0, 10.0, false
		)
	)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 16)
	GamePalette.apply_label_primary(_title)
	header.add_child(_title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.custom_minimum_size = Vector2(40, 36)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.add_theme_color_override("font_color", GamePalette.CRT_TEXT_MAIN)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	var hint := Label.new()
	hint.text = tr("KEY_DEBUG_ITEMS_HINT")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	GamePalette.apply_label_muted(hint)
	hint.name = "HintLabel"
	root.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)


func _rebuild_list() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	if ItemDatabase == null:
		return
	var items: Array[ItemData] = ItemDatabase.get_all_items()
	items.sort_custom(func(a: ItemData, b: ItemData) -> bool:
		return a.get_localized_name().to_lower() < b.get_localized_name().to_lower()
	)
	for proto: ItemData in items:
		if proto == null or proto.id.is_empty():
			continue
		_list.add_child(_make_row(proto))


func _make_row(proto: ItemData) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, DebugCatalogChip.CHIP)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_DRAG

	var chip := DebugCatalogChip.new()
	chip.setup(proto, self)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chip)

	var name_lbl := Label.new()
	name_lbl.text = proto.get_localized_name()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", 12)
	GamePalette.apply_label_value(name_lbl)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	return row
