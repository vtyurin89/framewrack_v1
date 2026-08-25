class_name TargetReticle
extends Control
## Shared CRT corner reticle that follows the selected enemy card in canvas space.

const COLOR := Color("#A8F0A8") ## PHOSPHOR_BRIGHT
const THICKNESS := 1.25
const ARM := 12.0
const PAD := 3.0
const MOVE_DURATION := 0.18
const PULSE_DURATION := 0.16

var _move_tween: Tween
var _pulse_tween: Tween
var _has_target: bool = false
var _locked_card: EnemyCardUI = null
var _follow_pos: Vector2 = Vector2.ZERO
var _follow_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 40
	## Ignore parent layout / offset — we place in viewport canvas space.
	top_level = true
	modulate.a = 0.0
	visible = true
	set_process(false)


func clear_target(animate: bool = true) -> void:
	_has_target = false
	_locked_card = null
	_kill_move()
	set_process(false)
	if not animate:
		modulate.a = 0.0
		queue_redraw()
		return
	_kill_pulse()
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "modulate:a", 0.0, 0.12)
	_pulse_tween.tween_callback(queue_redraw)


func lock_on(card: Control) -> void:
	if card == null or not is_instance_valid(card) or not card.is_inside_tree():
		clear_target(false)
		return
	_locked_card = card as EnemyCardUI
	_has_target = true
	set_process(true)

	var target_pos := _card_canvas_pos(card)
	var target_size := _card_canvas_size(card)
	_follow_pos = target_pos
	_follow_size = target_size

	_kill_move()
	if modulate.a < 0.05:
		global_position = target_pos
		size = target_size
		modulate.a = 1.0
		queue_redraw()
		_play_lock_pulse()
		return

	_move_tween = create_tween()
	_move_tween.set_parallel(true)
	_move_tween.set_trans(Tween.TRANS_CUBIC)
	_move_tween.set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(self, "global_position", target_pos, MOVE_DURATION)
	_move_tween.tween_property(self, "size", target_size, MOVE_DURATION)
	_move_tween.tween_method(func(_v: float) -> void: queue_redraw(), 0.0, 1.0, MOVE_DURATION)
	_move_tween.chain().tween_callback(_play_lock_pulse)
	queue_redraw()


func _process(_delta: float) -> void:
	if not _has_target or _locked_card == null or not is_instance_valid(_locked_card):
		clear_target(false)
		return
	if _locked_card.is_dying() or not _locked_card.is_visible_in_tree():
		clear_target(false)
		return
	## Keep glued to the card (layout / dock changes won't leave a ghost frame).
	var target_pos := _card_canvas_pos(_locked_card)
	var target_size := _card_canvas_size(_locked_card)
	_follow_pos = target_pos
	_follow_size = target_size
	## Don't fight an in-flight move tween — snap once it finishes.
	if _move_tween != null and _move_tween.is_valid():
		return
	if global_position.distance_to(target_pos) > 0.5 or size.distance_to(target_size) > 0.5:
		global_position = target_pos
		size = target_size
		queue_redraw()


func _card_canvas_pos(card: Control) -> Vector2:
	return card.get_global_transform_with_canvas().origin - Vector2(PAD, PAD)


func _card_canvas_size(card: Control) -> Vector2:
	return card.get_global_rect().size + Vector2(PAD, PAD) * 2.0


func _play_lock_pulse() -> void:
	if not _has_target:
		return
	_kill_pulse()
	## Alpha-only ping — scaling skews corner placement around the card.
	modulate.a = 1.0
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "modulate:a", 0.72, PULSE_DURATION * 0.4)
	_pulse_tween.tween_property(self, "modulate:a", 1.0, PULSE_DURATION * 0.6)


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
	var arm := mini(ARM, mini(w, h) * 0.22)
	var t := THICKNESS
	draw_line(Vector2(0, 0), Vector2(arm, 0), COLOR, t, false)
	draw_line(Vector2(0, 0), Vector2(0, arm), COLOR, t, false)
	draw_line(Vector2(w - arm, 0), Vector2(w, 0), COLOR, t, false)
	draw_line(Vector2(w, 0), Vector2(w, arm), COLOR, t, false)
	draw_line(Vector2(0, h - arm), Vector2(0, h), COLOR, t, false)
	draw_line(Vector2(0, h), Vector2(arm, h), COLOR, t, false)
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
