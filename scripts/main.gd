extends Control
## Root controller for Framewrack MVP.
## Inventory-first roguelike (Backpack Hero–like): body grid is the core loop,
## with node-map progression and turn-based combat driven by equipped modules.

const ENEMY_REBEL := preload("res://resources/enemies/desperate_rebel.tres")
const ENEMY_SYNTHET := preload("res://resources/enemies/corrupted_synthet.tres")
const STARTING_ITEM_ID := "SCRAP_PIPE"
const EVENT_LOOT_ITEM_ID := "REBEL_CLEAVER"

@onready var _map_ui: Control = %MapUI
@onready var _inventory_ui: Control = %InventoryUI
@onready var _combat_ui: Control = %CombatUI
@onready var _status_banner: Label = %StatusBanner
@onready var _inventory_panel: PanelContainer = %InventoryPanel
@onready var _btn_toggle_inv: Button = %ToggleInventoryButton
@onready var _btn_expand: Button = %ExpandGridButton
@onready var _btn_new_run: Button = %NewRunButton
@onready var _btn_lang: Button = %LanguageButton

var inventory: InventoryController
var flow_state: int = GameFlowState.State.EXPLORING

@onready var _combat: Node = $CombatManager
@onready var _map: Node = $MapManager


func _ready() -> void:
	inventory = InventoryController.new()
	_combat.setup(inventory)
	_seed_starting_loadout()
	_style_inventory_panel()

	_map_ui.setup(_map)
	_inventory_ui.setup(inventory)
	_combat_ui.setup(_combat, inventory)

	_map.node_entered.connect(_on_map_node_entered)
	_map.map_finished.connect(_on_map_finished)
	_map_ui.node_chosen.connect(_on_node_chosen)
	_combat_ui.end_turn_pressed.connect(_on_end_turn)
	_combat_ui.activate_item_requested.connect(_on_activate_item)
	_combat_ui.target_selected.connect(_on_target)
	_combat_ui.continue_pressed.connect(_on_combat_continue)
	_combat.state_changed.connect(_on_combat_state)
	EventBus.combat_ended.connect(_on_combat_ended_bus)

	_btn_toggle_inv.pressed.connect(_toggle_inventory)
	_btn_expand.pressed.connect(_expand_grid_demo)
	_btn_new_run.pressed.connect(_new_run)
	_btn_lang.pressed.connect(_on_language_pressed)
	LocalizationManager.language_changed.connect(_on_language_changed)

	_apply_static_locale()
	_show_exploring()
	_status_banner.text = tr("KEY_STATUS_ONLINE")


func _on_language_pressed() -> void:
	LocalizationManager.cycle_language()


func _on_language_changed(_locale: String) -> void:
	_apply_static_locale()
	_map_ui.refresh()
	_inventory_ui.refresh()


func _apply_static_locale() -> void:
	_btn_toggle_inv.text = tr("KEY_BODY_GRID")
	_btn_expand.text = tr("KEY_MUTATE_CELLS")
	_btn_new_run.text = tr("KEY_NEW_RUN")
	_btn_lang.text = "%s: %s" % [tr("KEY_LANGUAGE"), LocalizationManager.get_locale().to_upper()]


func _style_inventory_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.14, 0.14, 1)
	style.set_border_width_all(1)
	style.border_color = Color(0.35, 0.35, 0.35)
	style.set_content_margin_all(10)
	_inventory_panel.add_theme_stylebox_override("panel", style)


func _seed_starting_loadout() -> void:
	inventory.reset_run()
	## Starter kit comes only from ItemDatabase / items.csv.
	var scrap_pipe: ItemData = ItemDatabase.create_instance(STARTING_ITEM_ID)
	if scrap_pipe != null:
		inventory.place_item(scrap_pipe, Vector2i(0, 0))


func _set_flow(state: int) -> void:
	flow_state = state
	EventBus.game_state_changed.emit(state)


func _show_exploring() -> void:
	_set_flow(GameFlowState.State.EXPLORING)
	_map_ui.visible = true
	_combat_ui.visible = false
	_inventory_panel.visible = true
	_map_ui.refresh()
	_inventory_ui.refresh()


func _show_combat() -> void:
	_map_ui.visible = false
	_combat_ui.visible = true
	_inventory_panel.visible = true  # body grid stays visible during fight


func _toggle_inventory() -> void:
	_inventory_panel.visible = not _inventory_panel.visible


func _expand_grid_demo() -> void:
	## Mutation hook: unlock an irregular L-extension of flesh/bone cells.
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
			# Graft CSV loot directly onto the body if space remains.
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
	for eid in enemy_ids:
		match str(eid):
			"desperate_rebel":
				datas.append(ENEMY_REBEL.duplicate(true) as EnemyData)
			"corrupted_synthet":
				datas.append(ENEMY_SYNTHET.duplicate(true) as EnemyData)
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


func _on_activate_item(placed: PlacedItem) -> void:
	_combat.activate_item(placed)
	_inventory_ui.refresh()


func _on_target(index: int) -> void:
	_combat.set_target(index)


func _on_combat_state(_s: int) -> void:
	_inventory_ui.refresh()


func _on_combat_ended_bus(victory: bool) -> void:
	if victory:
		_status_banner.text = tr("KEY_STATUS_COMBAT_WIN")
	else:
		_status_banner.text = tr("KEY_STATUS_COMBAT_LOSE")


func _on_combat_continue() -> void:
	if _combat.state == _combat.CombatState.VICTORY:
		_map.complete_current()
		_show_exploring()
		_status_banner.text = tr("KEY_STATUS_SECTOR_SECURED")
	elif _combat.state == _combat.CombatState.DEFEAT:
		_show_exploring()
		_status_banner.text = tr("KEY_STATUS_WRECKAGE")


func _on_map_finished() -> void:
	_status_banner.text = tr("KEY_STATUS_RUN_COMPLETE")
	_set_flow(GameFlowState.State.VICTORY)


func _new_run() -> void:
	_map.reset()
	_seed_starting_loadout()
	_inventory_ui.setup(inventory)
	_combat.setup(inventory)
	_show_exploring()
	_status_banner.text = tr("KEY_STATUS_NEW_RUN")
	EventBus.run_started.emit()
