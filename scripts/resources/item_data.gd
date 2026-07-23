class_name ItemData
extends Resource
## Blueprint for an equippable body-module / weapon / utility.
## Instances are placed onto the player's body grid at runtime.

@export var id: String = ""
@export var display_name: String = "Unknown Module"
@export_multiline var description: String = ""
@export var texture: Texture2D

## Footprint in grid cells (width x height). Swapped on rotate (R while dragging).
@export var size: Vector2i = Vector2i(1, 1)

## If true, at least one occupied cell must touch the grid's outer edge.
@export var requires_edge: bool = false

## Combat activation cost (0 = passive / always-on).
@export var ap_cost: int = 0

@export var damage: int = 0
@export var block_amount: int = 0

## Flat bonus to the player's max AP while this item is functional.
@export var max_ap_bonus: int = 0

## Damage added to adjacent weapon items when they activate (e.g. Reactor → Weapon).
@export var adjacency_damage_bonus: int = 0

## Extra max AP while this item is adjacent to any functional weapon.
@export var adjacency_ap_bonus: int = 0

## Placeholder tint when no texture is assigned.
@export var placeholder_color: Color = Color(0.7, 0.7, 0.7)


# --- Spec aliases (item_name / cost_ap / is_edge_only / adjacency_dmg_bonus) --

var item_name: String:
	get:
		return display_name
	set(value):
		display_name = value


var is_edge_only: bool:
	get:
		return requires_edge
	set(value):
		requires_edge = value


var cost_ap: int:
	get:
		return ap_cost
	set(value):
		ap_cost = value


var adjacency_dmg_bonus: int:
	get:
		return adjacency_damage_bonus
	set(value):
		adjacency_damage_bonus = value


func is_weapon() -> bool:
	return damage > 0 and ap_cost > 0


func is_shield() -> bool:
	return block_amount > 0 and ap_cost > 0


func rotate_size() -> void:
	size = Vector2i(size.y, size.x)


func footprint_for(footprint: Vector2i, origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in footprint.y:
		for x in footprint.x:
			cells.append(origin + Vector2i(x, y))
	return cells


func footprint_cells(origin: Vector2i) -> Array[Vector2i]:
	return footprint_for(size, origin)
