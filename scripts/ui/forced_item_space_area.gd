class_name ForcedItemSpaceArea
extends Control
## Drop target for Body Grid ↔ Space during harmful insertion.


var forced_screen: ForcedItemScreen


func setup(screen: ForcedItemScreen) -> void:
	forced_screen = screen
	mouse_filter = Control.MOUSE_FILTER_STOP


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if forced_screen == null:
		return false
	return forced_screen._can_drop_data(at_position, data)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if forced_screen == null:
		return
	forced_screen._drop_data(at_position, data)
