extends Control
## Root controller for Framewrack MVP.
## Inventory-first roguelike (Backpack Hero–like): body grid is the core loop,
## with node-map progression and turn-based combat driven by equipped modules.

const ENEMY_REBEL := preload("res://resources/enemies/desperate_rebel.tres")
const ENEMY_SYNTHET := preload("res://resources/enemies/corrupted_synthet.tres")
const STARTING_ITEM_ID := "SCRAP_PIPE"
const STARTING_ARMOR_ID := "HEAVY_SCRAP_PLATE"
const STARTING_CONSUMABLE_ID := "BIO_GEL"
const EVENT_LOOT_ITEM_ID := "REBEL_CLEAVER"
const MAIN_MENU_SCENE := preload("res://scenes/UI/main_menu.tscn")
const GAME_OVER_SCENE := preload("res://scenes/UI/game_over_ui.tscn")
const SETTINGS_SCENE := preload("res://scenes/UI/settings_modal.tscn")
const DIALOG_EVENT_SCENE := preload("res://scenes/UI/dialog_event_ui.tscn")
const SELECT_ITEM_SCENE := preload("res://scenes/UI/select_item_ui.tscn")

@onready var _map_ui: Control = %MapUI
@onready var _inventory_ui: Control = %InventoryUI
@onready var _combat_ui: Control = %CombatUI
@onready var _status_banner: Label = %StatusBanner
@onready var _body_grid_pane: PanelContainer = %BodyGridPane
@onready var _stage_divider: ColorRect = %StageDivider
@onready var _inventory_panel: PanelContainer = %InventoryPanel
@onready var _body_grid_overlay: Control = %BodyGridOverlay
@onready var _gameplay_hud: GameplayHUD = %TopBar
@onready var _root_layout: Control = $RootLayout

var inventory: InventoryController
var player_stats: PlayerStats
var flow_state: int = GameFlowState.State.EXPLORING
var _main_menu: MainMenuUI
var _game_over: GameOverUI
var _settings: SettingsModal
## True after STARTUP_SETUP reset so GAMEPLAY opens explore UI fresh.
var _fresh_run_pending: bool = false
var _pending_combat_exp_reward: int = 0
var _first_combat_xp_granted: bool = false
var _inventory_overlay_content_min: Vector2 = Vector2(460, 320)
var _inventory_combat_docked: bool = false

@onready var _combat: Node = $CombatManager
@onready var _map: Node = $MapManager
@onready var _encounters: EncounterManager = $EncounterManager
@onready var _run_flow: RunFlowManager = $RunFlowManager

var _dialog_event_ui: DialogEventUI
var _select_item_ui: SelectItemUI
var _encounter_combat_active: bool = false


