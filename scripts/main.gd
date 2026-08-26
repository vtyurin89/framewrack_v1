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
const REST_SITE_SCENE := preload("res://scenes/UI/rest_site_ui.tscn")
const SHOP_SCREEN_SCENE := preload("res://scenes/UI/shop_screen.tscn")
const SELECT_ITEM_SCENE := preload("res://scenes/UI/select_item_ui.tscn")
const REWARD_SCREEN_SCENE := preload("res://scenes/UI/reward_screen.tscn")
const CHEST_REWARD_SCENE := preload("res://scenes/UI/chest_reward_ui.tscn")
const FORCED_ITEM_SCREEN_SCENE := preload("res://scenes/UI/forced_item_screen.tscn")
const ANNOUNCER_SCENE := preload("res://scenes/UI/announcer_ui.tscn")
const BOOT_SEQUENCE_SCENE := preload("res://scenes/UI/boot_sequence.tscn")
const CRT_OVERLAY_SCRIPT := preload("res://scripts/ui/crt_overlay.gd")
const HUMANITY_GAME_OVER_REASON_KEY := "KEY_GAME_OVER_INSANITY"

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
var _rest_site_ui: RestSiteUI
var _shop_screen: ShopScreen
var _select_item_ui: SelectItemUI
var _reward_screen: RewardScreen
var _chest_reward_ui: ChestRewardUI
var _forced_item_screen: ForcedItemScreen
var _announcer_ui: AnnouncerUI
var _boot_sequence: BootSequence
var _boot_generation: int = 0
var _post_combat_reward_active: bool = false
var _chest_site_active: bool = false
var _chest_loot_active: bool = false
var _dialog_loot_active: bool = false
var _forced_insertion_active: bool = false
var _encounter_combat_active: bool = false
var _shop_active: bool = false
var _last_announced_act_index: int = 0


func _ready() -> void:
	inventory = InventoryController.new()
	player_stats = PlayerStats.new()
	player_stats.pending_level_ups_changed.connect(_on_pending_level_ups_changed)
	player_stats.stats_changed.connect(_on_player_stats_changed)
	inventory.apply_actor_stats(player_stats)
	inventory.heal_full()
	_combat.setup(inventory, player_stats)
	_encounters.setup(inventory, player_stats, _combat)
	_encounters.encounter_started.connect(_on_encounter_started)
	_encounters.encounter_completed.connect(_on_encounter_completed)
	_encounters.request_combat.connect(_on_encounter_request_combat)
	_encounters.request_show_dialog.connect(_on_encounter_request_dialog)
	_encounters.request_show_placeholder.connect(_on_encounter_placeholder)
	_encounters.request_show_rest_site.connect(_on_encounter_request_rest_site)
	_encounters.request_show_shop.connect(_on_encounter_request_shop)
	_encounters.request_show_chest_reward.connect(_on_encounter_request_chest_reward)
	_encounters.request_item_selection.connect(_on_encounter_request_item_selection)
	_encounters.request_dialog_loot.connect(_on_encounter_request_dialog_loot)
	_encounters.request_post_combat_rewards.connect(_on_encounter_request_post_combat_rewards)
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
	if _combat.has_signal("forced_insertion_requested"):
		_combat.forced_insertion_requested.connect(_on_forced_insertion_requested)
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
		_gameplay_hud.bind_inventory_ui(_inventory_ui)
		_gameplay_hud.bind_combat(_combat)
		_gameplay_hud.debug_inventory_requested.connect(_on_debug_inventory_requested)
		_gameplay_hud.debug_act_jump_requested.connect(_on_debug_act_jump_requested)

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
				## Don't toggle map under an active boot cutscene.
				if _boot_sequence != null and _boot_sequence.is_playing():
					get_viewport().set_input_as_handled()
					return
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
			## Boot sequence: ESC opens pause menu and freezes the cutscene.
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
		UiOverlayLayer.mount(_settings, self)
		if not _settings.is_inside_tree():
			add_child(_settings)
	if _announcer_ui == null:
		_announcer_ui = ANNOUNCER_SCENE.instantiate() as AnnouncerUI
		_announcer_ui.name = "AnnouncerUI"
		add_child(_announcer_ui)
	_ensure_crt_overlay()
	_apply_crt_root_chrome()


