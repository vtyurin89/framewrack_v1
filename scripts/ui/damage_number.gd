class_name DamageNumber
extends Control
## Slay-the-Spire-style floating damage: high arc above the card, then fall below it.

const RISE_DURATION := 0.42
const FALL_DURATION := 0.88
const PEAK_SCALE_CRIT := 1.5
const PEAK_SCALE_BONK := 1.85
const PEAK_SCALE_NORMAL := 1.25
## How far above the card top the number peaks.
const ABOVE_CARD := 40.0
## How far below the card bottom it lands before vanishing.
const BELOW_CARD := 56.0
## Max horizontal drift across the whole arc (applied smoothly).
const DRIFT_MAX := 36.0

@onready var _label: Label = %DamageLabel

var _amount: int = 0
var _damage_type: String = "physical"
var _is_crit: bool = false
var _is_miss: bool = false
var _target_rect: Rect2 = Rect2()


func setup(
	amount: int,
	damage_type: String = "physical",
	is_crit: bool = false,
	is_miss: bool = false,
	target_rect: Rect2 = Rect2()
) -> void:
	_amount = amount
	_damage_type = damage_type
	_is_crit = is_crit
	_is_miss = is_miss
	_target_rect = target_rect
	if not is_node_ready():
		await ready
	_apply_presentation()
	_play_arc()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	z_index = 100
	custom_minimum_size = Vector2(80, 32)
	size = Vector2(80, 32)
	if _label:
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _apply_presentation() -> void:
	if _label == null:
		_label = get_node_or_null("%DamageLabel") as Label
	if _label == null:
		return
	var color := Color.WHITE
	if GamePalette:
		color = GamePalette.get_damage_color(_damage_type, _is_crit, _is_miss)
	_label.add_theme_color_override("font_color", color)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)

	if _is_miss:
		_label.text = "MISS"
		_label.add_theme_font_size_override("font_size", 18)
		if GamePalette:
			GamePalette.apply_font_header(_label)
	elif _damage_type in ["poison", "burn", "rust", "heal", "healing", "repair"]:
		var glyph := ""
		if GamePalette:
			glyph = GamePalette.get_status_glyph(_damage_type)
		_label.text = ("%s %d" % [glyph, _amount]).strip_edges()
		_label.add_theme_font_size_override("font_size", 18)
		if GamePalette:
			GamePalette.apply_font_header(_label)
	elif _damage_type == "bonk":
		_label.text = "BONK! %d" % _amount
		_label.add_theme_font_size_override("font_size", 30)
		if GamePalette:
			GamePalette.apply_font_emphasis(_label)
	elif _is_crit:
		_label.text = "%d!" % _amount
		_label.add_theme_font_size_override("font_size", 26)
		if GamePalette:
			GamePalette.apply_font_emphasis(_label)
	else:
		_label.text = str(_amount)
		_label.add_theme_font_size_override("font_size", 22)
		if GamePalette:
			GamePalette.apply_font_header(_label)


func _play_arc() -> void:
	## One continuous arc: chest → high above head → below card.
	## Horizontal drift is tiny and monotonic so it never "jumps" sideways.
	if size.x < 1.0 or size.y < 1.0:
		size = Vector2(80, 32)

	var rect := _target_rect
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		var gp := global_position
		rect = Rect2(gp.x - 90.0, gp.y - 150.0, 180.0, 300.0)

	var half := size * 0.5
	var mid_x := rect.get_center().x
	## Start around the upper torso / portrait area (not dead center).
	var start_y := rect.position.y + rect.size.y * 0.42
	var peak_y := rect.position.y - ABOVE_CARD
	var land_y := rect.end.y + BELOW_CARD

	var drift := randf_range(DRIFT_MAX * 0.45, DRIFT_MAX) * (1.0 if randf() > 0.5 else -1.0)
	## Peak uses ~40% of total drift; land uses 100% — smooth continuation, no reverse jump.
	var start := Vector2(mid_x, start_y) - half
	var peak := Vector2(mid_x + drift * 0.4, peak_y) - half
	var land := Vector2(mid_x + drift, land_y) - half
	var peak_scale := PEAK_SCALE_NORMAL
	if _damage_type == "bonk":
		peak_scale = PEAK_SCALE_BONK
	elif _is_crit:
		peak_scale = PEAK_SCALE_CRIT

	global_position = start
	modulate.a = 1.0
	scale = Vector2.ONE
	pivot_offset = half
	visible = true

	## Godot 4: tween() then parallel() — avoids set_parallel/chain glitches.
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	## Rise
	tween.tween_property(self, "global_position", peak, RISE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	tween.parallel().tween_property(self, "scale", Vector2(peak_scale, peak_scale), RISE_DURATION).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)

	## Fall (continues after rise completes)
	tween.tween_property(self, "global_position", land, FALL_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_IN
	)
	tween.parallel().tween_property(self, "scale", Vector2(0.92, 0.92), FALL_DURATION).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "modulate:a", 0.0, FALL_DURATION).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN
	)

	await tween.finished
	queue_free()
