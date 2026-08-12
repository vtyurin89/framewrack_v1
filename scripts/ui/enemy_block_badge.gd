class_name EnemyBlockBadge
extends Control
## Blue hexagon armor / Block badge that sits on the left edge of an enemy HP bar.

const BADGE_SIZE := Vector2(30, 30)
const FILL_COLOR := Color("#2E86C1")
const BORDER_COLOR := Color("#85C1E9")
const TEXT_COLOR := Color(0.95, 0.97, 1.0)

var _label: Label
var _amount: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = BADGE_SIZE
	size = BADGE_SIZE
	z_index = 5
	_ensure_label()
	set_block(0)


func set_block(amount: int) -> void:
	_amount = maxi(0, amount)
	_ensure_label()
	visible = _amount > 0
	_label.text = str(_amount)
	queue_redraw()


func _ensure_label() -> void:
	if _label != null and is_instance_valid(_label):
		return
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.add_theme_color_override("font_outline_color", Color(0.05, 0.12, 0.22, 0.9))
	_label.add_theme_constant_override("outline_size", 3)
	add_child(_label)


func _draw() -> void:
	if _amount <= 0:
		return
	var pts := _hex_points(size * 0.5, mini(size.x, size.y) * 0.48)
	draw_colored_polygon(pts, FILL_COLOR)
	pts.append(pts[0])
	draw_polyline(pts, BORDER_COLOR, 2.0, true)


func _hex_points(center: Vector2, radius: float) -> PackedVector2Array:
	## Pointy-top hexagon.
	var pts: PackedVector2Array = []
	for i in 6:
		var angle := deg_to_rad(-90.0 + float(i) * 60.0)
		pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return pts