func _ensure_crt_overlay() -> void:
	if get_node_or_null("CrtOverlay") != null:
		return
	var overlay: CrtOverlay = CRT_OVERLAY_SCRIPT.new() as CrtOverlay
	overlay.name = "CrtOverlay"
	add_child(overlay)


func _apply_crt_root_chrome() -> void:
	var bg := get_node_or_null("Background") as ColorRect
	if bg:
		bg.color = GamePalette.BACKGROUND_DARK
	if _stage_divider:
		_stage_divider.color = GamePalette.MUTED_GREEN
	if _status_banner:
		GamePalette.apply_label_muted(_status_banner)
	var overlay_dim := get_node_or_null("OverlayLayer/BodyGridOverlay/OverlayDim") as ColorRect
	if overlay_dim:
		overlay_dim.color = Color(
			GamePalette.BACKGROUND_DARK.r,
			GamePalette.BACKGROUND_DARK.g,
			GamePalette.BACKGROUND_DARK.b,
			0.72
		)


func _on_language_changed(_locale: String) -> void:
	_map_ui.refresh()
	_inventory_ui.refresh()


func _style_body_grid_pane() -> void:
	if _body_grid_pane == null:
		return
	var style := GamePalette.make_panel_stylebox(
		GamePalette.PANEL_BG, GamePalette.MUTED_GREEN, 1, 0, 12.0, false
	)
	_body_grid_pane.add_theme_stylebox_override("panel", style)
	_body_grid_pane.mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_crt_grid_noise(_body_grid_pane)


func _style_inventory_modal_panel() -> void:
	## Modal Body Grid outside combat — CRT framed panel.
	if _inventory_panel == null:
		return
	if _body_grid_overlay:
		_body_grid_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dim := _body_grid_overlay.get_node_or_null("OverlayDim") as Control
		if dim:
			dim.visible = false
			dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := GamePalette.make_panel_stylebox(
		GamePalette.PANEL_BG, GamePalette.PHOSPHOR_ACTIVE, 1, 0, 10.0, true
	)
	_inventory_panel.add_theme_stylebox_override("panel", style)
	_inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_crt_grid_noise(_inventory_panel)
	if _inventory_ui:
		_inventory_ui.mouse_filter = Control.MOUSE_FILTER_STOP


func _ensure_crt_grid_noise(host: Control) -> void:
	## Full-rect translucent overlay ABOVE cells/items so grain hits the whole panel.
	if host == null:
		return
	var existing := host.get_node_or_null("CrtGridNoise") as ColorRect
	if existing != null:
		existing.z_index = 5
		_keep_crt_grid_noise_on_top(host)
		return
	var shader := load("res://shaders/crt_grid_noise.gdshader") as Shader
	if shader == null:
		push_warning("Main: failed to load crt_grid_noise shader")
		return
	var noise := ColorRect.new()
	noise.name = "CrtGridNoise"
	noise.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noise.color = Color(1, 1, 1, 1)
	## Only need to sit above Body Grid content within this panel — not above modals.
	noise.z_index = 5
	noise.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	noise.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	noise.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var mat := ShaderMaterial.new()
	mat.shader = shader
	noise.material = mat
	host.add_child(noise)
	_keep_crt_grid_noise_on_top(host)


func _keep_crt_grid_noise_on_top(host: Control) -> void:
	if host == null:
		return
	var noise := host.get_node_or_null("CrtGridNoise") as ColorRect
	if noise != null:
		host.move_child(noise, host.get_child_count() - 1)


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
	_keep_crt_grid_noise_on_top(_body_grid_pane)
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
	_keep_crt_grid_noise_on_top(_inventory_panel)
	_set_inventory_close_visible(true)
	_inventory_combat_docked = false
	var body_btn := get_node_or_null("%ToggleInventoryButton") as CanvasItem
	if body_btn:
		body_btn.visible = true


func _seed_starting_loadout() -> void:
	inventory.reset_run()
	if GameManager != null:
		GameManager.reset_currency()
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
		if _boot_sequence != null and _boot_sequence.is_playing():
			_boot_generation += 1
			_boot_sequence.stop()
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
		## CRT boot, then opening dialogue via act intro.
		_play_boot_then_start_run()
		return


