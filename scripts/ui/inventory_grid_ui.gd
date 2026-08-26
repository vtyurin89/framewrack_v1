class_name InventoryGridUI
extends Control
## Body-grid inventory UI — no external stash.
## Drag modules on the grid; RMB while dragging rotates; invalid drops snap back.

signal cell_clicked(cell: Vector2i)
signal item_drag_started(item: ItemData, source: String)
signal item_drag_ended(item: ItemData, success: bool)
signal item_moved(item: ItemData, from_origin: Vector2i, to_origin: Vector2i)
signal item_inspected(item: ItemData)
signal item_activated(placed: PlacedItem)
signal close_requested
signal layout_fitted(min_size: Vector2)

const CELL_SIZE := 48.0
const CELL_GAP := 4.0
## Full 7x8 matrix already reserves locked perimeter cells for expansion.
const RESERVED_ROWS_TOP := 0
const RESERVED_ROWS_BOTTOM := 0
const DRAG_TYPE := "framewrack_item"
const INSPECT_MODAL_SCENE := preload("res://scenes/UI/item_inspect_modal.tscn")
## Level-up overlay dimmer — CRT dark green veil.
const LEVEL_UP_OVERLAY_COLOR := Color(0.031, 0.051, 0.039, 0.82)
## Phosphor CTA against the dark overlay.
const LEVEL_UP_BTN_BG := Color("#111C16") ## PANEL_BG_ALT
const LEVEL_UP_BTN_BG_HOVER := Color("#285A3A") ## MUTED_GREEN
const LEVEL_UP_BTN_BG_PRESSED := Color("#173323") ## INACTIVE_ELEMENT
const LEVEL_UP_BTN_BG_DISABLED := Color(0.05, 0.08, 0.06, 0.85)
const LEVEL_UP_BTN_BORDER := Color("#A8F0A8") ## PHOSPHOR_BRIGHT
const LEVEL_UP_BTN_FONT := Color("#A8F0A8") ## PHOSPHOR_BRIGHT
const LEVEL_UP_BTN_FONT_DIM := Color("#79D88A") ## PHOSPHOR_ACTIVE — idle soft glow

var inventory: InventoryController
var player_stats: PlayerStats
## When set, LMB on items activates combat modules instead of dragging.
var combat_manager: Node
var combat_click_mode: bool = false
## Blocks inventory interaction until the player confirms each pending level-up.
var level_up_mode: bool = false
## Optional RewardScreen hook for post-combat floating loot validation.
var reward_handler: Node

## Active drag session (shared Dictionary mutated for rotation).
var _drag: Dictionary = {}
var _drop_committed: bool = false
var _suppress_refresh: bool = false
var _hover_origin: Vector2i = Vector2i(-1, -1)
var _level_up_busy: bool = false
var _suppress_unlock_reveal: bool = false

var _slots: Dictionary = {}  # "x,y" -> InventorySlotUI
var _item_uis: Array[ItemUI] = []
var _hover_tooltip: ItemHoverTooltip
var _hovered_item_ui: ItemUI
var _context_menu: ItemContextMenu
var _inspect_modal: ItemInspectModal
var _cell_damage_vfx: CellDamageVfx

@onready var _grid_host: Control = %GridHost
@onready var _grid_root: GridContainer = %GridRoot
@onready var _stats_label: Label = %StatsHeaderLabel
@onready var _item_layer: Control = %ItemLayer
@onready var _title: Label = %Title
@onready var _close_button: Button = %CloseButton
@onready var _padding: MarginContainer = %Padding
@onready var _level_up_overlay: ColorRect = %LevelUpOverlay
@onready var _level_up_button: Button = %LevelUpButton


func _ready() -> void:
	_wire_stats_label_hover()
	_on_stats_changed()


func _wire_stats_label_hover() -> void:
	if _stats_label == null:
		return
	_stats_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_stats_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not _stats_label.mouse_entered.is_connected(_on_stats_label_mouse_entered):
		_stats_label.mouse_entered.connect(_on_stats_label_mouse_entered)
	if not _stats_label.mouse_exited.is_connected(_on_stats_label_mouse_exited):
		_stats_label.mouse_exited.connect(_on_stats_label_mouse_exited)


func _on_stats_label_mouse_entered() -> void:
	if player_stats == null:
		return
	_ensure_hover_tooltip()
	_hovered_item_ui = null
	_hover_tooltip.request_show_text(
		tr("KEY_PLAYER_STATS"),
		player_stats.format_stats_tooltip_body()
	)


func _on_stats_label_mouse_exited() -> void:
	_hide_hover_tooltip()


