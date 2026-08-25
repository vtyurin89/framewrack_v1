class_name GhostProgressBar
extends Control
## Dual HP bar: phosphor fill + delayed ghost drain, drawn as CRT block segments.

const GHOST_HOLD := 0.2
const GHOST_TWEEN_DURATION := 0.45
const MAIN_TWEEN_DURATION := 0.4
const SEGMENT_GAP := 1.0
const MIN_SEGMENTS := 8
const MAX_SEGMENTS := 28

@export var bar_min_size: Vector2 = Vector2(170, 20)
@export var show_label: bool = true

var _ghost: ProgressBar
var _main: ProgressBar
var _label: Label
var _ghost_tween: Tween
var _main_tween: Tween
var _hold_timer: SceneTreeTimer
var _current: float = 0.0
var _maximum: float = 1.0
var _built: bool = false


func _ready() -> void:
	_ensure_built()
	_apply_styles()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = bar_min_size
	clip_contents = true

	## ProgressBars store animated values only; visuals are custom-drawn segments.
	_ghost = ProgressBar.new()
	_ghost.name = "GhostBar"
	_ghost.show_percentage = false
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.modulate = Color(1, 1, 1, 0)
	_ghost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_ghost)
	move_child(_ghost, 0)

	_main = ProgressBar.new()
	_main.name = "MainBar"
	_main.show_percentage = false
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main.modulate = Color(1, 1, 1, 0)
	_main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_main)

	if show_label:
		_label = Label.new()
		_label.name = "HPLabel"
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 13)
		_label.add_theme_color_override("font_color", GamePalette.PHOSPHOR_BRIGHT)
		_label.add_theme_color_override("font_outline_color", GamePalette.BACKGROUND_DARK)
		_label.add_theme_constant_override("outline_size", 3)
		_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_label)
	elif _label != null:
		_label.visible = false


func _apply_styles() -> void:
	_ensure_built()
	if _label:
		_label.add_theme_color_override("font_color", GamePalette.PHOSPHOR_BRIGHT)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	## Outer frame.
	draw_rect(rect, GamePalette.BACKGROUND_DARK, true)
	draw_rect(rect, GamePalette.MUTED_GREEN, false, 1.0)

	var inner := rect.grow(-2.0)
	if inner.size.x <= 1.0 or inner.size.y <= 1.0:
		return
	var segments := clampi(int(round(inner.size.x / 7.0)), MIN_SEGMENTS, MAX_SEGMENTS)
	var total_gap := SEGMENT_GAP * float(segments - 1)
	var seg_w := (inner.size.x - total_gap) / float(segments)
	var ratio_ghost := 0.0
	var ratio_main := 0.0
	if _maximum > 0.0:
		ratio_ghost = clampf(_ghost.value / _maximum, 0.0, 1.0) if _ghost else 0.0
		ratio_main = clampf(_main.value / _maximum, 0.0, 1.0) if _main else 0.0
	var filled_ghost := int(ceil(ratio_ghost * float(segments) - 0.001))
	var filled_main := int(ceil(ratio_main * float(segments) - 0.001))

	for i in segments:
		var x := inner.position.x + float(i) * (seg_w + SEGMENT_GAP)
		var seg := Rect2(Vector2(x, inner.position.y), Vector2(seg_w, inner.size.y))
		if i < filled_ghost:
			draw_rect(seg, GamePalette.COLOR_HP_GHOST, true)
		else:
			draw_rect(seg, GamePalette.INACTIVE_ELEMENT, true)
		if i < filled_main:
			draw_rect(seg, GamePalette.COLOR_HP_MAIN, true)


func set_hp_animated(new_hp: int, max_hp: int, duration: float = MAIN_TWEEN_DURATION) -> void:
	set_hp(new_hp, max_hp, true, duration)


func set_hp(
	current_hp: int, max_hp: int, animate: bool = true, duration: float = MAIN_TWEEN_DURATION
) -> void:
	_ensure_built()
	var maximum := float(maxi(max_hp, 1))
	var current := float(clampi(current_hp, 0, int(maximum)))
	var previous_main := _main.value if _main.max_value > 0.0 else current
	var is_heal := current > previous_main + 0.01
	var is_damage := current < previous_main - 0.01

	_maximum = maximum
	_current = current
	_main.max_value = maximum
	_ghost.max_value = maximum
	if _label:
		_label.text = "%d/%d" % [int(current), int(maximum)]

	if not animate:
		_kill_main_tween()
		_kill_ghost_tween()
		_main.value = current
		_ghost.value = current
		queue_redraw()
		return

	_tween_main_to(current, duration)

	if is_heal or not is_damage:
		_kill_ghost_tween()
		if is_heal:
			_ghost_tween = create_tween()
			_ghost_tween.set_trans(Tween.TRANS_SINE)
			_ghost_tween.set_ease(Tween.EASE_OUT)
			_ghost_tween.tween_property(_ghost, "value", current, duration)
			_ghost_tween.tween_callback(queue_redraw)
		else:
			_ghost.value = current
		queue_redraw()
		return

	if _ghost.value < previous_main:
		_ghost.value = previous_main
	_schedule_ghost_drain()
	queue_redraw()


func snap_hp(current_hp: int, max_hp: int) -> void:
	set_hp(current_hp, max_hp, false)


func get_current() -> int:
	return int(_current)


func get_maximum() -> int:
	return int(_maximum)


func _tween_main_to(target: float, duration: float) -> void:
	_kill_main_tween()
	_main_tween = create_tween()
	_main_tween.tween_property(_main, "value", target, maxf(0.01, duration)).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_OUT)
	_main_tween.parallel().tween_method(func(_v: float) -> void: queue_redraw(), 0.0, 1.0, maxf(0.01, duration))


func _schedule_ghost_drain() -> void:
	_kill_ghost_tween()
	var tree := get_tree()
	if tree == null:
		_ghost.value = _current
		queue_redraw()
		return
	_hold_timer = tree.create_timer(GHOST_HOLD)
	_hold_timer.timeout.connect(_tween_ghost_to_main, CONNECT_ONE_SHOT)


func _tween_ghost_to_main() -> void:
	if not is_instance_valid(self) or _ghost == null:
		return
	_kill_ghost_tween()
	_ghost_tween = create_tween()
	_ghost_tween.set_trans(Tween.TRANS_QUAD)
	_ghost_tween.set_ease(Tween.EASE_OUT)
	_ghost_tween.tween_property(_ghost, "value", _current, GHOST_TWEEN_DURATION)
	_ghost_tween.parallel().tween_method(
		func(_v: float) -> void: queue_redraw(), 0.0, 1.0, GHOST_TWEEN_DURATION
	)


func _kill_main_tween() -> void:
	if _main_tween != null and _main_tween.is_valid():
		_main_tween.kill()
	_main_tween = null


func _kill_ghost_tween() -> void:
	if _ghost_tween != null and _ghost_tween.is_valid():
		_ghost_tween.kill()
	_ghost_tween = null