func _play_boot_then_start_run() -> void:
	_ensure_boot_sequence()
	_boot_generation += 1
	var token := _boot_generation
	if _boot_sequence.is_playing():
		_boot_sequence.stop()
	## Hide map/combat under the boot overlay; HUD stays for pause affordance.
	if _map_ui:
		_map_ui.visible = false
	if _combat_ui:
		_combat_ui.visible = false
	if _status_banner:
		_status_banner.text = ""
	_boot_sequence.play()
	await _boot_sequence.finished
	if not is_instance_valid(self) or token != _boot_generation:
		return
	## Soft-pause during boot must not skip the opening dialogue.
	if GameManager != null and GameManager.get_state() != GameManager.GameState.GAMEPLAY:
		while (
			is_instance_valid(self)
			and token == _boot_generation
			and GameManager != null
			and GameManager.get_state() != GameManager.GameState.GAMEPLAY
		):
			await get_tree().process_frame
	if not is_instance_valid(self) or token != _boot_generation:
		return
	if _map_ui:
		_map_ui.visible = true
	if _combat_ui:
		_combat_ui.visible = false
	if _status_banner:
		_status_banner.text = tr("KEY_STATUS_ONLINE")
	_run_flow.start_new_run()


func _ensure_boot_sequence() -> void:
	if _boot_sequence != null and is_instance_valid(_boot_sequence):
		return
	_boot_sequence = BOOT_SEQUENCE_SCENE.instantiate() as BootSequence
	_boot_sequence.name = "BootSequence"
	add_child(_boot_sequence)
	## ESC is handled by Main → pause menu; boot freezes via GameManager.state_changed.

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
	if _settings == null:
		_settings = SETTINGS_SCENE.instantiate() as SettingsModal
	UiOverlayLayer.mount(_settings, self)
	if not _settings.is_inside_tree():
		add_child(_settings)
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
	_last_announced_act_index = 0
	if StoryEventManager != null:
		StoryEventManager.reset_run()
	_seed_starting_loadout()
	_combat.setup(inventory, player_stats)
	_encounters.setup(inventory, player_stats, _combat)
	_encounter_combat_active = false
	if _dialog_event_ui != null and is_instance_valid(_dialog_event_ui):
		_dialog_event_ui.close_dialog()
	if _rest_site_ui != null and is_instance_valid(_rest_site_ui):
		_rest_site_ui.close_rest_site()
	_shop_active = false
	if _shop_screen != null and is_instance_valid(_shop_screen):
		_shop_screen.close_session()
	elif ShopManager != null:
		ShopManager.clear_session()
	_inventory_ui.setup(inventory)
	if _inventory_ui.has_method("bind_player_stats"):
		_inventory_ui.bind_player_stats(player_stats)
	_mount_inventory_modal_host()
	if _gameplay_hud:
		_gameplay_hud.bind_player_stats(player_stats)
		_gameplay_hud.bind_inventory(inventory)
		_gameplay_hud.bind_inventory_ui(_inventory_ui)
		_gameplay_hud.bind_combat(_combat)
	if _inventory_ui.has_method("set_combat_mode"):
		_inventory_ui.set_combat_mode(false)
	_combat_ui.setup(_combat, inventory)
	_fresh_run_pending = true


func _on_player_died() -> void:
	## HP hit zero — stop combat interactions and open game over.
	if _inventory_ui.has_method("set_combat_mode"):
		_inventory_ui.set_combat_mode(false)
	_abort_active_encounter_on_run_end()
	GameManager.trigger_game_over()


func _on_player_stats_changed() -> void:
	## Humanity at zero means the protagonist has irreversibly lost control.
	if player_stats == null or player_stats.humanity > 0:
		return
	if not GameManager.is_session_active or GameManager.is_game_over():
		return
	if _combat != null and _combat.has_method("abort_combat"):
		_combat.abort_combat()
	_abort_active_encounter_on_run_end()
	GameManager.trigger_game_over(HUMANITY_GAME_OVER_REASON_KEY)


func _abort_active_encounter_on_run_end() -> void:
	if _encounters != null and _encounters.has_method("abort_active_encounter"):
		_encounters.abort_active_encounter()
	if _dialog_event_ui != null and is_instance_valid(_dialog_event_ui) and _dialog_event_ui.visible:
		_dialog_event_ui.abort_on_run_end()