func setup(p_inventory: InventoryController) -> void:
	## Only the panel/content should capture input; parent overlay is pass-through.
	mouse_filter = Control.MOUSE_FILTER_STOP
	inventory = p_inventory
	_ensure_hover_tooltip()
	_ensure_context_menu()
	_ensure_inspect_modal()
	if not EventBus.inventory_changed.is_connected(_on_inventory_changed):
		EventBus.inventory_changed.connect(_on_inventory_changed)
	if not EventBus.grid_expanded.is_connected(_on_grid_expanded):
		EventBus.grid_expanded.connect(_on_grid_expanded)
	if not EventBus.placement_failed.is_connected(_on_placement_failed):
		EventBus.placement_failed.connect(_on_placement_failed)
	if not LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.connect(_on_language_changed)
	if not EventBus.combat_item_availability_changed.is_connected(_refresh_combat_item_visuals):
		EventBus.combat_item_availability_changed.connect(_refresh_combat_item_visuals)
	if not EventBus.ap_changed.is_connected(_on_ap_changed_visuals):
		EventBus.ap_changed.connect(_on_ap_changed_visuals)
	if not EventBus.cell_damaged.is_connected(_on_cell_damaged_vfx):
		EventBus.cell_damaged.connect(_on_cell_damaged_vfx)
	if not EventBus.sticky_grenade_blast.is_connected(_on_sticky_grenade_blast_vfx):
		EventBus.sticky_grenade_blast.connect(_on_sticky_grenade_blast_vfx)
	if _close_button and not _close_button.pressed.is_connected(_on_close_pressed):
		_close_button.pressed.connect(_on_close_pressed)
	if _level_up_button and not _level_up_button.pressed.is_connected(_on_level_up_pressed):
		_level_up_button.pressed.connect(_on_level_up_pressed)
	_apply_level_up_visuals()
	_apply_static_locale()
	_sync_level_up_overlay()
	refresh()


func bind_player_stats(stats: PlayerStats) -> void:
	if player_stats != null and player_stats.stats_changed.is_connected(_on_stats_changed):
		player_stats.stats_changed.disconnect(_on_stats_changed)
	player_stats = stats
	if _hover_tooltip != null:
		_hover_tooltip.actor_stats = stats
		_hover_tooltip.body_grid = inventory.grid if inventory != null else null
	if _inspect_modal != null:
		_inspect_modal.actor_stats = stats
		_inspect_modal.body_grid = inventory.grid if inventory != null else null
	if player_stats != null:
		if not player_stats.stats_changed.is_connected(_on_stats_changed):
			player_stats.stats_changed.connect(_on_stats_changed)
		_recalculate_player_equipment_stats()
		_on_stats_changed()
	if player_stats != null and player_stats.has_pending_level_ups():
		set_level_up_mode(true)
	else:
		_sync_level_up_overlay()


func _on_stats_changed() -> void:
	if _stats_label == null:
		return
	GamePalette.apply_label_primary(_stats_label)
	if player_stats == null:
		_stats_label.text = "STR: — | AGI: — | END: — | INT: — | LCK: — | HUM: —"
		return
	_stats_label.text = player_stats.format_stats_header()
	if inventory != null:
		inventory.apply_actor_stats(player_stats)


func _recalculate_player_equipment_stats() -> void:
	if player_stats == null:
		return
	var grid: BodyGrid = inventory.grid if inventory != null else null
	player_stats.recalculate_from_equipment(grid)

func set_combat_mode(enabled: bool, p_combat: Node = null) -> void:
	combat_click_mode = enabled
	combat_manager = p_combat if enabled else null
	_hide_hover_tooltip()
	_close_context_menu()
	refresh()


func set_level_up_mode(enabled: bool) -> void:
	level_up_mode = enabled
	if not enabled:
		_level_up_busy = false
	_hide_hover_tooltip()
	_close_context_menu()
	if not _drag.is_empty():
		end_item_drag(false)
	_sync_level_up_overlay()


func _on_ap_changed_visuals(_current: int, _maximum: int) -> void:
	_refresh_combat_item_visuals()


func _ensure_hover_tooltip() -> void:
	if _hover_tooltip != null and is_instance_valid(_hover_tooltip):
		_hover_tooltip.body_grid = inventory.grid if inventory != null else null
		_hover_tooltip.is_hacked_fn = Callable(self, "_is_player_hacked")
		return
	_hover_tooltip = ItemHoverTooltip.new()
	_hover_tooltip.name = "ItemHoverTooltip"
	_hover_tooltip.actor_stats = player_stats
	_hover_tooltip.body_grid = inventory.grid if inventory != null else null
	_hover_tooltip.is_hacked_fn = Callable(self, "_is_player_hacked")
	add_child(_hover_tooltip)


func _ensure_inspect_modal() -> void:
	if _inspect_modal != null and is_instance_valid(_inspect_modal):
		_inspect_modal.actor_stats = player_stats
		_inspect_modal.body_grid = inventory.grid if inventory != null else null
		_inspect_modal.is_hacked_fn = Callable(self, "_is_player_hacked")
		return
	_inspect_modal = INSPECT_MODAL_SCENE.instantiate() as ItemInspectModal
	_inspect_modal.name = "ItemInspectModal"
	_inspect_modal.actor_stats = player_stats
	_inspect_modal.body_grid = inventory.grid if inventory != null else null
	_inspect_modal.is_hacked_fn = Callable(self, "_is_player_hacked")
	_inspect_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inspect_modal.offset_left = 0
	_inspect_modal.offset_top = 0
	_inspect_modal.offset_right = 0
	_inspect_modal.offset_bottom = 0
	## High CanvasLayer so grain / target reticle cannot paint over the dialog.
	UiOverlayLayer.mount(_inspect_modal, self)


