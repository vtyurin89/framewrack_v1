class_name ShopSpaceArea
extends Control
## Drop target for shop stock Space (purchase flow mirrors RewardSpaceArea).

var shop_screen: ShopScreen


func setup(screen: ShopScreen) -> void:
	shop_screen = screen
	mouse_filter = Control.MOUSE_FILTER_STOP


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if shop_screen == null:
		return false
	return shop_screen._can_drop_data(at_position, data)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if shop_screen == null:
		return
	shop_screen._drop_data(at_position, data)