func _show_exploring() -> void:
	_set_flow(GameFlowState.State.EXPLORING)
	_shop_active = false
	_chest_site_active = false
	_chest_loot_active = false
	_dialog_loot_active = false
	if _chest_reward_ui != null and is_instance_valid(_chest_reward_ui):
		_chest_reward_ui.close_session()
	if _shop_screen != null and is_instance_valid(_shop_screen) and _shop_screen.is_active():
		_shop_screen.close_session()
	elif ShopManager != null:
		ShopManager.clear_session()
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


func _on_debug_inventory_requested() -> void:
	## Items debug catalog needs the Body Grid visible for drops.
	if _inventory_combat_docked:
		return
	if _body_grid_overlay != null and not _body_grid_overlay.visible:
		_toggle_inventory()
	if _inventory_ui != null:
		_inventory_ui.refresh()


func _on_debug_act_jump_requested(act_index: int) -> void:
	## Finish / abort any live event UI, then regenerate the chosen act from its intro.
	if _combat != null and _combat.has_method("abort_combat"):
		_combat.abort_combat()
	_abort_active_encounter_on_run_end()
	if _reward_screen != null and is_instance_valid(_reward_screen) and _reward_screen.is_active():
		_reward_screen.close_session()
	if _forced_item_screen != null and is_instance_valid(_forced_item_screen) and _forced_item_screen.is_active():
		## Force-close without completing insertion mid-debug jump.
		if _forced_item_screen.has_method("close_session"):
			_forced_item_screen.close_session()
	_forced_insertion_active = false
	_encounter_combat_active = false
	_last_announced_act_index = -1
	_show_exploring()
	if _run_flow != null and _run_flow.has_method("debug_jump_to_act"):
		_run_flow.debug_jump_to_act(act_index)


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
	elif new_state == RunFlowManager.RunState.ACT_INTRO:
		_try_announce_act()
	elif new_state == RunFlowManager.RunState.VICTORY:
		_status_banner.text = tr("KEY_STATUS_RUN_COMPLETE")
		_set_flow(GameFlowState.State.VICTORY)


func _try_announce_act() -> void:
	if _announcer_ui == null or _run_flow == null or _run_flow.current_act == null:
		return
	var act_index := _run_flow.current_act_index
	if act_index == _last_announced_act_index:
		return
	_last_announced_act_index = act_index
	var act_text := "%s\n%s" % [
		tr("KEY_ACT_ANNOUNCE_CHAPTER") % act_index,
		_run_flow.current_act.get_localized_title(),
	]
	_announcer_ui.announce_chapter(act_text)


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
	var attack_cap := 2
	if encounter != null:
		attack_cap = maxi(1, int(encounter.payload.get("max_attackers_per_turn", 2)))
	_combat.start_combat(datas, attack_cap)
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


func _on_encounter_request_rest_site(_encounter: EncounterData) -> void:
	_ensure_rest_site_ui()
	if _rest_site_ui == null:
		_encounters.complete_rest_site()
		return
	_rest_site_ui.bind(inventory, _encounters)
	await get_tree().process_frame
	_layout_rest_site_under_top_bar()
	_rest_site_ui.open_rest_site()


func _on_encounter_request_shop(_encounter: EncounterData, price_multiplier: float) -> void:
	_ensure_shop_screen()
	if _shop_screen == null:
		_encounters.complete_shop_site()
		return
	_shop_active = true
	_map_ui.visible = false
	_combat_ui.visible = true
	if not _inventory_combat_docked:
		_mount_inventory_combat_dock()
	_hide_inventory_overlay()
	if _inventory_ui.has_method("set_combat_mode"):
		_inventory_ui.set_combat_mode(false)
	_inventory_ui.refresh()
	if _combat_ui.has_method("set_reward_phase"):
		_combat_ui.set_reward_phase(true, "KEY_STATUS_SHOP_OPEN")
	if _combat_ui.has_method("set_continue_enabled"):
		_combat_ui.set_continue_enabled(true)
	var act := 1
	if _run_flow != null:
		act = maxi(_run_flow.current_act_index, 1)
	if _encounter != null:
		act = maxi(int(_encounter.payload.get("act", act)), 1)
	var stock: Array[ItemData] = ShopManager.generate_stock(act, ShopManager.STOCK_COUNT)
	ShopManager.begin_session(stock, price_multiplier)
	_status_banner.text = tr("KEY_STATUS_SHOP_OPEN")
	await get_tree().process_frame
	_shop_screen.open_session(inventory, _inventory_ui)


