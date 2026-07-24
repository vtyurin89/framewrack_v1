class_name MapManager
extends Node
## Simple branching node map: Combat → Event/Repair → Combat → Boss.

enum NodeType {
	COMBAT,
	REPAIR,
	EVENT,
	BOSS,
}

signal node_entered(node_id: String, node_type: NodeType)
signal map_finished

var nodes: Array[Dictionary] = []
var current_index: int = -1
var completed: Dictionary = {}  # node_id → true


func _ready() -> void:
	_build_default_map()


func _build_default_map() -> void:
	nodes = [
		{"id": "n0", "type": NodeType.COMBAT, "label_key": "MAP_N0_NAME", "label": "Scrap Corridor", "enemy_ids": ["desperate_rebel"]},
		{"id": "n1", "type": NodeType.REPAIR, "label_key": "MAP_N1_NAME", "label": "Jury-Rig Bench", "enemy_ids": []},
		{"id": "n2", "type": NodeType.COMBAT, "label_key": "MAP_N2_NAME", "label": "Synth Nest", "enemy_ids": ["corrupted_synthet"]},
		{"id": "n3", "type": NodeType.EVENT, "label_key": "MAP_N3_NAME", "label": "Mutation Cache", "enemy_ids": []},
		{
			"id": "n4",
			"type": NodeType.BOSS,
			"label_key": "MAP_N4_NAME",
			"label": "Framewrack Core",
			"enemy_ids": ["desperate_rebel", "corrupted_synthet"],
		},
	]
	current_index = -1
	completed.clear()


func reset() -> void:
	_build_default_map()


func get_available_nodes() -> Array[Dictionary]:
	## Linear MVP: only the next uncompleted node is available.
	var result: Array[Dictionary] = []
	var next := current_index + 1
	if next < nodes.size():
		result.append(nodes[next])
	return result


func get_all_nodes() -> Array[Dictionary]:
	return nodes.duplicate(true)


func select_node(node_id: String) -> bool:
	for i in nodes.size():
		var n: Dictionary = nodes[i]
		if n["id"] != node_id:
			continue
		# Must be the next sequential node.
		if i != current_index + 1:
			return false
		current_index = i
		EventBus.map_node_selected.emit(node_id)
		node_entered.emit(node_id, n["type"] as NodeType)
		return true
	return false


func complete_current() -> void:
	if current_index < 0 or current_index >= nodes.size():
		return
	var n: Dictionary = nodes[current_index]
	completed[n["id"]] = true
	EventBus.map_node_completed.emit(n["id"])
	if current_index >= nodes.size() - 1:
		map_finished.emit()


func get_current() -> Dictionary:
	if current_index < 0 or current_index >= nodes.size():
		return {}
	return nodes[current_index]
