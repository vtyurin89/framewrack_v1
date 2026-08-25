class_name TargetReticle
extends Control
## Shared CRT corner reticle that tweens between enemy cards.

const COLOR := Color("#A8F0A8") ## PHOSPHOR_BRIGHT
const THICKNESS := 1.25
const ARM := 12.0
const PAD := 3.0
const MOVE_DURATION := 0.22
const PULSE_DURATION := 0.18

var _move_tween: Tween
var _pulse_tween: Tween
var _has_target: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 40
	modulate.a = 0.0
	visible = true


func clear_target(animate: bool = true) -> void:
	_has_target = false
	_kill_move()
	if not animate:
		modulate.a = 0.0
		return
	_kill_pulse()
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "modulate:a", 0.0, 0.12)


func lock_on(card: Control) -> void:
	if card == null or not is_instance_valid(card):
		clear_target()
		return
	var host := get_parent() as Control
	if host == null:
		return

	var card_rect := card.get_global_rect()
	var host_rect := host.get_global_rect()
	var target_pos := card_rect.position - host_rect.position - Vector2(PAD, PAD)
	var target_size := card_rect.size + Vector2(PAD, PAD) * 2.0

	_kill_move()
	_has_target = true
	if modulate.a < 0.05:
		## First lock — snap then pulse.
		position = target_pos
		size = target_size
		modulate.a = 1.0
		queue_redraw()
		_play_lock_pulse()
		return

	_move_tween = create_tween()
	_move_tween.set_parallel(true)
	_move_tween.set_trans(Tween.TRANS_CUBIC)
	_move_tween.set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(self, "position", target_pos, MOVE_DURATION)
	_move_tween.tween_property(self, "size", target_size, MOVE_DURATION)
	_move_tween.tween_method(func(_v: float) -> void: queue_redraw(), 0.0, 1.0, MOVE_DURATION)
	_move_tween.chain().tween_callback(_play_lock_pulse)
	queue_redraw()


func _play_lock_pulse() -> void:
	if not _has_target:
		return
	_kill_pulse()
	modulate.a = 1.0
	scale = Vector2.ONE
	pivot_offset = size * 0.5
	_pulse_tween = create_tween()
	_pulse_tween.set_trans(Tween.TRANS_SINE)
	_pulse_tween.set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(self, "scale", Vector2(1.04, 1.04), PULSE_DURATION * 0.45)
	_pulse_tween.tween_property(self, "scale", Vector2.ONE, PULSE_DURATION * 0.55)
	## Soft alpha ping.
	_pulse_tween.parallel().tween_property(self, "modulate:a", 0.7, PULSE_DURATION * 0.35)
	_pulse_tween.tween_property(self, "modulate:a", 1.0, PULSE_DURATION * 0.65)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if not _has_target or modulate.a <= 0.01:
		return
	var w := size.x
	var h := size.y
	if w <= 2.0 or h <= 2.0:
		return
	var arm := mini(ARM, mini(w, h) * 0.28)
	var t := THICKNESS
	## Top-left
	draw_line(Vector2(0, 0), Vector2(arm, 0), COLOR, t, false)
	draw_line(Vector2(0, 0), Vector2(0, arm), COLOR, t, false)
	## Top-right
	draw_line(Vector2(w - arm, 0), Vector2(w, 0), COLOR, t, false)
	draw_line(Vector2(w, 0), Vector2(w, arm), COLOR, t, false)
	## Bottom-left
	draw_line(Vector2(0, h - arm), Vector2(0, h), COLOR, t, false)
	draw_line(Vector2(0, h), Vector2(arm, h), COLOR, t, false)
	## Bottom-right
	draw_line(Vector2(w - arm, h), Vector2(w, h), COLOR, t, false)
	draw_line(Vector2(w, h - arm), Vector2(w, h), COLOR, t, false)


func _kill_move() -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = null


func _kill_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	scale = Vector2.ONE
