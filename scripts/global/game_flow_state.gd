class_name GameFlowState
extends RefCounted
## High-level run / scene flow states.

enum State {
	EXPLORING,
	INVENTORY,
	PLAYER_TURN,
	ENEMY_TURN,
	VICTORY,
	GAME_OVER,
}
