extends Node
## Global high-level game state machine for Framewrack.
## Scenes / UI listen to state_changed and perform local transitions.

enum GameState {
	MAIN_MENU,
	STARTUP_SETUP,
	GAMEPLAY,
	GAME_OVER,
}

signal state_changed(previous_state: GameState, new_state: GameState)
signal restart_requested
signal return_to_main_menu_requested
signal start_game_requested
signal continue_requested
signal settings_requested

## True while a run exists that can be Continued from the main menu.
var is_session_active: bool = false
## True when the main menu is open over an active session (soft pause).
var is_paused: bool = false

var state: GameState = GameState.MAIN_MENU


func get_state() -> GameState:
	return state


func is_gameplay() -> bool:
	return state == GameState.GAMEPLAY


func is_game_over() -> bool:
	return state == GameState.GAME_OVER


func change_state(new_state: GameState) -> void:
	if state == new_state:
		return
	var previous: GameState = state
	state = new_state
	state_changed.emit(previous, new_state)
	EventBus.game_state_changed.emit(int(new_state))


func begin_session() -> void:
	is_session_active = true
	is_paused = false


func end_session() -> void:
	is_session_active = false
	is_paused = false


func request_new_game() -> void:
	## Fresh run from main menu (or mid-run New Game).
	begin_session()
	start_game_requested.emit()
	change_state(GameState.STARTUP_SETUP)
	change_state(GameState.GAMEPLAY)


func request_start_game() -> void:
	## Alias used by older call sites.
	request_new_game()


func request_continue() -> void:
	if not is_session_active:
		return
	is_paused = false
	continue_requested.emit()
	change_state(GameState.GAMEPLAY)


func request_restart() -> void:
	## GAME_OVER → new run (session stays / becomes active).
	begin_session()
	restart_requested.emit()
	change_state(GameState.STARTUP_SETUP)
	change_state(GameState.GAMEPLAY)


func request_pause_to_menu() -> void:
	## Soft pause: keep session so Continue works.
	if state != GameState.GAMEPLAY:
		return
	if not is_session_active:
		return
	is_paused = true
	change_state(GameState.MAIN_MENU)


func request_main_menu() -> void:
	## Hard return: ends the run session.
	end_session()
	return_to_main_menu_requested.emit()
	change_state(GameState.MAIN_MENU)


func request_open_settings() -> void:
	settings_requested.emit()


func trigger_game_over() -> void:
	if state == GameState.GAME_OVER:
		return
	end_session()
	change_state(GameState.GAME_OVER)
