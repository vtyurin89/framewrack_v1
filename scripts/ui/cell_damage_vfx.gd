class_name CellDamageVfx
extends Control
## Red crosshair laser + CRT flash for CellDamage strikes on the body grid.

const LASER_COLOR := Color(0.92, 0.12, 0.12, 0.92)
const FLASH_COLOR := Color(1.0, 0.15, 0.15, 1.0)
const LINE_WIDTH := 3.0
const FLASH_DURATION := 0.28
const FADE_DURATION := 0.45

var _target_cell := Vector2i(-1, -1)
var _grid_size := Vector2i.ZERO
var _cell_size := 48.0
var _cell_gap := 4.0
var _flash_strength := 0.0
var _line_alpha := 0.0
var _tween: Tween


func configure(grid_size: Vector2i, cell_size: float, cell_gap: float) -> void:
	_grid_size = grid_size
	_cell_size = cell_size
	_cell_gap = cell_gap
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	z_as_relative = false
	var w := grid_size.x * cell_size + maxi(grid_size.x - 1, 0) * cell_gap
	var h := grid_size.y * cell_size + maxi(grid_size.y - 1, 0) * cell_gap
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)
	visible = false
	set_process(false)


func play_at(cell: Vector2i) -> void:
	if _grid_size == Vector2i.ZERO:
		return
	_target_cell = cell
	visible = true
	set_process(true)
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_flash_strength = 1.0
	_line_alpha = 1.0
	queue_redraw()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_method(_set_flash_strength, 1.0, 0.0, FLASH_DURATION).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_line_alpha, 1.0, 0.0, FADE_DURATION).set_delay(0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_callback(_finish)


func _set_flash_strength(value: float) -> void:
	_flash_strength = value
	queue_redraw()


func _set_line_alpha(value: float) -> void:
	_line_alpha = value
	queue_redraw()


func _finish() -> void:
	visible = false
	set_process(false)
	_target_cell = Vector2i(-1, -1)
	_flash_strength = 0.0
	_line_alpha = 0.0
	queue_redraw()


func _process(_delta: float) -> void:
	## Keep redrawing while animating in case tween steps are sparse.
	if _line_alpha > 0.01 or _flash_strength > 0.01:
		queue_redraw()


func _draw() -> void:
	if _target_cell.x < 0 or _line_alpha <= 0.01:
		return
	var stride := _cell_size + _cell_gap
	var center := Vector2(
		_target_cell.x * stride + _cell_size * 0.5,
		_target_cell.y * stride + _cell_size * 0.5
	)
	var laser := LASER_COLOR
	laser.a *= _line_alpha
	draw_line(Vector2(0.0, center.y), Vector2(size.x, center.y), laser, LINE_WIDTH, true)
	draw_line(Vector2(center.x, 0.0), Vector2(center.x, size.y), laser, LINE_WIDTH, true)
	if _flash_strength > 0.01:
		var flash := FLASH_COLOR
		flash.a *= _flash_strength
		var half := _cell_size * 0.55
		draw_rect(Rect2(center - Vector2(half, half), Vector2(half * 2.0, half * 2.0)), flash, true)
