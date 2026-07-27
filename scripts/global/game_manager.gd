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


func request_start_game() -> void:
	## MAIN_MENU → STARTUP_SETUP → GAMEPLAY (handled by Main).
	start_game_requested.emit()
	change_state(GameState.STARTUP_SETUP)
	change_state(GameState.GAMEPLAY)


func request_restart() -> void:
	## GAME_OVER → STARTUP_SETUP → GAMEPLAY.
	restart_requested.emit()
	change_state(GameState.STARTUP_SETUP)
	change_state(GameState.GAMEPLAY)


func request_main_menu() -> void:
	return_to_main_menu_requested.emit()
	change_state(GameState.MAIN_MENU)


func trigger_game_over() -> void:
	if state == GameState.GAME_OVER:
		return
	change_state(GameState.GAME_OVER)