func _ready() -> void:
	inventory = InventoryController.new()
	player_stats = PlayerStats.new()
	player_stats.pending_level_ups_changed.connect(_on_pending_level_ups_changed)
	inventory.apply_actor_stats(player_stats)
	inventory.heal_full()
	_combat.setup(inventory, player_stats)
	_encounters.setup(inventory, player_stats, _combat)
	_encounters.encounter_started.connect(_on_encounter_started)
	_encounters.encounter_completed.connect(_on_encounter_completed)
	_encounters.request_combat.connect(_on_encounter_request_combat)
	_encounters.request_show_dialog.connect(_on_encounter_request_dialog)
	_encounters.request_show_placeholder.connect(_on_encounter_placeholder)
	_encounters.request_item_selection.connect(_on_encounter_request_item_selection)
	_style_body_grid_pane()
	_style_inventory_modal_panel()
	_ensure_overlays()

	_run_flow.setup(_encounters)
	_map_ui.setup(_run_flow)
	_inventory_ui.setup(inventory)
	if _inventory_ui.has_method("bind_player_stats"):
		_inventory_ui.bind_player_stats(player_stats)
	_mount_inventory_modal_host()
	_combat_ui.setup(_combat, inventory)

	_run_flow.map_changed.connect(_on_run_map_changed)
	_run_flow.run_state_changed.connect(_on_run_state_changed)
	_map_ui.node_chosen.connect(_on_node_chosen)
	_combat_ui.end_turn_pressed.connect(_on_end_turn)
	_combat_ui.target_selected.connect(_on_target)
	_combat_ui.continue_pressed.connect(_on_combat_continue)
	_combat.state_changed.connect(_on_combat_state)
	EventBus.combat_ended.connect(_on_combat_ended_bus)
	EventBus.player_died.connect(_on_player_died)
	if _inventory_ui.has_signal("item_activated"):
		_inventory_ui.item_activated.connect(_on_inventory_item_activated)
	if _inventory_ui.has_signal("close_requested"):
		_inventory_ui.close_requested.connect(_hide_inventory_overlay)
	if _inventory_ui.has_signal("layout_fitted"):
		_inventory_ui.layout_fitted.connect(_on_inventory_layout_fitted)
	if _inventory_ui and not _inventory_ui.resized.is_connected(_position_inventory_overlay_panel):
		_inventory_ui.resized.connect(_position_inventory_overlay_panel)
	if _inventory_panel and not _inventory_panel.resized.is_connected(_position_inventory_overlay_panel):
		_inventory_panel.resized.connect(_position_inventory_overlay_panel)

	if _gameplay_hud:
		_gameplay_hud.body_grid_pressed.connect(_toggle_inventory)
		_gameplay_hud.menu_pressed.connect(_on_menu_pressed)
		_gameplay_hud.combat_log_pressed.connect(_on_combat_log_pressed)
		_gameplay_hud.bind_player_stats(player_stats)
		_gameplay_hud.bind_inventory(inventory)

	LocalizationManager.language_changed.connect(_on_language_changed)

	GameManager.state_changed.connect(_on_game_manager_state_changed)
	GameManager.start_game_requested.connect(_on_start_game_requested)
	GameManager.restart_requested.connect(_on_restart_requested)
	GameManager.return_to_main_menu_requested.connect(_on_return_to_main_menu)
	GameManager.continue_requested.connect(_on_continue_requested)
	GameManager.settings_requested.connect(_on_settings_requested)

	_set_gameplay_ui_visible(false)
	GameManager.change_state(GameManager.GameState.MAIN_MENU)
	call_deferred("_position_inventory_overlay_panel")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_M:
			if GameManager.get_state() == GameManager.GameState.GAMEPLAY:
				_map_ui.visible = not _map_ui.visible
				get_viewport().set_input_as_handled()
			return
	if not event.is_action_pressed("ui_cancel"):
		return
	## Settings modal consumes ESC while open (PROCESS_MODE_ALWAYS).
	if _settings != null and _settings.is_open():
		return
	if (
		_combat_ui != null
		and _combat_ui.visible
		and _combat_ui.has_method("is_combat_log_open")
		and _combat_ui.is_combat_log_open()
	):
		_combat_ui.hide_combat_log()
		get_viewport().set_input_as_handled()
		return
	if (
		not _inventory_combat_docked
		and _body_grid_overlay != null
		and _body_grid_overlay.visible
	):
		_hide_inventory_overlay()
		get_viewport().set_input_as_handled()
		return
	match GameManager.get_state():
		GameManager.GameState.GAMEPLAY:
			GameManager.request_pause_to_menu()
			get_viewport().set_input_as_handled()
		GameManager.GameState.MAIN_MENU:
			if GameManager.is_session_active:
				GameManager.request_continue()
				get_viewport().set_input_as_handled()


