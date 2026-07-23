class_name StashDropArea
extends PanelContainer
## Drop target that returns a dragged module to the ungrafted stash.

signal item_returned(data: Variant)

var grid_ui: Node


func setup(p_grid_ui: Node) -> void:
	grid_ui = p_grid_ui
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 1)
	style.set_border_width_all(1)
	style.border_color = Color(0.35, 0.35, 0.4)
	style.set_content_margin_all(6)
	style.set_corner_radius_all(2)
	add_theme_stylebox_override("panel", style)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if grid_ui and grid_ui.has_method("can_drop_on_stash"):
		return grid_ui.can_drop_on_stash(data)
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if grid_ui and grid_ui.has_method("drop_on_stash"):
		grid_ui.drop_on_stash(data)
	item_returned.emit(data)
