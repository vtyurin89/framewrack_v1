class_name CrtOverlay
extends CanvasLayer
## Full-screen CRT scanline + vignette. Keeps glow off the global pass.

const SHADER_PATH := "res://shaders/crt_overlay.gdshader"

var _rect: ColorRect


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_rect()


func _ensure_rect() -> void:
	if _rect != null and is_instance_valid(_rect):
		return
	_rect = ColorRect.new()
	_rect.name = "CrtRect"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	## Transparent fallback if the shader fails to compile/load.
	_rect.color = Color(0, 0, 0, 0)

	var shader := load(SHADER_PATH) as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		_rect.material = mat
		## Shader drives RGB+A; base color just needs to be opaque for sampling.
		_rect.color = Color(1, 1, 1, 1)
	else:
		push_warning("CrtOverlay: failed to load shader at %s" % SHADER_PATH)

	add_child(_rect)


func set_enabled(enabled: bool) -> void:
	_ensure_rect()
	visible = enabled
