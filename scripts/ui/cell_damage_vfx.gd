class_name CellDamageVfx
extends Control
## Red crosshair laser + CRT flash for CellDamage, plus one-shot grenade blast pulse.

const LASER_COLOR := Color(0.92, 0.12, 0.12, 0.92)
const FLASH_COLOR := Color(1.0, 0.15, 0.15, 1.0)
const BLAST_CORE := Color(1.0, 0.18, 0.08, 1.0)
const BLAST_GLOW := Color(1.0, 0.05, 0.02, 1.0)
const LINE_WIDTH := 3.0
const FLASH_DURATION := 0.28
const FADE_DURATION := 0.45
## One bright expanding pulse covering the epicenter + neighbors.
const BLAST_DURATION := 0.42

var _target_cell := Vector2i(-1, -1)
var _blast_cell := Vector2i(-1, -1)
var _grid_size := Vector2i.ZERO
var _cell_size := 48.0
var _cell_gap := 4.0
var _flash_strength := 0.0
var _line_alpha := 0.0
var _blast_strength := 0.0
var _blast_radius := 0.0
var _laser_tween: Tween
var _blast_tween: Tween


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
	## Never kill an in-flight laser / blast when the grid relayouts.
	if not _is_playing():
		visible = false
		set_process(false)


func play_at(cell: Vector2i) -> void:
	if _grid_size == Vector2i.ZERO:
		return
	_target_cell = cell
	visible = true
	set_process(true)
	if _laser_tween != null and is_instance_valid(_laser_tween):
		_laser_tween.kill()
	_flash_strength = 1.0
	_line_alpha = 1.0
	queue_redraw()
	_laser_tween = create_tween()
	_laser_tween.set_parallel(true)
	_laser_tween.tween_method(_set_flash_strength, 1.0, 0.0, FLASH_DURATION).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_laser_tween.tween_method(_set_line_alpha, 1.0, 0.0, FADE_DURATION).set_delay(0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_laser_tween.chain().tween_callback(_finish_laser)


func play_blast_at(cell: Vector2i) -> void:
	## Single red pulse (PulseGlow-like) covering the cell and its neighbors.
	if _grid_size == Vector2i.ZERO:
		return
	_blast_cell = cell
	visible = true
	set_process(true)
	if _blast_tween != null and is_instance_valid(_blast_tween):
		_blast_tween.kill()
	_blast_strength = 0.0
	_blast_radius = 0.35
	queue_redraw()
	_blast_tween = create_tween()
	_blast_tween.set_parallel(true)
	## Peak bright and large, then collapse — one explosion beat.
	_blast_tween.tween_method(_set_blast_strength, 0.0, 0.72, BLAST_DURATION * 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_blast_tween.tween_method(_set_blast_radius, 0.35, 1.7, BLAST_DURATION * 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_blast_tween.chain()
	_blast_tween.set_parallel(false)
	_blast_tween.tween_method(_set_blast_strength, 0.72, 0.0, BLAST_DURATION * 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_blast_tween.tween_callback(_finish_blast)


func _is_playing() -> bool:
	return _line_alpha > 0.01 or _flash_strength > 0.01 or _blast_strength > 0.01


func _set_flash_strength(value: float) -> void:
	_flash_strength = value
	queue_redraw()


func _set_line_alpha(value: float) -> void:
	_line_alpha = value
	queue_redraw()


func _set_blast_strength(value: float) -> void:
	_blast_strength = value
	queue_redraw()


func _set_blast_radius(value: float) -> void:
	_blast_radius = value
	queue_redraw()


func _finish_laser() -> void:
	_target_cell = Vector2i(-1, -1)
	_flash_strength = 0.0
	_line_alpha = 0.0
	if not _is_playing():
		visible = false
		set_process(false)
	queue_redraw()


func _finish_blast() -> void:
	_blast_cell = Vector2i(-1, -1)
	_blast_strength = 0.0
	_blast_radius = 0.0
	if not _is_playing():
		visible = false
		set_process(false)
	queue_redraw()


func _process(_delta: float) -> void:
	if _is_playing():
		queue_redraw()


func _draw() -> void:
	_draw_laser()
	_draw_blast()


func _draw_laser() -> void:
	if _target_cell.x < 0 or _line_alpha <= 0.01:
		return
	var center := _cell_center(_target_cell)
	var laser := LASER_COLOR
	laser.a *= _line_alpha
	draw_line(Vector2(0.0, center.y), Vector2(size.x, center.y), laser, LINE_WIDTH, true)
	draw_line(Vector2(center.x, 0.0), Vector2(center.x, size.y), laser, LINE_WIDTH, true)
	if _flash_strength > 0.01:
		var flash := FLASH_COLOR
		flash.a *= _flash_strength
		var half := _cell_size * 0.55
		draw_rect(Rect2(center - Vector2(half, half), Vector2(half * 2.0, half * 2.0)), flash, true)


func _draw_blast() -> void:
	if _blast_cell.x < 0 or _blast_strength <= 0.01:
		return
	var center := _cell_center(_blast_cell)
	var stride := _cell_size + _cell_gap
	var radius := stride * _blast_radius
	## Soft outer glow (neighbors), muted core on the bomb cell.
	var glow := BLAST_GLOW
	glow.a = 0.32 * _blast_strength
	draw_circle(center, radius, glow)
	var mid := BLAST_CORE
	mid.a = 0.42 * _blast_strength
	draw_circle(center, radius * 0.62, mid)
	var core := Color(1.0, 0.45, 0.18, 0.55 * _blast_strength)
	draw_circle(center, maxf(_cell_size * 0.35, radius * 0.28), core)
	## Rectangular CRT plate flash over the 3x3 footprint.
	var plate_half := stride * 1.15 * _blast_radius
	var plate := Color(1.0, 0.12, 0.08, 0.12 * _blast_strength)
	draw_rect(
		Rect2(center - Vector2(plate_half, plate_half), Vector2(plate_half * 2.0, plate_half * 2.0)),
		plate,
		true
	)


func _cell_center(cell: Vector2i) -> Vector2:
	var stride := _cell_size + _cell_gap
	return Vector2(
		cell.x * stride + _cell_size * 0.5,
		cell.y * stride + _cell_size * 0.5
	)
