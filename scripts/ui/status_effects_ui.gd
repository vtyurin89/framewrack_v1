class_name StatusEffectsUI
extends HBoxContainer
## Horizontal strip of active status icons with stack/duration and hover tooltips.

const ICON_MIN_SIZE := Vector2(28, 28)

var _controller: StatusController
var _bound: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_STOP


func bind_controller(controller: StatusController) -> void:
	if _controller != null and _controller.statuses_updated.is_connected(_on_statuses_updated):
		_controller.statuses_updated.disconnect(_on_statuses_updated)
	_controller = controller
	_bound = false
	if _controller != null:
		_controller.statuses_updated.connect(_on_statuses_updated)
		_bound = true
		_rebuild(_controller.get_active_statuses())
	else:
		_clear()


func unbind() -> void:
	bind_controller(null)


func _on_statuses_updated(active_statuses: Array) -> void:
	var typed: Array[StatusInstance] = []
	for entry in active_statuses:
		if entry is StatusInstance:
			typed.append(entry as StatusInstance)
	_rebuild(typed)


func _clear() -> void:
	for child in get_children():
		child.queue_free()


func _rebuild(statuses: Array[StatusInstance]) -> void:
	_clear()
	for status: StatusInstance in statuses:
		if status == null or status.data == null or status.is_expired():
			continue
		add_child(_make_icon(status))


func _make_icon(status: StatusInstance) -> Control:
	var wrap := UITooltipHost.new()
	wrap.custom_minimum_size = ICON_MIN_SIZE
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	## Non-empty tooltip_text is required for Godot to request a custom tip.
	wrap.tooltip_text = UITooltip.format_status_title(status)
	wrap.tip_factory = func() -> Control:
		return UITooltip.create_from_status(status)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.92)
	style.set_border_width_all(1)
	style.border_color = (
		Color(0.75, 0.35, 0.35) if status.data.is_debuff else Color(0.35, 0.7, 0.45)
	)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(2)
	wrap.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(row)

	if status.data.icon != null:
		var tex := TextureRect.new()
		tex.texture = status.data.icon
		tex.custom_minimum_size = Vector2(18, 18)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tex)
	else:
		var glyph := Label.new()
		glyph.text = status.data.get_ui_glyph()
		glyph.add_theme_font_size_override("font_size", 14)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(glyph)

	var count := Label.new()
	if status.is_permanent():
		count.text = "∞"
	else:
		count.text = str(status.get_display_count())
	count.add_theme_font_size_override("font_size", 12)
	count.add_theme_color_override("font_color", Color(0.92, 0.92, 0.94))
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(count)
	return wrap
