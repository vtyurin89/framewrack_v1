class_name PlacedItem
extends RefCounted
## Runtime instance of an ItemData sitting on the body grid.

var data: ItemData
var origin: Vector2i = Vector2i.ZERO
## Unique instance id so multiple copies of the same blueprint can coexist.
var instance_id: String = ""


func _init(p_data: ItemData = null, p_origin: Vector2i = Vector2i.ZERO) -> void:
	data = p_data
	origin = p_origin
	if p_data:
		instance_id = "%s_%d_%d" % [p_data.id, p_origin.x, p_origin.y]


func occupied_cells() -> Array[Vector2i]:
	return data.footprint_cells(origin)
