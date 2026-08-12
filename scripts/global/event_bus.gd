extends Node
## Global signal hub for Framewrack.
## Keeps UI, combat, inventory, and map loosely coupled.

# --- Game flow ---------------------------------------------------------------
signal game_state_changed(new_state: int)
signal run_started
signal run_ended(victory: bool)

# --- Map / exploration -------------------------------------------------------
signal map_node_selected(node_id: String)
signal map_node_completed(node_id: String)
signal repair_station_used

# --- Inventory / body grid ---------------------------------------------------
signal inventory_changed
signal item_placed(item_id: String, origin: Vector2i)
signal item_removed(item_id: String)
signal cell_corrupted(cell: Vector2i, duration: int)
signal cell_corruption_cleared(cell: Vector2i)
signal grid_expanded(new_cells: Array[Vector2i])
signal placement_failed(reason: String)
signal grid_layout_updated

# --- Combat ------------------------------------------------------------------
signal combat_started(enemy_ids: Array[String])
signal combat_ended(victory: bool)
signal turn_started(is_player: bool)
signal ap_changed(current: int, maximum: int)
## Fired when the player tries to act without enough AP (HUD shake / flash).
signal ap_insufficient
signal player_hp_changed(current: int, maximum: int)
signal enemy_hp_changed(enemy_index: int, current: int, maximum: int)
## Fired when an enemy's Block / armor amount changes (shield gain or absorb).
signal enemy_block_changed(enemy_index: int, amount: int)
## Fired when an enemy receives healing (UI heal flash / float text).
signal enemy_healed(enemy_index: int, amount: int)
signal enemy_selected(enemy_index: int)
## Fired when enemies are added/removed mid-fight (e.g. summon).
signal enemy_roster_changed
signal combat_log_message(text: String)
## Floating notice over an enemy panel (ability name / crit / etc.).
signal enemy_combat_text(enemy_index: int, text: String, kind: String)
## Fired when an enemy's telegraphed intention is planned or reactively updated.
signal enemy_intention_changed(enemy_index: int, intention: RefCounted)
## Fired when an enemy reaches 0 HP (UI fades the card; manager may purge afterward).
signal enemy_died(enemy_index: int)
signal block_changed(amount: int)
signal combat_item_availability_changed
signal player_died
## Floating damage / miss / status popup request (CombatUI resolves target nodes).
## target_kind: "enemy" | "player"
signal damage_popup_requested(
	target_kind: String,
	enemy_index: int,
	amount: int,
	damage_type: String,
	is_crit: bool,
	is_miss: bool
)