func _ensure_overlays() -> void:
	if _main_menu == null:
		_main_menu = MAIN_MENU_SCENE.instantiate() as MainMenuUI
		add_child(_main_menu)
		_main_menu.continue_pressed.connect(_on_main_menu_continue)
		_main_menu.new_game_pressed.connect(_on_main_menu_new_game)
		_main_menu.settings_pressed.connect(_on_main_menu_settings)
		_main_menu.exit_pressed.connect(_on_main_menu_exit)
	if _game_over == null:
		_game_over = GAME_OVER_SCENE.instantiate() as GameOverUI
		add_child(_game_over)
		_game_over.restart_pressed.connect(_on_game_over_restart)
		_game_over.main_menu_pressed.connect(_on_game_over_main_menu)
	if _settings == null:
		_settings = SETTINGS_SCENE.instantiate() as SettingsModal
		add_child(_settings)


func _on_language_changed(_locale: String) -> void:
	_map_ui.refresh()
	_inventory_ui.refresh()


func _style_body_grid_pane() -> void:
	if _body_grid_pane == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.11, 1.0)
	style.set_border_width_all(0)
	style.set_content_margin_all(12)
	_body_grid_pane.add_theme_stylebox_override("panel", style)
	_body_grid_pane.mouse_filter = Control.MOUSE_FILTER_STOP


