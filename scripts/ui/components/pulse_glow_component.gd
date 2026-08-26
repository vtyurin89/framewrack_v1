class_name PulseGlowComponent
extends Node

## Drives outer CRT glow on a PulseGlowPanel placed behind an action button.

@export var glow_panel: Control
@export var min_glow_strength: float = 0.08
@export var max_glow_strength: float = 0.65
@export var pulse_duration: float = 0.7  ## Half-cycle duration (seconds).

var _is_pulsing: bool = false
var _tween: Tween

var is_pulsing: bool:
	get:
		return _is_pulsing
	set(value):
		set_pulsing(value)


func _ready() -> void:
	if glow_panel == null and get_parent() is Control:
		var slot := get_parent() as Control
		glow_panel = slot.get_node_or_null("GlowPanel") as Control
	if glow_panel != null:
		glow_panel.visible = false
		_set_glow_strength(0.0)


func set_pulsing(value: bool) -> void:
	if _is_pulsing == value:
		return
	_is_pulsing = value

	if _is_pulsing:
		_start_pulse()
	else:
		_stop_pulse()


func _start_pulse() -> void:
	if glow_panel == null:
		return
	_kill_tween()
	if glow_panel:
		glow_panel.visible = true

	_set_glow_strength(min_glow_strength)
	_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_set_glow_strength, min_glow_strength, max_glow_strength, pulse_duration)
	_tween.tween_method(_set_glow_strength, max_glow_strength, min_glow_strength, pulse_duration)


func _stop_pulse() -> void:
	_kill_tween()
	if glow_panel == null:
		return
	var reset_tween := create_tween()
	reset_tween.tween_method(_set_glow_strength, _read_glow_strength(), 0.0, 0.25)
	reset_tween.tween_callback(func() -> void:
		if glow_panel:
			glow_panel.visible = false
	)


func _set_glow_strength(strength: float) -> void:
	if glow_panel == null:
		return
	if glow_panel.has_method("set_glow_strength"):
		glow_panel.call("set_glow_strength", strength)
	else:
		var col := glow_panel.modulate
		col.a = strength
		glow_panel.modulate = col


func _read_glow_strength() -> float:
	if glow_panel != null and glow_panel.has_method("set_glow_strength"):
		return max_glow_strength
	return glow_panel.modulate.a if glow_panel != null else 0.0


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