func _on_encounter_request_chest_reward(encounter: EncounterData) -> void:
	_chest_site_active = true
	_chest_loot_active = false
	_map_ui.visible = false
	_combat_ui.visible = true
	if not _inventory_combat_docked:
		_mount_inventory_combat_dock()
	_hide_inventory_overlay()
	if _inventory_ui.has_method("set_combat_mode"):
		_inventory_ui.set_combat_mode(false)
	_inventory_ui.refresh()
	if _combat_ui.has_method("set_chest_phase"):
		_combat_ui.set_chest_phase(true)
	_ensure_chest_reward_ui()
	var locked := true
	if encounter != null:
		locked = bool(encounter.payload.get("locked", true))
	_status_banner.text = tr("KEY_TYPE_REWARD")
	if _chest_reward_ui != null:
		_chest_reward_ui.open_session(inventory, locked)


func _ensure_chest_reward_ui() -> void:
	var host: Control = null
	if _combat_ui != null and _combat_ui.has_method("get_loot_stage"):
		host = _combat_ui.get_loot_stage()
	if host == null:
		host = _combat_ui
	if _chest_reward_ui != null and is_instance_valid(_chest_reward_ui):
		if _chest_reward_ui.get_parent() != host and host != null:
			_chest_reward_ui.reparent(host)
			_chest_reward_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	_chest_reward_ui = CHEST_REWARD_SCENE.instantiate() as ChestRewardUI
	_chest_reward_ui.name = "ChestRewardUI"
	if host != null:
		host.add_child(_chest_reward_ui)
	else:
		add_child(_chest_reward_ui)
	_chest_reward_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chest_reward_ui.loot_opened.connect(_on_chest_loot_opened)


func _on_chest_loot_opened() -> void:
	if not _chest_site_active:
		return
	_ensure_reward_screen()
	var act_depth := 1
	if _run_flow != null:
		act_depth = maxi(_run_flow.current_act_index, 1)
		if _run_flow.current_map_data != null:
			var cur := _run_flow.current_map_data.get_node(_run_flow.current_map_data.current_node_id)
			if cur != null:
				act_depth = maxi(cur.layer, 0)
	var loot := RewardManager.generate_chest_rewards(act_depth)
	_chest_loot_active = true
	if _combat_ui.has_method("set_reward_phase"):
		_combat_ui.set_reward_phase(true, "KEY_REWARD_SELECT_ONE")
	_status_banner.text = tr("KEY_REWARD_SELECT_ONE")
	_reward_screen.open_session(loot, inventory, _inventory_ui, RewardManager.CHEST_PICKS)


func _finish_chest_site(opened: bool) -> void:
	if _chest_reward_ui != null:
		_chest_reward_ui.close_session()
	if _reward_screen != null and _reward_screen.is_active():
		_reward_screen.close_session()
	_chest_site_active = false
	_chest_loot_active = false
	_post_combat_reward_active = false
	if _combat_ui != null and _combat_ui.has_method("set_reward_phase"):
		_combat_ui.set_reward_phase(false)
	if _inventory_ui != null and _inventory_ui.has_method("set_reward_handler"):
		_inventory_ui.set_reward_handler(null)
	_encounters.complete_chest_site(opened)


func _on_encounter_placeholder(_encounter: EncounterData, message_key: String) -> void:
	if not message_key.is_empty():
		_status_banner.text = tr(message_key)


func _on_encounter_request_item_selection(item_pool: Array, title: String) -> void:
	_ensure_select_item_ui()
	if _select_item_ui:
		_select_item_ui.open_item_selection(item_pool, title)


func _on_encounter_request_dialog_loot(items: Array, pick_count: int, title_key: String) -> void:
	## Story-event loot uses the same RewardScreen as chests / post-combat.
	_dialog_loot_active = true
	if _dialog_event_ui != null and is_instance_valid(_dialog_event_ui):
		_dialog_event_ui.visible = false
	_show_combat()
	if not _inventory_combat_docked:
		_mount_inventory_combat_dock()
	_hide_inventory_overlay()
	if _inventory_ui != null and _inventory_ui.has_method("set_combat_mode"):
		_inventory_ui.set_combat_mode(false)
	_ensure_reward_screen()
	var loot: Array[ItemData] = []
	for entry in items:
		if entry is ItemData:
			loot.append(entry as ItemData)
	var picks := maxi(1, pick_count)
	if _combat_ui != null and _combat_ui.has_method("set_reward_phase"):
		_combat_ui.set_reward_phase(true, title_key if not title_key.is_empty() else "KEY_REWARD_SELECT_ONE")
	_status_banner.text = tr(title_key if not title_key.is_empty() else "KEY_REWARD_SELECT_ONE")
	if picks >= 2:
		_status_banner.text = tr("KEY_REWARD_SELECT_UP_TO_3")
	_reward_screen.open_session(loot, inventory, _inventory_ui, picks)


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


