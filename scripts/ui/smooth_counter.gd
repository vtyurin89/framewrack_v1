class_name SmoothCounter
extends Label
## Label that punches in scale while smoothly interpolating an integer value.

@export var scale_up_factor: Vector2 = Vector2(1.35, 1.35)
@export var punch_in_duration: float = 0.18
@export var count_duration: float = 0.45
@export var punch_out_duration: float = 0.18
@export var show_plus_sign: bool = true
@export var wrap_in_parentheses: bool = true
@export var hide_when_zero: bool = false
@export var positive_color: Color = Color(0.88, 0.88, 0.92, 1)
@export var negative_color: Color = Color(0.92, 0.28, 0.28, 1)
@export var use_value_colors: bool = true

var current_displayed_value: int = 0
var active_tween: Tween
var _pending_target: int = 0


func _ready() -> void:
	## Ensure scale transforms occur around the visual center of the label.
	pivot_offset = size * 0.5
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	_update_label_text(current_displayed_value)


func _on_resized() -> void:
	pivot_offset = size * 0.5


func set_value_instant(target_value: int) -> void:
	if active_tween != null and active_tween.is_valid():
		active_tween.kill()
	active_tween = null
	scale = Vector2.ONE
	current_displayed_value = target_value
	_pending_target = target_value
	_update_label_text(target_value)


func set_value_animated(target_value: int) -> void:
	if target_value == current_displayed_value and visible == (target_value != 0 or not hide_when_zero):
		_update_label_text(target_value)
		return

	if active_tween != null and active_tween.is_valid():
		active_tween.kill()
	active_tween = null

	_pending_target = target_value
	## Show a sized placeholder immediately so the punch is visible inside containers.
	visible = true
	scale = Vector2.ONE
	if current_displayed_value == 0 and hide_when_zero:
		text = _format_value(0)
		if use_value_colors:
			add_theme_color_override(
				"font_color",
				positive_color if target_value >= 0 else negative_color
			)
	else:
		_update_label_text(current_displayed_value)

	## Defer one frame so Label size/pivot are valid after text assignment.
	call_deferred("_begin_animated_tween", target_value)


func _begin_animated_tween(target_value: int) -> void:
	if target_value != _pending_target:
		return
	if not is_inside_tree():
		set_value_instant(target_value)
		return

	pivot_offset = size * 0.5
	if size.x < 8.0 or size.y < 8.0:
		custom_minimum_size = Vector2(maxf(size.x, 48.0), maxf(size.y, 22.0))
		pivot_offset = custom_minimum_size * 0.5

	if active_tween != null and active_tween.is_valid():
		active_tween.kill()

	var start_value := current_displayed_value
	active_tween = create_tween().set_parallel(false)

	## 1. Scale punch up.
	active_tween.tween_property(self, "scale", scale_up_factor, punch_in_duration).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)

	## 2. Smoothly count numerical step value.
	active_tween.tween_method(
		_on_counter_step,
		float(start_value),
		float(target_value),
		count_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	## 3. Scale back to normal.
	active_tween.tween_property(self, "scale", Vector2.ONE, punch_out_duration).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_IN_OUT)
	active_tween.tween_callback(_on_animation_finished)


func _on_animation_finished() -> void:
	custom_minimum_size = Vector2.ZERO
	_update_label_text(current_displayed_value)


func _on_counter_step(value: float) -> void:
	current_displayed_value = int(round(value))
	_update_label_text(current_displayed_value)
	pivot_offset = size * 0.5


func _format_value(val: int) -> String:
	if not wrap_in_parentheses:
		if val > 0 and show_plus_sign:
			return "+%d" % val
		return str(val)
	if val > 0 and show_plus_sign:
		return "(+%d)" % val
	if val < 0:
		return "(%d)" % val
	return "(0)"


func _update_label_text(val: int) -> void:
	if hide_when_zero and val == 0:
		text = ""
		visible = false
		scale = Vector2.ONE
		custom_minimum_size = Vector2.ZERO
		return

	visible = true
	text = _format_value(val)

	if use_value_colors:
		var color := negative_color if val < 0 else positive_color
		add_theme_color_override("font_color", color)
