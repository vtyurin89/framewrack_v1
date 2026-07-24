class_name ItemRarityData
extends Resource
## Rarity tier used by adjacency rules and future loot / UI tinting.

@export var id: String = ""
@export var rarity_name_key: String = ""
@export var display_name: String = "Common"
@export var tint: Color = Color(0.75, 0.75, 0.75)
@export var sort_order: int = 0


func get_localized_name() -> String:
	if not rarity_name_key.is_empty():
		return tr(rarity_name_key)
	return display_name