func _on_encounter_request_post_combat_rewards(encounter: EncounterData) -> void:
	_ensure_reward_screen()
	var encounter_kind := "NORMAL"
	if encounter != null:
		if bool(encounter.payload.get("force_elite_rewards", false)):
			encounter_kind = "ELITE"
		else:
			match encounter.type:
				EncounterData.EncounterType.COMBAT_ELITE:
					encounter_kind = "ELITE"
				EncounterData.EncounterType.COMBAT_BOSS:
					encounter_kind = "BOSS"
				_:
					encounter_kind = "NORMAL"
	var act_depth := 1
	if _run_flow != null:
		act_depth = maxi(_run_flow.current_act_index, 1)
		if _run_flow.current_map_data != null:
			var cur := _run_flow.current_map_data.get_node(_run_flow.current_map_data.current_node_id)
			if cur != null:
				act_depth = maxi(cur.layer, 0)
	var loot := RewardManager.generate_rewards(encounter_kind, act_depth)
	if encounter_kind == "ELITE":
		loot = RewardManager.ensure_at_least_one_rare(loot)
	if GameManager != null:
		var chips_gained: int = GameManager.award_combat_chips(encounter_kind, act_depth)
		if chips_gained > 0:
			EventBus.combat_log_message.emit(tr("KEY_LOG_CHIPS_GAINED") % chips_gained)
	## Stay in the combat window: loot fills the enemy stage, Body Grid stays docked.
	_combat_ui.visible = true
	if not _inventory_combat_docked:
		_mount_inventory_combat_dock()
	_hide_inventory_overlay()
	if _inventory_ui.has_method("set_combat_mode"):
		_inventory_ui.set_combat_mode(false)
	if _combat_ui.has_method("set_reward_phase"):
		_combat_ui.set_reward_phase(true)
	_post_combat_reward_active = true
	_reward_screen.open_session(loot, inventory, _inventory_ui)
	_status_banner.text = tr("KEY_REWARD_SELECT_UP_TO_3")


func _ensure_reward_screen() -> void:
	var host: Control = null
	if _combat_ui != null and _combat_ui.has_method("get_loot_stage"):
		host = _combat_ui.get_loot_stage()
	if host == null:
		host = _combat_ui
	if _reward_screen != null and is_instance_valid(_reward_screen):
		if _reward_screen.get_parent() != host and host != null:
			_reward_screen.reparent(host)
			_reward_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	_reward_screen = REWARD_SCREEN_SCENE.instantiate() as RewardScreen
	_reward_screen.name = "RewardScreen"
	if host != null:
		host.add_child(_reward_screen)
	else:
		add_child(_reward_screen)
	_reward_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reward_screen.finished.connect(_on_reward_screen_finished)
	_reward_screen.notice_requested.connect(_on_reward_notice)


func _on_reward_notice(message: String) -> void:
	if not message.is_empty():
		_status_banner.text = message


func _on_reward_screen_finished() -> void:
	if _dialog_loot_active:
		_dialog_loot_active = false
		if _combat_ui != null and _combat_ui.has_method("set_reward_phase"):
			_combat_ui.set_reward_phase(false)
		_encounters.complete_dialog_loot()
		## Encounter already finished (loot ended the event) — stay on map.
		if _encounters.active_encounter == null:
			return
		if (
			_dialog_event_ui != null
			and is_instance_valid(_dialog_event_ui)
			and _dialog_event_ui.has_active_event()
		):
			_show_exploring()
			_dialog_event_ui.visible = true
			_layout_dialog_event_under_top_bar()
		return
	if _chest_loot_active or _chest_site_active:
		_finish_chest_site(true)
		return
	_post_combat_reward_active = false
	_encounter_combat_active = false
	if _combat_ui != null and _combat_ui.has_method("set_reward_phase"):
		_combat_ui.set_reward_phase(false)
	_encounters.complete_post_combat_rewards()