func _ensure_context_menu() -> void:
	if _context_menu != null and is_instance_valid(_context_menu):
		return
	_context_menu = ItemContextMenu.new()
	_context_menu.name = "ItemContextMenu"
	_context_menu.inspect_pressed.connect(_on_context_inspect_pressed)
	_context_menu.use_pressed.connect(_on_context_use_pressed)
	## Mount with inventory as tree anchor (menu is not in the tree yet).
	UiOverlayLayer.mount(_context_menu, self)
	if not _context_menu.is_inside_tree():
		add_child(_context_menu)


func _hide_hover_tooltip() -> void:
	_hovered_item_ui = null
	if _hover_tooltip:
		_hover_tooltip.hide_tooltip()


func _close_context_menu() -> void:
	if _context_menu:
		_context_menu.close()


func _on_language_changed(_locale: String) -> void:
	_apply_static_locale()
	_hide_hover_tooltip()
	refresh()


func _apply_level_up_visuals() -> void:
	if _level_up_overlay:
		_level_up_overlay.color = LEVEL_UP_OVERLAY_COLOR
	if _level_up_button == null:
		return
	_level_up_button.custom_minimum_size = Vector2(200, 52)
	_level_up_button.add_theme_font_size_override("font_size", 20)
	## Idle: soft phosphor text; hover/focus snaps to full bright.
	_level_up_button.add_theme_color_override("font_color", LEVEL_UP_BTN_FONT_DIM)
	_level_up_button.add_theme_color_override("font_hover_color", LEVEL_UP_BTN_FONT)
	_level_up_button.add_theme_color_override("font_pressed_color", LEVEL_UP_BTN_FONT)
	_level_up_button.add_theme_color_override("font_focus_color", LEVEL_UP_BTN_FONT)
	_level_up_button.add_theme_color_override("font_disabled_color", Color(0.16, 0.22, 0.18, 0.7))
	_level_up_button.add_theme_stylebox_override(
		"normal", _make_level_up_button_style(LEVEL_UP_BTN_BG, LEVEL_UP_BTN_BORDER, false)
	)
	_level_up_button.add_theme_stylebox_override(
		"hover", _make_level_up_button_style(LEVEL_UP_BTN_BG_HOVER, LEVEL_UP_BTN_BORDER, true)
	)
	_level_up_button.add_theme_stylebox_override(
		"pressed", _make_level_up_button_style(LEVEL_UP_BTN_BG_PRESSED, LEVEL_UP_BTN_BORDER, false)
	)
	_level_up_button.add_theme_stylebox_override(
		"disabled",
		_make_level_up_button_style(LEVEL_UP_BTN_BG_DISABLED, Color(0.16, 0.25, 0.2, 0.55), false)
	)
	_level_up_button.add_theme_stylebox_override(
		"focus", _make_level_up_button_style(LEVEL_UP_BTN_BG_HOVER, LEVEL_UP_BTN_BORDER, true)
	)
	GamePalette.apply_phosphor_glow(_level_up_button, true)


