class_name RewardSpaceArea
extends Control
## Drop target for inventory ↔ floating loot transfers during reward phase.

var reward_screen: RewardScreen


func setup(screen: RewardScreen) -> void:
	reward_screen = screen
	mouse_filter = Control.MOUSE_FILTER_STOP


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if reward_screen == null:
		return false
	return reward_screen._can_drop_data(at_position, data)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if reward_screen == null:
		return
	reward_screen._drop_data(at_position, data)