func _ensure_dialog_event_ui() -> void:
	if _dialog_event_ui != null and is_instance_valid(_dialog_event_ui):
		return
	_dialog_event_ui = DIALOG_EVENT_SCENE.instantiate() as DialogEventUI
	_dialog_event_ui.name = "DialogEventUI"
	add_child(_dialog_event_ui)
	if not resized.is_connected(_on_main_resized_for_dialog):
		resized.connect(_on_main_resized_for_dialog)


func _ensure_rest_site_ui() -> void:
	if _rest_site_ui != null and is_instance_valid(_rest_site_ui):
		return
	_rest_site_ui = REST_SITE_SCENE.instantiate() as RestSiteUI
	_rest_site_ui.name = "RestSiteUI"
	add_child(_rest_site_ui)
	_rest_site_ui.continue_pressed.connect(_on_rest_site_continue)
	if not resized.is_connected(_on_main_resized_for_dialog):
		resized.connect(_on_main_resized_for_dialog)


func _ensure_shop_screen() -> void:
	## Host inside CombatUI LootStage — same left-side Space as post-combat rewards.
	var host: Control = null
	if _combat_ui != null and _combat_ui.has_method("get_loot_stage"):
		host = _combat_ui.get_loot_stage()
	if host == null:
		host = _combat_ui
	if _shop_screen != null and is_instance_valid(_shop_screen):
		if _shop_screen.get_parent() != host and host != null:
			_shop_screen.reparent(host)
			_shop_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	_shop_screen = SHOP_SCREEN_SCENE.instantiate() as ShopScreen
	_shop_screen.name = "ShopScreen"
	if host != null:
		host.add_child(_shop_screen)
	else:
		add_child(_shop_screen)
	_shop_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shop_screen.finished.connect(_on_shop_screen_finished)
	_shop_screen.notice_requested.connect(_on_reward_notice)


func _layout_dialog_event_under_top_bar() -> void:
	if _dialog_event_ui == null or not is_instance_valid(_dialog_event_ui):
		return
	## Leave the shared TopBar (HP + actions) exposed above the event module.
	var pad := 0.0
	if _root_layout:
		pad = float(_root_layout.get_theme_constant("separation"))
	_dialog_event_ui.layout_below_top_bar(_gameplay_hud, pad)


func _layout_rest_site_under_top_bar() -> void:
	if _rest_site_ui == null or not is_instance_valid(_rest_site_ui):
		return
	var pad := 0.0
	if _root_layout:
		pad = float(_root_layout.get_theme_constant("separation"))
	_rest_site_ui.layout_below_top_bar(_gameplay_hud, pad)


func _on_rest_site_continue() -> void:
	if _inventory_ui:
		_inventory_ui.refresh()
	_encounters.complete_rest_site()


func _on_shop_screen_finished() -> void:
	_shop_active = false
	if _combat_ui != null and _combat_ui.has_method("set_reward_phase"):
		_combat_ui.set_reward_phase(false)
	if _inventory_ui:
		if _inventory_ui.has_method("set_reward_handler"):
			_inventory_ui.set_reward_handler(null)
		_inventory_ui.refresh()
	_encounters.complete_shop_site()