func _make_level_up_button_style(bg: Color, border: Color, with_glow: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_border_width_all(2)
	style.border_color = border
	style.set_corner_radius_all(0)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	if with_glow:
		style.shadow_color = Color(LEVEL_UP_BTN_BORDER.r, LEVEL_UP_BTN_BORDER.g, LEVEL_UP_BTN_BORDER.b, 0.35)
		style.shadow_size = 6
		style.shadow_offset = Vector2.ZERO
	else:
		style.shadow_size = 0
	return style


func _apply_static_locale() -> void:
	if _title:
		_title.text = tr("KEY_BODY_GRID_TITLE")
	if _close_button:
		_close_button.text = "✕"
	if _level_up_button:
		_level_up_button.text = tr("KEY_LEVEL_UP").to_upper()
	_on_stats_changed()


func refresh() -> void:
	if inventory == null or _suppress_refresh:
		return
	_rebuild_grid()
	_rebuild_items()
	_sync_level_up_overlay()


func _on_inventory_changed() -> void:
	_recalculate_player_equipment_stats()
	refresh()


func _on_grid_expanded(new_cells: Array[Vector2i]) -> void:
	refresh()
	_on_stats_changed()
	if not _suppress_unlock_reveal:
		_play_unlock_reveal(new_cells)


func _sync_level_up_overlay() -> void:
	if _level_up_overlay == null:
		return
	if _level_up_busy:
		## Keep an invisible mouse-blocker up while cells reveal.
		_level_up_overlay.visible = true
		_level_up_overlay.modulate = Color(1, 1, 1, 0)
		_level_up_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		if _level_up_button:
			_level_up_button.disabled = true
			_level_up_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	var show_overlay := level_up_mode
	_level_up_overlay.visible = show_overlay
	_level_up_overlay.modulate = Color.WHITE
	_level_up_overlay.mouse_filter = (
		Control.MOUSE_FILTER_STOP if show_overlay else Control.MOUSE_FILTER_IGNORE
	)
	if _level_up_button:
		_level_up_button.disabled = not show_overlay
		_level_up_button.mouse_filter = (
			Control.MOUSE_FILTER_STOP if show_overlay else Control.MOUSE_FILTER_IGNORE
		)


func _on_level_up_pressed() -> void:
	if _level_up_busy or not level_up_mode:
		return
	if player_stats == null or not player_stats.has_pending_level_ups():
		set_level_up_mode(false)
		return
	if inventory == null or inventory.grid == null:
		return
	await _confirm_level_up()


func _confirm_level_up() -> void:
	_level_up_busy = true
	if _level_up_button:
		_level_up_button.disabled = true
	_hide_hover_tooltip()
	_close_context_menu()

	await _fade_level_up_overlay_out()

	## Resolve the level this reveal belongs to (supports multi-level XP dumps).
	var reveal_level := 1
	if player_stats != null:
		reveal_level = player_stats.level - player_stats.pending_level_ups + 1
	var cell_gain := BodyGrid.level_up_cell_gain_for_level(reveal_level)

	_suppress_unlock_reveal = true
	var new_cells: Array[Vector2i] = inventory.grid.unlock_random_adjacent_cells(cell_gain)
	_suppress_unlock_reveal = false
	await _play_unlock_reveal(new_cells)

	if player_stats != null:
		player_stats.consume_pending_level_up()

	_level_up_busy = false
	if player_stats != null and player_stats.has_pending_level_ups():
		level_up_mode = true
		_sync_level_up_overlay()
	else:
		set_level_up_mode(false)


func _fade_level_up_overlay_out() -> void:
	if _level_up_overlay == null:
		return
	## Keep overlay present (and mouse-blocking) at alpha 0 during the unlock reveal.
	_level_up_overlay.visible = true
	_level_up_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_level_up_overlay.modulate = Color.WHITE
	var tween := create_tween()
	tween.tween_property(_level_up_overlay, "modulate:a", 0.0, 0.22)
	await tween.finished


func _play_unlock_reveal(new_cells: Array[Vector2i]) -> void:
	if new_cells.is_empty():
		return
	## Cascade pop: each cell scales up from center with a gold flash, staggered slightly.
	var running: Array[InventorySlotUI] = []
	for i in new_cells.size():
		var slot: InventorySlotUI = _slots.get(BodyGrid.cell_key(new_cells[i]))
		if slot == null or not is_instance_valid(slot):
			continue
		running.append(slot)
		## Fire without awaiting so the cascade overlaps; await the last pop below.
		slot.play_unlock_pop(0.08 * float(i))

	if running.is_empty():
		return
	var last_index := running.size() - 1
	var wait_s := 0.08 * float(last_index) + maxf(
		InventorySlotUI.UNLOCK_SCALE_DURATION,
		InventorySlotUI.UNLOCK_FLASH_DURATION
	) + 0.05
	await get_tree().create_timer(wait_s).timeout


func _on_placement_failed(_reason: String) -> void:
	pass


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _rebuild_grid() -> void:
	for child in _grid_root.get_children():
		child.queue_free()
	_slots.clear()

	var g: BodyGrid = inventory.grid
	_grid_root.columns = g.width
	_grid_root.add_theme_constant_override("h_separation", int(CELL_GAP))
	_grid_root.add_theme_constant_override("v_separation", int(CELL_GAP))

	for y in g.height:
		for x in g.width:
			var cell := Vector2i(x, y)
			var slot := InventorySlotUI.new()
			slot.setup(cell, self, CELL_SIZE)
			slot.apply_cell_state(
				g.is_unlocked(cell),
				g.is_corrupted(cell),
				g.is_edge_cell(cell),
				g.get_corruption_turns(cell),
			)
			slot.gui_input.connect(_on_slot_gui_input.bind(cell))
			_grid_root.add_child(slot)
			_slots[BodyGrid.cell_key(cell)] = slot

	call_deferred("_fit_layers")


func _rebuild_items() -> void:
	_hide_hover_tooltip()
	_close_context_menu()
	_item_uis.clear()
	if _item_layer == null:
		return

	for child in _item_layer.get_children():
		child.queue_free()

	var g: BodyGrid = inventory.grid
	g.recalculate_grid_adjacencies()
	for placed: PlacedItem in g.items:
		var ui := ItemUI.new()
		ui.setup(placed.data, self, CELL_SIZE, CELL_GAP, placed.origin)
		ui.position = _origin_to_layer_pos(placed.origin)
		ui.combat_click_mode = combat_click_mode
		ui.context_menu_requested.connect(_on_item_context_menu_requested)
		ui.pointer_down.connect(_on_item_pointer_down)
		ui.activate_requested.connect(_on_item_activate_requested)
		ui.mouse_entered.connect(_on_item_mouse_entered.bind(ui))
		ui.mouse_exited.connect(_on_item_mouse_exited.bind(ui))
		_item_layer.add_child(ui)
		_item_uis.append(ui)
		if combat_click_mode and combat_manager != null and combat_manager.has_method("can_activate_item"):
			ui.set_combat_visual(combat_manager.can_activate_item(placed))

	call_deferred("_fit_layers")


func _fit_layers() -> void:
	if inventory == null or _grid_root == null:
		return
	var g: BodyGrid = inventory.grid
	var w := g.width * CELL_SIZE + maxi(g.width - 1, 0) * CELL_GAP
	var h := g.height * CELL_SIZE + maxi(g.height - 1, 0) * CELL_GAP
	var row_stride := CELL_SIZE + CELL_GAP
	var top_pad := RESERVED_ROWS_TOP * row_stride
	var bottom_pad := RESERVED_ROWS_BOTTOM * row_stride
	var host_h := h + top_pad + bottom_pad
	if _grid_host:
		_grid_host.custom_minimum_size = Vector2(w, host_h)
		_grid_host.size = Vector2(w, host_h)
	_grid_root.position = Vector2(0, top_pad)
	_grid_root.size = Vector2(w, h)
	if _item_layer:
		_item_layer.position = Vector2(0, top_pad)
		_item_layer.custom_minimum_size = Vector2(w, h)
		_item_layer.size = Vector2(w, h)
		_item_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ensure_cell_damage_vfx(g, w, h, top_pad)
	update_minimum_size()
	var content_min := _padding.get_combined_minimum_size() if _padding else get_combined_minimum_size()
	custom_minimum_size = content_min
	layout_fitted.emit(content_min)


func _on_close_pressed() -> void:
	close_requested.emit()


func _ensure_cell_damage_vfx(g: BodyGrid, w: float, h: float, top_pad: float) -> void:
	## Live on GridHost (not ItemLayer) so item rebuilds do not kill the laser mid-play.
	if _grid_host == null:
		return
	if _cell_damage_vfx == null or not is_instance_valid(_cell_damage_vfx):
		_cell_damage_vfx = CellDamageVfx.new()
		_cell_damage_vfx.name = "CellDamageVfx"
		_grid_host.add_child(_cell_damage_vfx)
	elif _cell_damage_vfx.get_parent() != _grid_host:
		_cell_damage_vfx.reparent(_grid_host)
	_cell_damage_vfx.configure(Vector2i(g.width, g.height), CELL_SIZE, CELL_GAP)
	_cell_damage_vfx.position = Vector2(0, top_pad)
	_cell_damage_vfx.size = Vector2(w, h)
	_grid_host.move_child(_cell_damage_vfx, -1)


func _on_cell_damaged_vfx(cell: Vector2i) -> void:
	if inventory == null or inventory.grid == null or _grid_host == null:
		return
	var g: BodyGrid = inventory.grid
	var w := g.width * CELL_SIZE + maxi(g.width - 1, 0) * CELL_GAP
	var h := g.height * CELL_SIZE + maxi(g.height - 1, 0) * CELL_GAP
	var top_pad := RESERVED_ROWS_TOP * (CELL_SIZE + CELL_GAP)
	_ensure_cell_damage_vfx(g, w, h, top_pad)
	if _cell_damage_vfx != null and is_instance_valid(_cell_damage_vfx):
		_cell_damage_vfx.play_at(cell)


func _on_sticky_grenade_blast_vfx(cell: Vector2i) -> void:
	if inventory == null or inventory.grid == null or _grid_host == null:
		return
	var g: BodyGrid = inventory.grid
	var w := g.width * CELL_SIZE + maxi(g.width - 1, 0) * CELL_GAP
	var h := g.height * CELL_SIZE + maxi(g.height - 1, 0) * CELL_GAP
	var top_pad := RESERVED_ROWS_TOP * (CELL_SIZE + CELL_GAP)
	_ensure_cell_damage_vfx(g, w, h, top_pad)
	if _cell_damage_vfx != null and is_instance_valid(_cell_damage_vfx):
		_cell_damage_vfx.play_blast_at(cell)


func _is_player_hacked() -> bool:
	if combat_manager == null:
		return false
	var statuses = combat_manager.get("player_statuses")
	if statuses == null:
		return false
	return statuses.has_method("has_status") and bool(statuses.has_status("hacked"))


func _origin_to_layer_pos(origin: Vector2i) -> Vector2:
	return Vector2(
		origin.x * (CELL_SIZE + CELL_GAP),
		origin.y * (CELL_SIZE + CELL_GAP),
	)


func _on_slot_gui_input(event: InputEvent, cell: Vector2i) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		cell_clicked.emit(cell)


func _on_item_context_menu_requested(item: ItemData) -> void:
	open_item_context_menu(item)


func open_item_context_menu(item: ItemData) -> void:
	## RMB on a static inventory or floating reward item.
	if level_up_mode or _level_up_busy:
		return
	if not _drag.is_empty():
		return
	if item == null:
		return
	## Don't stack menus under an open inspect dialog.
	if _inspect_modal != null and is_instance_valid(_inspect_modal) and _inspect_modal.is_open():
		return
	_hide_hover_tooltip()
	_ensure_context_menu()
	if _context_menu == null:
		return
	## Ensure the menu is in the scene tree before opening (await needs SceneTree).
	if not _context_menu.is_inside_tree():
		UiOverlayLayer.mount(_context_menu, self)
	if not _context_menu.is_inside_tree():
		add_child(_context_menu)
	var in_combat := combat_click_mode
	if combat_manager != null and combat_manager.has_method("is_in_combat"):
		in_combat = combat_manager.is_in_combat()
	_context_menu.open_for_item(item, get_global_mouse_position(), in_combat)


func _on_context_inspect_pressed(item: ItemData) -> void:
	_close_context_menu()
	_hide_hover_tooltip()
	inspect_item(item)


func _on_context_use_pressed(item: ItemData) -> void:
	_close_context_menu()
	_hide_hover_tooltip()
	if inventory == null or item == null:
		return
	if combat_click_mode:
		return
	var result: Dictionary = inventory.use_consumable_out_of_combat(item, player_stats)
	var msg := str(result.get("message", ""))
	if not msg.is_empty():
		EventBus.combat_log_message.emit(msg)
		_show_inventory_toast(msg)
	var unlocked: Array = result.get("unlocked_cells", [])
	if unlocked is Array and not unlocked.is_empty():
		var cells: Array[Vector2i] = []
		for c in unlocked:
			if c is Vector2i:
				cells.append(c)
		if not cells.is_empty():
			_play_unlock_reveal(cells)
	refresh()


func _show_inventory_toast(bbcode_or_text: String) -> void:
	## Lightweight floating notice over the body grid.
	var toast := RichTextLabel.new()
	toast.bbcode_enabled = true
	toast.fit_content = true
	toast.scroll_active = false
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.text = bbcode_or_text
	toast.z_index = 200
	toast.add_theme_font_size_override("normal_font_size", 14)
	add_child(toast)
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.position = Vector2(size.x * 0.5 - 120.0, 12.0)
	toast.custom_minimum_size = Vector2(240, 0)
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(toast, "modulate:a", 0.0, 0.35)
	tw.tween_callback(toast.queue_free)


func inspect_item(item: ItemData) -> void:
	if item == null:
		return
	_close_context_menu()
	_hide_hover_tooltip()
	if inventory != null:
		inventory.grid.recalculate_grid_adjacencies()
	_ensure_inspect_modal()
	if _inspect_modal:
		_inspect_modal.open_item(item)
	item_inspected.emit(item)


func _on_item_activate_requested(item_ui: ItemUI) -> void:
	if not combat_click_mode or item_ui == null or inventory == null:
		return
	var placed: PlacedItem = inventory.grid.get_occupant(item_ui.grid_origin)
	if placed == null:
		return
	item_activated.emit(placed)


func _refresh_combat_item_visuals() -> void:
	if inventory == null:
		return
	for ui: ItemUI in _item_uis:
		if not is_instance_valid(ui):
			continue
		if combat_click_mode and combat_manager != null:
			ui.combat_click_mode = true
			var placed: PlacedItem = inventory.grid.get_occupant(ui.grid_origin)
			if placed != null and combat_manager.has_method("can_activate_item"):
				ui.set_combat_visual(combat_manager.can_activate_item(placed))
			else:
				ui.set_combat_visual(false)
		elif ui.has_method("refresh_status_overlay"):
			ui.refresh_status_overlay()


func _on_item_pointer_down(_item_ui: ItemUI) -> void:
	## LMB pressed on an item — hide tooltip / menu before drag or activation.
	_hide_hover_tooltip()
	_close_context_menu()


func _on_item_mouse_entered(item_ui: ItemUI) -> void:
	if level_up_mode or _level_up_busy:
		return
	if not _drag.is_empty():
		return
	if item_ui == null or item_ui.item == null:
		return
	_hovered_item_ui = item_ui
	_ensure_hover_tooltip()
	if inventory != null:
		inventory.grid.recalculate_grid_adjacencies()
	_hover_tooltip.request_show_for_item(item_ui.item)


func _on_item_mouse_exited(item_ui: ItemUI) -> void:
	if _hovered_item_ui == item_ui:
		_hide_hover_tooltip()


# ---------------------------------------------------------------------------
# Drag session — grid only; invalid drop restores previous grid position
# ---------------------------------------------------------------------------

func set_reward_handler(handler: Node) -> void:
	reward_handler = handler


func commit_external_drop() -> void:
	## Mark current drag as successfully consumed outside the grid (e.g. Space).
	_drop_committed = true


func begin_debug_item_drag(item: ItemData) -> Dictionary:
	## Like begin_reward_space_drag, but allowed during combat (debug catalog grants).
	if level_up_mode or _level_up_busy:
		return {}
	if inventory == null or item == null:
		return {}
	if not _drag.is_empty():
		return {}
	_hide_hover_tooltip()
	_close_context_menu()
	_suppress_refresh = true
	_drop_committed = false
	_hover_origin = Vector2i(-1, -1)
	_drag = {
		"type": DRAG_TYPE,
		"item": item,
		"footprint": item.size,
		"original_size": item.size,
		"source": "space",
		"original_origin": Vector2i(-1, -1),
		"preview": null,
	}
	_set_item_uis_pass_through(true)
	item_drag_started.emit(item, "space")
	return _drag


func begin_reward_space_drag(item: ItemData) -> Dictionary:
	if combat_click_mode or level_up_mode or _level_up_busy:
		return {}
	if inventory == null or item == null:
		return {}
	if not _drag.is_empty():
		return {}
	_hide_hover_tooltip()
	_close_context_menu()
	_suppress_refresh = true
	_drop_committed = false
	_hover_origin = Vector2i(-1, -1)
	_drag = {
		"type": DRAG_TYPE,
		"item": item,
		"footprint": item.size,
		"original_size": item.size,
		"source": "space",
		"original_origin": Vector2i(-1, -1),
		"preview": null,
	}
	_set_item_uis_pass_through(true)
	item_drag_started.emit(item, "space")
	return _drag


func begin_item_drag(item_ui: ItemUI) -> Dictionary:
	if combat_click_mode or level_up_mode or _level_up_busy:
		return {}
	if inventory == null or item_ui == null or item_ui.item == null:
		return {}
	if not _drag.is_empty():
		return {}
	if item_ui.grid_origin.x < 0:
		return {}

	## Tooltip / context menu must hide immediately on LMB pickup.
	_hide_hover_tooltip()
	_close_context_menu()

	_suppress_refresh = true
	_drop_committed = false
	_hover_origin = Vector2i(-1, -1)

	var original_size := item_ui.item.size
	var original_origin := item_ui.grid_origin
	var extracted: ItemData = inventory.extract_from_grid(item_ui.grid_origin)
	if extracted == null:
		_suppress_refresh = false
		return {}

	_drag = {
		"type": DRAG_TYPE,
		"item": extracted,
		"footprint": extracted.size,
		"original_size": original_size,
		"source": "grid",
		"original_origin": original_origin,
		"preview": null,
	}

	_set_item_uis_pass_through(true)
	_refresh_slots_only()
	item_drag_started.emit(extracted, "grid")
	return _drag


func end_item_drag(_success: bool) -> bool:
	if _drag.is_empty():
		_suppress_refresh = false
		_set_item_uis_pass_through(false)
		_hide_hover_tooltip()
		return false

	var item: ItemData = _drag["item"]
	var source := str(_drag.get("source", "grid"))
	var committed := _drop_committed
	## Any failed / off-grid drop cancels and snaps back.
	if not committed:
		if source == "space" and reward_handler != null:
			if reward_handler.has_method("return_floating_to_space"):
				reward_handler.return_floating_to_space(item, get_global_mouse_position())
			elif reward_handler.has_method("on_item_extracted_to_space"):
				reward_handler.on_item_extracted_to_space(item, get_global_mouse_position())
		else:
			_restore_drag_item()
	elif source == "space" and reward_handler != null and reward_handler.has_method("recover_space_item_if_lost"):
		## Catch rare lost-loot cases (committed without a grid placement).
		reward_handler.recover_space_item_if_lost(item, get_global_mouse_position())
	item_drag_ended.emit(item, committed)

	_clear_highlights()
	_drag.clear()
	_drop_committed = false
	_hover_origin = Vector2i(-1, -1)
	_set_item_uis_pass_through(false)
	_suppress_refresh = false
	_hide_hover_tooltip()
	EventBus.inventory_changed.emit()
	refresh()
	return committed


func _restore_drag_item() -> void:
	if _drag.is_empty():
		return
	var item: ItemData = _drag["item"]
	item.size = _drag["original_size"]
	var origin: Vector2i = _drag["original_origin"]
	inventory.grid.place_item(item, origin, item.size)


func _set_item_uis_pass_through(enabled: bool) -> void:
	var filter := Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP
	for ui in _item_uis:
		if is_instance_valid(ui):
			ui.mouse_filter = filter


# ---------------------------------------------------------------------------
# Hover validation / highlights
# ---------------------------------------------------------------------------

func on_slot_drag_hover(cell: Vector2i, data: Variant) -> void:
	if level_up_mode or _level_up_busy:
		return
	if not _is_drag(data):
		return
	if cell == _hover_origin and data.get("footprint") == _drag.get("footprint"):
		return
	_hover_origin = cell
	_update_footprint_highlights(cell, data)


func can_drop_on_cell(cell: Vector2i, data: Variant) -> bool:
	if level_up_mode or _level_up_busy:
		return false
	if not _is_drag(data) or inventory == null:
		return false
	var item: ItemData = data["item"]
	var footprint: Vector2i = data["footprint"]
	## Pick-limit is enforced in drop_on_cell (so a notice can fire). Grid fit only here.
	return inventory.grid.can_place_item(item, cell, footprint)


func drop_on_cell(cell: Vector2i, data: Variant) -> void:
	if not _is_drag(data) or inventory == null:
		return
	var item: ItemData = data["item"]
	var footprint: Vector2i = data["footprint"]
	if reward_handler != null and reward_handler.has_method("can_accept_item_to_inventory"):
		if not reward_handler.can_accept_item_to_inventory(item, true):
			return
	if not inventory.place_dragged(item, cell, footprint):
		## Invalid cell — leave uncommitted so end_item_drag snaps back.
		return

	_drop_committed = true
	if reward_handler != null and reward_handler.has_method("on_item_placed_in_inventory"):
		reward_handler.on_item_placed_in_inventory(item)
	var from_origin: Vector2i = data.get("original_origin", Vector2i(-1, -1))
	if from_origin.x >= 0:
		item_moved.emit(item, from_origin, cell)
	_clear_highlights()


func _update_footprint_highlights(origin: Vector2i, data: Variant) -> void:
	_clear_highlights()
	if not _is_drag(data) or inventory == null:
		return
	var item: ItemData = data["item"]
	var footprint: Vector2i = data["footprint"]
	var valid := inventory.grid.can_place_item(item, origin, footprint)
	if valid and reward_handler != null and reward_handler.has_method("can_accept_item_to_inventory"):
		if not reward_handler.can_accept_item_to_inventory(item, false):
			valid = false
	var cells: Array[Vector2i] = item.footprint_for(footprint, origin)
	var mode := (
		InventorySlotUI.Highlight.VALID if valid else InventorySlotUI.Highlight.INVALID
	)
	for cell: Vector2i in cells:
		var slot: InventorySlotUI = _slots.get(BodyGrid.cell_key(cell))
		if slot:
			slot.set_highlight(mode)


func _clear_highlights() -> void:
	_refresh_slots_only()


func _refresh_slots_only() -> void:
	if inventory == null:
		return
	var g: BodyGrid = inventory.grid
	for key: String in _slots.keys():
		var slot: InventorySlotUI = _slots[key]
		var cell := slot.cell
		slot.apply_cell_state(
			g.is_unlocked(cell),
			g.is_corrupted(cell),
			g.is_edge_cell(cell),
			g.get_corruption_turns(cell),
		)


# ---------------------------------------------------------------------------
# Rotation — RMB while dragging ONLY (static RMB does nothing)
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _drag.is_empty():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_rotate_drag()
			get_viewport().set_input_as_handled()


func _rotate_drag() -> void:
	if _drag.is_empty():
		return
	var footprint: Vector2i = _drag["footprint"]
	footprint = Vector2i(footprint.y, footprint.x)
	_drag["footprint"] = footprint

	var preview: Control = _drag.get("preview")
	var item: ItemData = _drag["item"]
	if preview and is_instance_valid(preview):
		_rebuild_preview_node(preview, item, footprint)

	if _hover_origin.x >= 0:
		_update_footprint_highlights(_hover_origin, _drag)


func _rebuild_preview_node(preview: Control, item: ItemData, footprint: Vector2i) -> void:
	while preview.get_child_count() > 0:
		var child := preview.get_child(0)
		preview.remove_child(child)
		child.free()

	var w := footprint.x * CELL_SIZE + maxi(footprint.x - 1, 0) * CELL_GAP
	var h := footprint.y * CELL_SIZE + maxi(footprint.y - 1, 0) * CELL_GAP
	preview.custom_minimum_size = Vector2(w, h)
	preview.size = Vector2(w, h)

	for y in footprint.y:
		for x in footprint.x:
			var cell := Panel.new()
			cell.position = Vector2(x * (CELL_SIZE + CELL_GAP), y * (CELL_SIZE + CELL_GAP))
			cell.size = Vector2(CELL_SIZE, CELL_SIZE)
			var style := StyleBoxFlat.new()
			var col := item.placeholder_color if item else Color(0.7, 0.7, 0.7)
			style.bg_color = col
			style.set_border_width_all(1)
			style.border_color = Color(1, 1, 1, 0.7)
			style.set_corner_radius_all(2)
			cell.add_theme_stylebox_override("panel", style)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			preview.add_child(cell)

	var caption := Label.new()
	caption.text = item.get_localized_name() if item else ""
	caption.position = Vector2(4, 4)
	caption.add_theme_color_override("font_color", GamePalette.PHOSPHOR_BRIGHT)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(caption)


static func _is_drag(data: Variant) -> bool:
	return data is Dictionary and data.get("type", "") == DRAG_TYPE
