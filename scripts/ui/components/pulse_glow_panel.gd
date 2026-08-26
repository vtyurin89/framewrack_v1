class_name PulseGlowPanel
extends PanelContainer
## CRT phosphor border glow drawn behind a combat action button.

var _style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 0
	_build_style()
	set_glow_strength(0.0)
	visible = false


func set_glow_strength(strength: float) -> void:
	if _style == null:
		_build_style()
	var t := clampf(strength, 0.0, 1.0)
	_style.shadow_size = int(lerpf(2.0, 12.0, t))
	_style.shadow_color = Color(
		GamePalette.PHOSPHOR_ACTIVE.r,
		GamePalette.PHOSPHOR_ACTIVE.g,
		GamePalette.PHOSPHOR_ACTIVE.b,
		lerpf(0.0, 0.32, t)
	)
	_style.border_color = Color(0, 0, 0, 0)
	_style.bg_color = Color(
		GamePalette.PHOSPHOR_ACTIVE.r,
		GamePalette.PHOSPHOR_ACTIVE.g,
		GamePalette.PHOSPHOR_ACTIVE.b,
		lerpf(0.0, 0.06, t)
	)
	add_theme_stylebox_override("panel", _style)
	visible = t > 0.02


func _build_style() -> void:
	_style = StyleBoxFlat.new()
	_style.set_border_width_all(0)
	_style.set_corner_radius_all(0)
	_style.shadow_offset = Vector2.ZERO
	set_glow_strength(0.0)
