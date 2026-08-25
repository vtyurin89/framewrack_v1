class_name DamageVignette
extends CanvasLayer
## Full-screen red edge flash when the player takes damage.

@export var default_max_alpha: float = 0.4
@export var default_duration: float = 0.3

@onready var vignette_rect: TextureRect = $VignetteRect

var flash_tween: Tween


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_vignette_texture()
	if vignette_rect:
		vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vignette_rect.modulate.a = 0.0


func flash(max_alpha: float = -1.0, duration: float = -1.0) -> void:
	if vignette_rect == null:
		return
	var alpha := default_max_alpha if max_alpha < 0.0 else max_alpha
	var fade_time := default_duration if duration < 0.0 else duration
	if flash_tween != null and flash_tween.is_valid():
		flash_tween.kill()

	## Fast flash in, smooth fade out.
	vignette_rect.modulate.a = clampf(alpha, 0.0, 1.0)
	flash_tween = create_tween()
	flash_tween.tween_property(vignette_rect, "modulate:a", 0.0, maxf(0.01, fade_time)).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_OUT)


func _ensure_vignette_texture() -> void:
	if vignette_rect == null:
		return
	## Always rebuild so editor/runtime tweaks to the falloff apply after reloads.
	## Radial gradient: keep center clear; push redness toward the outer rim only.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.72, 0.88, 1.0])
	gradient.colors = PackedColorArray([
		Color(GamePalette.COLOR_DANGER.r, GamePalette.COLOR_DANGER.g, GamePalette.COLOR_DANGER.b, 0.0),
		Color(GamePalette.COLOR_DANGER.r, GamePalette.COLOR_DANGER.g, GamePalette.COLOR_DANGER.b, 0.0),
		Color(GamePalette.COLOR_DANGER.r, GamePalette.COLOR_DANGER.g, GamePalette.COLOR_DANGER.b, 0.32),
		Color(GamePalette.COLOR_DANGER.r, GamePalette.COLOR_DANGER.g, GamePalette.COLOR_DANGER.b, 0.55),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 512
	tex.height = 512
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	vignette_rect.texture = tex
	vignette_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette_rect.stretch_mode = TextureRect.STRETCH_SCALE