func _style_inventory_modal_panel() -> void:
	## Modal Body Grid outside combat — framed like End Turn.
	if _inventory_panel == null:
		return
	if _body_grid_overlay:
		_body_grid_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dim := _body_grid_overlay.get_node_or_null("OverlayDim") as Control
		if dim:
			dim.visible = false
			dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 1.0)
	style.set_border_width_all(2)
	style.border_color = Color(0.92, 0.55, 0.18, 1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 8
	_inventory_panel.add_theme_stylebox_override("panel", style)
	_inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if _inventory_ui:
		_inventory_ui.mouse_filter = Control.MOUSE_FILTER_STOP


func _set_inventory_close_visible(visible_flag: bool) -> void:
	if _inventory_ui == null:
		return
	var close_btn := _inventory_ui.get_node_or_null("%CloseButton") as BaseButton
	if close_btn:
		close_btn.visible = visible_flag


func _mount_inventory_combat_dock() -> void:
	## Combat encounters: Body Grid is fixed on the right of the fight UI.
	_hide_inventory_overlay()
	if _inventory_ui != null and _body_grid_pane != null and _inventory_ui.get_parent() != _body_grid_pane:
		_inventory_ui.reparent(_body_grid_pane)
	_set_inventory_close_visible(false)
	if _stage_divider:
		_stage_divider.visible = true
	if _body_grid_pane:
		_body_grid_pane.visible = true
	_inventory_combat_docked = true
	var body_btn := get_node_or_null("%ToggleInventoryButton") as CanvasItem
	if body_btn:
		body_btn.visible = false


func _mount_inventory_modal_host() -> void:
	## Map / events / menus: Body Grid opens as a framed modal.
	if _stage_divider:
		_stage_divider.visible = false
	if _body_grid_pane:
		_body_grid_pane.visible = false
	if _inventory_ui != null and _inventory_panel != null and _inventory_ui.get_parent() != _inventory_panel:
		_inventory_ui.reparent(_inventory_panel)
	_set_inventory_close_visible(true)
	_inventory_combat_docked = false
	var body_btn := get_node_or_null("%ToggleInventoryButton") as CanvasItem
	if body_btn:
		body_btn.visible = true


func _seed_starting_loadout() -> void:
	inventory.reset_run()
	if player_stats != null:
		player_stats.reset_run()
		inventory.apply_actor_stats(player_stats)
		inventory.heal_full()
	_first_combat_xp_granted = false
	var scrap_pipe: ItemData = ItemDatabase.create_instance(STARTING_ITEM_ID)
	if scrap_pipe != null:
		inventory.place_item(scrap_pipe, BodyGrid.STARTER_ORIGIN)
	var heavy_armor: ItemData = ItemDatabase.create_instance(STARTING_ARMOR_ID)
	if heavy_armor != null:
		inventory.try_place_anywhere(heavy_armor)
	var bio_gel: ItemData = ItemDatabase.create_instance(STARTING_CONSUMABLE_ID)
	if bio_gel != null:
		inventory.try_place_anywhere(bio_gel)


func _set_flow(state: int) -> void:
	flow_state = state
	EventBus.game_state_changed.emit(state)


func _set_gameplay_ui_visible(visible_flag: bool) -> void:
	if _root_layout:
		_root_layout.visible = visible_flag
	if not visible_flag:
		_hide_inventory_overlay()


# --- GameManager / menu / game over -----------------------------------------

func _on_game_manager_state_changed(_previous: GameManager.GameState, new_state: GameManager.GameState) -> void:
	match new_state:
		GameManager.GameState.MAIN_MENU:
			_enter_main_menu()
		GameManager.GameState.STARTUP_SETUP:
			pass
		GameManager.GameState.GAMEPLAY:
			_enter_gameplay()
		GameManager.GameState.GAME_OVER:
			_enter_game_over()


func _enter_main_menu() -> void:
	if _game_over:
		_game_over.hide_game_over()
	if GameManager.is_session_active:
		## Soft pause: keep run (and combat) alive under the menu overlay.
		_set_gameplay_ui_visible(true)
	else:
		## Hard menu: tear down any mid-run combat and hide gameplay.
		if _combat.has_method("abort_combat"):
			_combat.abort_combat()
		if _inventory_ui.has_method("set_combat_mode"):
			_inventory_ui.set_combat_mode(false)
		_set_gameplay_ui_visible(false)
		_combat_ui.visible = false
	if _main_menu:
		_main_menu.show_menu()
	_hide_inventory_overlay()


func _enter_gameplay() -> void:
	if _main_menu:
		_main_menu.hide_menu()
	if _game_over:
		_game_over.hide_game_over()
	_set_gameplay_ui_visible(true)
	if _fresh_run_pending:
		_fresh_run_pending = false
		## Start a fresh act map immediately.
		_map_ui.visible = true
		_combat_ui.visible = false
		_status_banner.text = tr("KEY_STATUS_ONLINE")
		_run_flow.start_new_run()


func _enter_game_over() -> void:
	if _inventory_ui.has_method("set_combat_mode"):
		_inventory_ui.set_combat_mode(false)
	_combat_ui.visible = true
	if _main_menu:
		_main_menu.hide_menu()
	if _game_over:
		_game_over.show_game_over()


func _on_main_menu_continue() -> void:
	GameManager.request_continue()


func _on_main_menu_new_game() -> void:
	GameManager.request_new_game()


func _on_main_menu_settings() -> void:
	GameManager.request_open_settings()


func _on_main_menu_exit() -> void:
	get_tree().quit()


func _on_menu_pressed() -> void:
	GameManager.request_pause_to_menu()


func _on_combat_log_pressed() -> void:
	if _combat_ui == null or not _combat_ui.visible:
		return
	if _combat_ui.has_method("toggle_combat_log"):
		_combat_ui.toggle_combat_log()


func _on_settings_requested() -> void:
	if _settings:
		_settings.open_settings()


func _on_continue_requested() -> void:
	## State change to GAMEPLAY drives UI; nothing else to reset.
	pass


func _on_game_over_restart() -> void:
	GameManager.request_restart()


func _on_game_over_main_menu() -> void:
	GameManager.request_main_menu()


func _on_start_game_requested() -> void:
	_reset_run_to_startup()


func _on_restart_requested() -> void:
	_reset_run_to_startup()


func _on_return_to_main_menu() -> void:
	if _combat.has_method("abort_combat"):
		_combat.abort_combat()


func _reset_run_to_startup() -> void:
	## STARTUP_SETUP: full HP, clear grid, starter weapon/armor/consumable, reset map/combat.
	if _combat.has_method("abort_combat"):
		_combat.abort_combat()
	_seed_starting_loadout()
	_combat.setup(inventory, player_stats)
	_encounters.setup(inventory, player_stats, _combat)
	_encounter_combat_active = false
	if _dialog_event_ui != null and is_instance_valid(_dialog_event_ui):
		_dialog_event_ui.close_dialog()
	_inventory_ui.setup(inventory)
	if _inventory_ui.has_method("bind_player_stats"):
		_inventory_ui.bind_player_stats(player_stats)
	_mount_inventory_modal_host()
	if _gameplay_hud:
		_gameplay_hud.bind_player_stats(player_stats)
		_gameplay_hud.bind_inventory(inventory)
	if _inventory_ui.has_method("set_combat_mode"):
		_inventory_ui.set_combat_mode(false)
	_combat_ui.setup(_combat, inventory)
	_fresh_run_pending = true


func _on_player_died() -> void:
	## HP hit zero — stop combat interactions and open game over.
	if _inventory_ui.has_method("set_combat_mode"):
		_inventory_ui.set_combat_mode(false)
	GameManager.trigger_game_over()


func _show_exploring() -> void:
	_set_flow(GameFlowState.State.EXPLORING)
	_map_ui.visible = true
	_combat_ui.visible = false
	_mount_inventory_modal_host()
	if player_stats != null and player_stats.has_pending_level_ups():
		_show_inventory_for_level_up()
	else:
		_hide_inventory_overlay()
		if _inventory_ui.has_method("set_level_up_mode"):
			_inventory_ui.set_level_up_mode(false)
	if _inventory_ui.has_method("set_combat_mode"):
		_inventory_ui.set_combat_mode(false)
	_map_ui.refresh()
	_inventory_ui.refresh()


func _show_combat() -> void:
	_map_ui.visible = false
	_combat_ui.visible = true
	_mount_inventory_combat_dock()
	if _inventory_ui.has_method("set_combat_mode"):
		_inventory_ui.set_combat_mode(true, _combat)
	_inventory_ui.refresh()


func _toggle_inventory() -> void:
	## Outside combat only — in combat the grid is permanently docked.
	if _inventory_combat_docked:
		return
	if _body_grid_overlay == null:
		return
	if _body_grid_overlay.visible:
		_hide_inventory_overlay()
	else:
		_open_inventory_overlay()


func _open_inventory_overlay() -> void:
	if _inventory_combat_docked:
		return
	_mount_inventory_modal_host()
	if _body_grid_overlay == null:
		return
	_body_grid_overlay.visible = true
	if player_stats != null and player_stats.has_pending_level_ups():
		if _inventory_ui.has_method("set_level_up_mode"):
			_inventory_ui.set_level_up_mode(true)
	if _inventory_ui:
		_inventory_ui.refresh()
	_request_inventory_overlay_relayout()


func _hide_inventory_overlay() -> void:
	if _body_grid_overlay:
		_body_grid_overlay.visible = false


func _position_inventory_overlay_panel() -> void:
	if _inventory_panel == null or _body_grid_overlay == null or _inventory_combat_docked:
		return
	var panel_size := _inventory_overlay_content_min
	if _inventory_ui != null:
		panel_size = panel_size.max(_inventory_ui.custom_minimum_size)
	panel_size = panel_size.max(_inventory_panel.get_combined_minimum_size())
	panel_size.x = maxf(460.0, panel_size.x)
	panel_size.y = maxf(220.0, panel_size.y)
	_inventory_panel.offset_left = -16.0 - panel_size.x
	_inventory_panel.offset_right = -16.0
	_inventory_panel.offset_top = -panel_size.y * 0.5
	_inventory_panel.offset_bottom = panel_size.y * 0.5


func _request_inventory_overlay_relayout() -> void:
	call_deferred("_position_inventory_overlay_panel_deferred")


func _position_inventory_overlay_panel_deferred() -> void:
	await get_tree().process_frame
	_position_inventory_overlay_panel()


func _on_inventory_layout_fitted(min_size: Vector2) -> void:
	_inventory_overlay_content_min = min_size
	if _body_grid_overlay != null and _body_grid_overlay.visible and not _inventory_combat_docked:
		_request_inventory_overlay_relayout()


func _show_inventory_for_level_up() -> void:
	if _inventory_ui != null and _inventory_ui.has_method("set_level_up_mode"):
		_inventory_ui.set_level_up_mode(true)
	if _inventory_combat_docked:
		_inventory_ui.refresh()
		return
	_open_inventory_overlay()


func _expand_grid_demo() -> void:
	inventory.grid.expand_by_adjacent_cells(BodyGrid.LEVEL_UP_CELL_GAIN)
	_status_banner.text = tr("KEY_STATUS_MUTATED")
	_inventory_ui.refresh()


func _on_node_chosen(node_id: String) -> void:
	_run_flow.select_node_by_id(node_id)

func _on_run_map_changed(map_data: MapData) -> void:
	if _map_ui.has_method("set_map_data"):
		_map_ui.set_map_data(map_data)
	_map_ui.refresh()
	_inventory_ui.refresh()


func _on_run_state_changed(_prev: RunFlowManager.RunState, new_state: RunFlowManager.RunState) -> void:
	if new_state == RunFlowManager.RunState.MAP_VIEW:
		_show_exploring()
	elif new_state == RunFlowManager.RunState.VICTORY:
		_status_banner.text = tr("KEY_STATUS_RUN_COMPLETE")
		_set_flow(GameFlowState.State.VICTORY)


func _on_encounter_started(data: EncounterData) -> void:
	if data == null:
		return
	_status_banner.text = data.get_display_title()


func _on_encounter_completed(rewards: Dictionary) -> void:
	var message_key := str(rewards.get("message_key", ""))
	_show_exploring()
	if not message_key.is_empty():
		_status_banner.text = tr(message_key)
	elif bool(rewards.get("combat_victory", false)):
		_status_banner.text = tr("KEY_STATUS_SECTOR_SECURED")
	_map_ui.refresh()
	_inventory_ui.refresh()


func _on_encounter_request_combat(enemy_datas: Array, encounter: EncounterData) -> void:
	_encounter_combat_active = true
	_pending_combat_exp_reward = 0
	var datas: Array[EnemyData] = []
	for entry in enemy_datas:
		if entry is EnemyData:
			var data := entry as EnemyData
			datas.append(data)
			## Summoned / zero-XP blueprints do not contribute to combat XP.
			if data.exp_reward > 0 and not ("summoned_creature" in data.trait_ids):
				_pending_combat_exp_reward += maxi(data.exp_reward, 0)
	_show_combat()
	_combat_ui.setup(_combat, inventory)
	_combat.start_combat(datas)
	var label := encounter.get_display_title() if encounter != null else tr("KEY_STATUS_ENGAGEMENT")
	_status_banner.text = tr("KEY_STATUS_ENGAGEMENT") % label


func _on_encounter_request_dialog(dialog: DialogEventData, encounter: EncounterData) -> void:
	_ensure_dialog_event_ui()
	if _dialog_event_ui:
		_dialog_event_ui.bind_encounter_manager(_encounters)
		if encounter != null:
			_dialog_event_ui.set_encounter_type(encounter.type)
		## Wait one frame so TopBar has a valid size before measuring clearance.
		await get_tree().process_frame
		_layout_dialog_event_under_top_bar()
		_dialog_event_ui.start_event(dialog)


func _on_encounter_placeholder(_encounter: EncounterData, message_key: String) -> void:
	if not message_key.is_empty():
		_status_banner.text = tr(message_key)


func _on_encounter_request_item_selection(item_pool: Array, title: String) -> void:
	_ensure_select_item_ui()
	if _select_item_ui:
		_select_item_ui.open_item_selection(item_pool, title)


func _ensure_select_item_ui() -> void:
	if _select_item_ui != null and is_instance_valid(_select_item_ui):
		return
	_select_item_ui = SELECT_ITEM_SCENE.instantiate() as SelectItemUI
	_select_item_ui.name = "SelectItemUI"
	add_child(_select_item_ui)
	_select_item_ui.item_selected.connect(_on_select_item_chosen)


func _on_select_item_chosen(item: ItemData) -> void:
	_encounters.resolve_item_selection(item)
	if _inventory_ui:
		_inventory_ui.refresh()


func _ensure_dialog_event_ui() -> void:
	if _dialog_event_ui != null and is_instance_valid(_dialog_event_ui):
		return
	_dialog_event_ui = DIALOG_EVENT_SCENE.instantiate() as DialogEventUI
	_dialog_event_ui.name = "DialogEventUI"
	add_child(_dialog_event_ui)
	if not resized.is_connected(_on_main_resized_for_dialog):
		resized.connect(_on_main_resized_for_dialog)


func _layout_dialog_event_under_top_bar() -> void:
	if _dialog_event_ui == null or not is_instance_valid(_dialog_event_ui):
		return
	## Leave the shared TopBar (HP + actions) exposed above the event module.
	var pad := 0.0
	if _root_layout:
		pad = float(_root_layout.get_theme_constant("separation"))
	_dialog_event_ui.layout_below_top_bar(_gameplay_hud, pad)


func _on_main_resized_for_dialog() -> void:
	if _dialog_event_ui != null and _dialog_event_ui.visible:
		_layout_dialog_event_under_top_bar()


func _on_end_turn() -> void:
	_combat.end_player_turn()


func _on_inventory_item_activated(placed: PlacedItem) -> void:
	if GameManager.is_game_over():
		return
	if _combat.activate_item(placed):
		_inventory_ui.refresh()


func _on_target(index: int) -> void:
	_combat.set_target(index)


func _on_combat_state(_s: int) -> void:
	if GameManager.is_game_over():
		if _inventory_ui.has_method("set_combat_mode"):
			_inventory_ui.set_combat_mode(false)
		return
	if _inventory_ui.has_method("set_combat_mode"):
		var in_combat: bool = (
			_combat.state == _combat.CombatState.PLAYER_TURN
			or _combat.state == _combat.CombatState.ENEMY_TURN
		)
		_inventory_ui.set_combat_mode(in_combat, _combat if in_combat else null)
	_inventory_ui.refresh()


func _on_combat_ended_bus(victory: bool) -> void:
	if GameManager.is_game_over():
		return
	if victory:
		var gained_xp := _resolve_victory_xp_reward()
		if gained_xp > 0:
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_XP_GAINED") % gained_xp
			)
		if player_stats != null:
			player_stats.add_exp(gained_xp)
		_status_banner.text = tr("KEY_STATUS_COMBAT_WIN")
	else:
		_status_banner.text = tr("KEY_STATUS_COMBAT_LOSE")
	_pending_combat_exp_reward = 0


