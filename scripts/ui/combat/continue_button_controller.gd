class_name ContinueButtonController
extends Button

## Pulses outer CRT glow during victory rewards (Continue) or 0 AP player turns (End Turn).

enum CombatPhase {
	INACTIVE = 0,
	PLAYER_TURN = 1,
	ENEMY_TURN = 2,
	VICTORY = 3,
	DEFEAT = 4,
	VICTORY_REWARDS = 5,
}

@export var pulse_glow_component: PulseGlowComponent
@export var pulse_on_rewards: bool = true
@export var pulse_on_zero_ap: bool = false

var _combat_manager: Node
var _connected: bool = false


func _ready() -> void:
	z_index = 1
	_resolve_pulse_component()
	call_deferred("_bind_signals")


func _resolve_pulse_component() -> void:
	if pulse_glow_component != null:
		return
	pulse_glow_component = get_node_or_null("PulseGlowComponent") as PulseGlowComponent
	if pulse_glow_component == null and get_parent() != null:
		pulse_glow_component = get_parent().get_node_or_null("PulseGlowComponent") as PulseGlowComponent


func _bind_signals() -> void:
	if _connected:
		return
	_resolve_pulse_component()
	_combat_manager = _resolve_combat_manager()
	if _combat_manager != null:
		if _combat_manager.has_signal("phase_changed"):
			_combat_manager.phase_changed.connect(_eval_pulse_conditions)
		if _combat_manager.has_signal("state_changed"):
			_combat_manager.state_changed.connect(_eval_pulse_conditions)
		if _combat_manager.has_signal("player_ap_changed"):
			_combat_manager.player_ap_changed.connect(_eval_pulse_conditions)
	if not EventBus.ap_changed.is_connected(_eval_pulse_conditions):
		EventBus.ap_changed.connect(_eval_pulse_conditions)
	if not EventBus.turn_started.is_connected(_on_turn_started):
		EventBus.turn_started.connect(_on_turn_started)
	if not EventBus.combat_started.is_connected(_eval_pulse_conditions):
		EventBus.combat_started.connect(_eval_pulse_conditions)
	_connected = true
	call_deferred("_eval_pulse_conditions")


func _on_turn_started(is_player: bool) -> void:
	if is_player:
		call_deferred("_eval_pulse_conditions")


func _resolve_combat_manager() -> Node:
	var grouped := get_tree().get_first_node_in_group("combat_manager")
	if grouped != null:
		return grouped
	var main := get_tree().root.get_node_or_null("Main")
	if main != null:
		return main.get_node_or_null("CombatManager")
	return null


func _eval_pulse_conditions(_args: Variant = null) -> void:
	_resolve_pulse_component()
	if pulse_glow_component == null:
		return
	if _combat_manager == null:
		_combat_manager = _resolve_combat_manager()

	var is_rewards_phase := _is_rewards_phase()
	var is_player_turn := _is_player_turn()
	var is_zero_ap := _read_current_ap() <= 0

	var should_pulse := false
	if pulse_on_rewards and is_rewards_phase:
		should_pulse = true
	if pulse_on_zero_ap and is_player_turn and is_zero_ap:
		should_pulse = true

	var slot := get_parent() as CanvasItem
	if slot != null and not slot.is_visible_in_tree():
		should_pulse = false
	elif not is_visible_in_tree():
		should_pulse = false

	pulse_glow_component.is_pulsing = should_pulse


func _is_rewards_phase() -> bool:
	if _combat_manager == null:
		return false
	if bool(_combat_manager.get("_victory_rewards_active")):
		return true
	return int(_combat_manager.get("current_phase")) == CombatPhase.VICTORY_REWARDS


func _is_player_turn() -> bool:
	if _combat_manager == null:
		return false
	if _combat_manager.has_method("is_player_turn_active"):
		return bool(_combat_manager.call("is_player_turn_active"))
	return int(_combat_manager.get("state")) == CombatPhase.PLAYER_TURN


func _read_current_ap() -> int:
	if _combat_manager != null:
		return int(_combat_manager.get("current_ap"))
	return 0
