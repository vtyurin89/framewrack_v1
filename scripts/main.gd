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

@onready var _map_ui: Control = %MapUI
@onready var _inventory_ui: Control = %InventoryUI
@onready var _combat_ui: Control = %CombatUI
@onready var _status_banner: Label = %StatusBanner
@onready var _inventory_panel: PanelContainer = %InventoryPanel
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

@onready var _combat: Node = $CombatManager
@onready var _map: Node = $MapManager


func _ready() -> void:
	inventory = InventoryController.new()
	player_stats = PlayerStats.new()
	player_stats.leveled_up.connect(_on_player_leveled_up)
	_combat.setup(inventory)
	_style_inventory_panel()
	_ensure_overlays()

	_map_ui.setup(_map)
	_inventory_ui.setup(inventory)
	_combat_ui.setup(_combat, inventory)

	_map.node_entered.connect(_on_map_node_entered)
	_map.map_finished.connect(_on_map_finished)
	_map_ui.node_chosen.connect(_on_node_chosen)
	_combat_ui.end_turn_pressed.connect(_on_end_turn)
	_combat_ui.target_selected.connect(_on_target)
	_combat_ui.continue_pressed.connect(_on_combat_continue)
	_combat.state_changed.connect(_on_combat_state)
	EventBus.combat_ended.connect(_on_combat_ended_bus)
	EventBus.player_died.connect(_on_player_died)
	if _inventory_ui.has_signal("item_activated"):
		_inventory_ui.item_activated.connect(_on_inventory_item_activated)

	if _gameplay_hud:
		_gameplay_hud.body_grid_pressed.connect(_toggle_inventory)
		_gameplay_hud.menu_pressed.connect(_on_menu_pressed)
		_gameplay_hud.bind_player_stats(player_stats)

	LocalizationManager.language_changed.connect(_on_language_changed)

	GameManager.state_changed.connect(_on_game_manager_state_changed)
	GameManager.start_game_requested.connect(_on_start_game_requested)
	GameManager.restart_requested.connect(_on_restart_requested)
	GameManager.return_to_main_menu_requested.connect(_on_return_to_main_menu)
	GameManager.continue_requested.connect(_on_continue_requested)
	GameManager.settings_requested.connect(_on_settings_requested)

	_set_gameplay_ui_visible(false)
	GameManager.change_state(GameManager.GameState.MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	## Settings modal consumes ESC while open (PROCESS_MODE_ALWAYS).
	if _settings != null and _settings.is_open():
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


func _style_inventory_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.14, 0.14, 1)
	style.set_border_width_all(1)
	style.border_color = Color(0.35, 0.35, 0.35)
	style.set_content_margin_all(10)
	_inventory_panel.add_theme_stylebox_override("panel", style)


func _seed_starting_loadout() -> void:
	inventory.reset_run()
	if player_stats != null:
		player_stats.reset_run()
	_first_combat_xp_granted = false
	var scrap_pipe: ItemData = ItemDatabase.create_instance(STARTING_ITEM_ID)
	if scrap_pipe != null:
		inventory.place_item(scrap_pipe, Vector2i(0, 0))
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


func _enter_gameplay() -> void:
	if _main_menu:
		_main_menu.hide_menu()
	if _game_over:
		_game_over.hide_game_over()
	_set_gameplay_ui_visible(true)
	if _fresh_run_pending:
		_fresh_run_pending = false
		_show_exploring()
		_status_banner.text = tr("KEY_STATUS_ONLINE")
		EventBus.run_started.emit()


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
	_map.reset()
	_seed_starting_loadout()
	_combat.setup(inventory)
	_inventory_ui.setup(inventory)
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
	_inventory_panel.visible = true
	if _inventory_ui.has_method("set_combat_mode"):
		_inventory_ui.set_combat_mode(false)
	_map_ui.refresh()
	_inventory_ui.refresh()


