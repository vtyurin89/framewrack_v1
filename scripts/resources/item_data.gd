class_name ItemData
extends Resource
## Blueprint for an equippable body-module / weapon / utility.
## Instances are placed onto the player's body grid at runtime.

@export var id: String = ""
@export var display_name: String = "Unknown Module"
@export_multiline var description: String = ""

## Footprint in grid cells (width x height). Rotation not in MVP.
@export var size: Vector2i = Vector2i(1, 1)

## If true, at least one occupied cell must touch the grid's outer border.
@export var requires_edge: bool = false

## Combat activation cost (0 = passive / always-on).
@export var ap_cost: int = 0

@export var damage: int = 0
@export var block_amount: int = 0

## Flat bonus to the player's max AP while this item is functional.
@export var max_ap_bonus: int = 0

## Damage added to ADJACENT weapon items when they activate.
@export var adjacency_damage_bonus: int = 0

## Extra AP granted to the player while this item is adjacent to a weapon
## that is being activated (MVP: treated as max_ap style via reactor).
@export var adjacency_ap_bonus: int = 0

## Placeholder tint for ColorRect / sprite placeholders.
@export var placeholder_color: Color = Color(0.7, 0.7, 0.7)


func is_weapon() -> bool:
	return damage > 0 and ap_cost > 0


func is_shield() -> bool:
	return block_amount > 0 and ap_cost > 0


func footprint_cells(origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			cells.append(origin + Vector2i(x, y))
	return cells