func _on_main_resized_for_dialog() -> void:
	if _dialog_event_ui != null and _dialog_event_ui.visible:
		_layout_dialog_event_under_top_bar()
	if _rest_site_ui != null and _rest_site_ui.visible:
		_layout_rest_site_under_top_bar()


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
	if _forced_insertion_active:
		## Keep drag enabled while the parasite must be placed.
		if _inventory_ui.has_method("set_combat_mode"):
			_inventory_ui.set_combat_mode(false)
		_inventory_ui.refresh()
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
		## Let the final enemy finish fading before the loot stage swaps in.
		if _combat_ui != null and _combat_ui.has_method("await_pending_death_fades"):
			await _combat_ui.await_pending_death_fades()
		if _encounter_combat_active:
			_encounters.notify_combat_finished(true)
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
	if _forced_insertion_active and _forced_item_screen != null and _forced_item_screen.is_active():
		_forced_item_screen.confirm_and_finish()
		return
	## Shop: same Continue as post-combat rewards.
	if _shop_active and _shop_screen != null and _shop_screen.is_active():
		_shop_screen.confirm_and_finish()
		return
	## Chest site: leave without opening, or finish after single-pick loot.
	if _chest_site_active:
		if _chest_loot_active and _reward_screen != null and _reward_screen.is_active():
			_reward_screen.confirm_and_finish()
			return
		_finish_chest_site(false)
		return
	## Dialog event loot (crematorium / collector house).
	if _dialog_loot_active and _reward_screen != null and _reward_screen.is_active():
		_reward_screen.confirm_and_finish()
		return
	## Reward phase: the same Continue discards leftover Space loot and returns to map.
	if _post_combat_reward_active and _reward_screen != null and _reward_screen.is_active():
		_reward_screen.confirm_and_finish()
		return
	if _combat.state == _combat.CombatState.VICTORY:
		if _encounter_combat_active:
			_encounter_combat_active = false
			_encounters.notify_combat_finished(true)
	elif _combat.state == _combat.CombatState.DEFEAT:
		if _encounter_combat_active:
			_encounter_combat_active = false
			_encounters.notify_combat_finished(false)
		_show_exploring()
		_status_banner.text = tr("KEY_STATUS_WRECKAGE")


func _on_forced_insertion_requested(item_id: String) -> void:
	var instance: ItemData = null
	if _combat != null and _combat.has_method("take_pending_forced_item"):
		instance = _combat.take_pending_forced_item() as ItemData
	if instance == null and ItemDatabase != null:
		instance = ItemDatabase.create_instance(item_id)
	if instance == null:
		push_warning("Main: forced insertion missing item '%s'" % item_id)
		if _combat.has_method("complete_forced_item_insertion"):
			_combat.complete_forced_item_insertion()
		return
	## Harmful parasites keep drop/use constraints; returned stolen loot does not.
	if instance.is_harmful:
		instance.enforce_harmful_constraints()
	_ensure_forced_item_screen()
	if _inventory_ui.has_method("set_combat_mode"):
		_inventory_ui.set_combat_mode(false)
	if _combat_ui.has_method("set_harmful_insertion_phase"):
		var banner := (
			tr("KEY_FORCED_INSERT_BANNER")
			if instance.is_harmful
			else tr("KEY_FORCED_INSERT_RETURN")
		)
		_combat_ui.set_harmful_insertion_phase(true, banner)
	_forced_insertion_active = true
	_forced_item_screen.open_session(instance, inventory, _inventory_ui)


func _ensure_forced_item_screen() -> void:
	var host: Control = null
	if _combat_ui != null and _combat_ui.has_method("get_loot_stage"):
		host = _combat_ui.get_loot_stage()
	if _forced_item_screen != null and is_instance_valid(_forced_item_screen):
		if _forced_item_screen.get_parent() != host and host != null:
			_forced_item_screen.reparent(host)
			_forced_item_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	_forced_item_screen = FORCED_ITEM_SCREEN_SCENE.instantiate() as ForcedItemScreen
	_forced_item_screen.name = "ForcedItemScreen"
	if host != null:
		host.add_child(_forced_item_screen)
	else:
		add_child(_forced_item_screen)
	_forced_item_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_forced_item_screen.finished.connect(_on_forced_insertion_finished)
	_forced_item_screen.notice_requested.connect(_on_reward_notice)
	_forced_item_screen.continue_availability_changed.connect(_on_forced_continue_availability)


func _on_forced_continue_availability(can_continue: bool) -> void:
	if _combat_ui != null and _combat_ui.has_method("set_continue_enabled"):
		_combat_ui.set_continue_enabled(can_continue)


func _on_forced_insertion_finished() -> void:
	_forced_insertion_active = false
	if _combat_ui != null and _combat_ui.has_method("set_harmful_insertion_phase"):
		_combat_ui.set_harmful_insertion_phase(false)
	if _inventory_ui != null and _inventory_ui.has_method("set_combat_mode"):
		## Stay in non-click mode until player turn resumes; enemy turn still active.
		_inventory_ui.set_combat_mode(false)
	if _inventory_ui != null:
		_inventory_ui.refresh()
	if _combat != null and _combat.has_method("complete_forced_item_insertion"):
		_combat.complete_forced_item_insertion()
