class_name GhostProgressBar
extends Control
## StS-style dual HP bar: instant red main + delayed yellow ghost drain.

const GHOST_HOLD := 0.2
const GHOST_TWEEN_DURATION := 0.45

@export var bar_min_size: Vector2 = Vector2(170, 20)
@export var show_label: bool = true

var _ghost: ProgressBar
var _main: ProgressBar
var _label: Label
var _ghost_tween: Tween
var _hold_timer: SceneTreeTimer
var _current: float = 0.0
var _maximum: float = 1.0
var _built: bool = false


func _ready() -> void:
	_ensure_built()
	_apply_styles()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = bar_min_size
	clip_contents = true

	_ghost = ProgressBar.new()
	_ghost.name = "GhostBar"
	_ghost.show_percentage = false
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_ghost)
	move_child(_ghost, 0)

	_main = ProgressBar.new()
	_main.name = "MainBar"
	_main.show_percentage = false
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_main)

	if show_label:
		_label = Label.new()
		_label.name = "HPLabel"
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 13)
		_label.add_theme_color_override("font_color", Color.WHITE)
		_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_label)


func _apply_styles() -> void:
	_ensure_built()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#121212")
	bg.set_corner_radius_all(2)
	bg.set_content_margin_all(0)

	var ghost_fill := StyleBoxFlat.new()
	ghost_fill.bg_color = GamePalette.COLOR_HP_GHOST if GamePalette else Color("#F39C12")
	ghost_fill.set_corner_radius_all(2)
	ghost_fill.set_content_margin_all(0)

	var main_fill := StyleBoxFlat.new()
	main_fill.bg_color = GamePalette.COLOR_HP_MAIN if GamePalette else Color("#E74C3C")
	main_fill.set_corner_radius_all(2)
	main_fill.set_content_margin_all(0)

	## Ghost uses opaque bg; main uses transparent bg so ghost shows through.
	var main_bg := StyleBoxFlat.new()
	main_bg.bg_color = Color(0, 0, 0, 0)
	main_bg.set_corner_radius_all(2)
	main_bg.set_content_margin_all(0)

	_ghost.add_theme_stylebox_override("background", bg)
	_ghost.add_theme_stylebox_override("fill", ghost_fill)
	_main.add_theme_stylebox_override("background", main_bg)
	_main.add_theme_stylebox_override("fill", main_fill)


func set_hp(current_hp: int, max_hp: int, animate: bool = true) -> void:
	_ensure_built()
	var maximum := float(maxi(max_hp, 1))
	var current := float(clampi(current_hp, 0, int(maximum)))
	var previous_main := _main.value if _main.max_value > 0.0 else current

	_maximum = maximum
	_current = current
	_main.max_value = maximum
	_ghost.max_value = maximum
	_main.value = current
	if _label:
		_label.text = "%d/%d" % [int(current), int(maximum)]

	if not animate or current >= previous_main:
		## Heal / init — snap ghost up with main.
		_kill_ghost_tween()
		_ghost.value = current
		return

	## Damage: keep ghost high briefly, then ease down to main.
	if _ghost.value < previous_main:
		_ghost.value = previous_main
	_schedule_ghost_drain()


func snap_hp(current_hp: int, max_hp: int) -> void:
	set_hp(current_hp, max_hp, false)


func get_current() -> int:
	return int(_current)


func get_maximum() -> int:
	return int(_maximum)


func _schedule_ghost_drain() -> void:
	_kill_ghost_tween()
	var tree := get_tree()
	if tree == null:
		_ghost.value = _current
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


func _kill_ghost_tween() -> void:
	if _ghost_tween != null and _ghost_tween.is_valid():
		_ghost_tween.kill()
	_ghost_tween = null