func _resolve_victory_xp_reward() -> int:
	## First victory is always 30 XP; after that, use enemy data rewards as-is.
	if not _first_combat_xp_granted:
		_first_combat_xp_granted = true
		return 30
	return maxi(_pending_combat_exp_reward, 0)


func _on_pending_level_ups_changed(count: int) -> void:
	## Auto-open Body Grid and enter LEVEL_UP mode when XP grants a pending reveal.
	if count <= 0:
		if _inventory_ui != null and _inventory_ui.has_method("set_level_up_mode"):
			_inventory_ui.set_level_up_mode(false)
		return
	_show_inventory_for_level_up()


func _on_combat_continue() -> void:
	if GameManager.is_game_over():
		return
	if _combat.state == _combat.CombatState.VICTORY:
		if _encounter_combat_active:
			_encounter_combat_active = false
			## EncounterManager emits encounter_completed → map advance / prologue exit.
			_encounters.notify_combat_finished(true)
	elif _combat.state == _combat.CombatState.DEFEAT:
		if _encounter_combat_active:
			_encounter_combat_active = false
			_encounters.notify_combat_finished(false)
		## Defeat is handled by Game Over modal; keep explore fallback if needed.
		_show_exploring()
		_status_banner.text = tr("KEY_STATUS_WRECKAGE")