func _show_combat() -> void:
	_map_ui.visible = false
	_combat_ui.visible = true
	_inventory_panel.visible = true
	if _inventory_ui.has_method("set_combat_mode"):
		_inventory_ui.set_combat_mode(true, _combat)


func _toggle_inventory() -> void:
	_inventory_panel.visible = not _inventory_panel.visible


func _expand_grid_demo() -> void:
	var cells: Array[Vector2i] = [
		Vector2i(4, 0),
		Vector2i(4, 1),
		Vector2i(4, 2),
		Vector2i(3, 4),
		Vector2i(4, 4),
	]
	inventory.grid.unlock_cells(cells)
	_status_banner.text = tr("KEY_STATUS_MUTATED")
	_inventory_ui.refresh()


func _on_node_chosen(node_id: String) -> void:
	_map.select_node(node_id)


func _on_map_node_entered(_node_id: String, node_type: int) -> void:
	match node_type:
		MapManager.NodeType.COMBAT, MapManager.NodeType.BOSS:
			_start_combat_for_current()
		MapManager.NodeType.REPAIR:
			inventory.grid.clear_all_corruption()
			inventory.heal_full()
			_status_banner.text = tr("KEY_STATUS_REPAIR")
			_map.complete_current()
			_map_ui.refresh()
			_inventory_ui.refresh()
		MapManager.NodeType.EVENT:
			var loot: ItemData = ItemDatabase.create_instance(EVENT_LOOT_ITEM_ID)
			if loot != null:
				inventory.try_place_anywhere(loot)
			inventory.current_hp = mini(inventory.max_hp, inventory.current_hp + 10)
			EventBus.player_hp_changed.emit(inventory.current_hp, inventory.max_hp)
			_status_banner.text = tr("KEY_STATUS_EVENT")
			_map.complete_current()
			_map_ui.refresh()
			_inventory_ui.refresh()
		_:
			pass


func _start_combat_for_current() -> void:
	var node: Dictionary = _map.get_current()
	var enemy_ids: Array = node.get("enemy_ids", [])
	var datas: Array[EnemyData] = []
	_pending_combat_exp_reward = 0
	for eid in enemy_ids:
		match str(eid):
			"desperate_rebel":
				datas.append(ENEMY_REBEL.duplicate(true) as EnemyData)
			"corrupted_synthet":
				datas.append(ENEMY_SYNTHET.duplicate(true) as EnemyData)
	for enemy_data: EnemyData in datas:
		if enemy_data == null:
			continue
		_pending_combat_exp_reward += maxi(enemy_data.exp_reward, 0)
	_show_combat()
	_combat_ui.setup(_combat, inventory)
	_combat.start_combat(datas)
	var node_label := str(node.get("label", "Unknown"))
	var label_key := str(node.get("label_key", ""))
	if not label_key.is_empty():
		node_label = tr(label_key)
	_status_banner.text = tr("KEY_STATUS_ENGAGEMENT") % node_label


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


func _on_player_leveled_up(_new_level: int) -> void:
	## +3 cells per level up: expand right-side column, top-to-bottom.
	var g := inventory.grid
	if g == null:
		return
	var new_cells: Array[Vector2i] = []
	var column_x := g.width
	for i in 3:
		new_cells.append(Vector2i(column_x, i))
	g.unlock_cells(new_cells)
	_inventory_ui.refresh()


func _on_combat_continue() -> void:
	if GameManager.is_game_over():
		return
	if _combat.state == _combat.CombatState.VICTORY:
		_map.complete_current()
		_show_exploring()
		_status_banner.text = tr("KEY_STATUS_SECTOR_SECURED")
	elif _combat.state == _combat.CombatState.DEFEAT:
		## Defeat is handled by Game Over modal; keep explore fallback if needed.
		_show_exploring()
		_status_banner.text = tr("KEY_STATUS_WRECKAGE")


func _on_map_finished() -> void:
	_status_banner.text = tr("KEY_STATUS_RUN_COMPLETE")
	_set_flow(GameFlowState.State.VICTORY)
