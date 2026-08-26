class_name PulseComponent
extends Node

@export var target_node: Control
@export var pulse_scale: bool = false
@export var scale_amount: Vector2 = Vector2(1.05, 1.05)
@export var pulse_alpha: bool = true
@export var min_alpha: float = 0.4
@export var max_alpha: float = 1.0
@export var pulse_duration: float = 0.8

var _is_pulsing: bool = false
var _tween: Tween
var _original_scale: Vector2 = Vector2.ONE
var _original_modulate: Color = Color.WHITE

var is_pulsing: bool:
	get:
		return _is_pulsing
	set(value):
		set_pulsing(value)


func _ready() -> void:
	if not target_node and get_parent() is Control:
		target_node = get_parent() as Control

	if target_node:
		_original_scale = target_node.scale
		_original_modulate = target_node.modulate
		target_node.resized.connect(_refresh_pivot)


func set_pulsing(value: bool) -> void:
	if _is_pulsing == value:
		return
	_is_pulsing = value

	if _is_pulsing:
		_start_pulse()
	else:
		_stop_pulse()


func _refresh_pivot() -> void:
	if target_node and pulse_scale:
		target_node.pivot_offset = target_node.size * 0.5


func _start_pulse() -> void:
	if not target_node:
		return
	_kill_tween()
	_original_scale = target_node.scale
	_original_modulate = target_node.modulate

	if pulse_scale:
		target_node.pivot_offset = target_node.size * 0.5

	var half := maxf(0.01, pulse_duration * 0.5)
	_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if pulse_scale:
		_tween.tween_property(target_node, "scale", _original_scale * scale_amount, half)
		_tween.tween_property(target_node, "scale", _original_scale, half)
	elif pulse_alpha:
		var dim := _original_modulate
		dim.a = min_alpha
		var bright := _original_modulate
		bright.a = max_alpha
		_tween.tween_property(target_node, "modulate", dim, half)
		_tween.tween_property(target_node, "modulate", bright, half)
	else:
		_tween.tween_interval(pulse_duration)


func _stop_pulse() -> void:
	_kill_tween()
	if not target_node:
		return
	var reset_tween := create_tween().set_parallel(true)
	reset_tween.tween_property(target_node, "scale", _original_scale, 0.2)
	reset_tween.tween_property(target_node, "modulate", _original_modulate, 0.2)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
