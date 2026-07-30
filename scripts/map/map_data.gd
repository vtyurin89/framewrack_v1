class_name MapData
extends Resource

@export var nodes: Dictionary = {}
@export var current_node_id: String = ""


func get_node(node_id: String) -> MapNodeData:
	if not nodes.has(node_id):
		return null
	return nodes[node_id] as MapNodeData


func get_all_nodes() -> Array[MapNodeData]:
	var result: Array[MapNodeData] = []
	for value in nodes.values():
		if value is MapNodeData:
			result.append(value as MapNodeData)
	result.sort_custom(
		func(a: MapNodeData, b: MapNodeData) -> bool:
			if a.layer == b.layer:
				return a.grid_x < b.grid_x
			return a.layer < b.layer
	)
	return result


func get_available_nodes() -> Array[MapNodeData]:
	var available: Array[MapNodeData] = []
	for node: MapNodeData in get_all_nodes():
		if node.state == MapNodeData.NodeState.AVAILABLE:
			available.append(node)
	return available


func mark_visited(node_id: String) -> void:
	var node := get_node(node_id)
	if node == null:
		return
	node.state = MapNodeData.NodeState.VISITED
	current_node_id = node_id
	## Forward-only: lock any other AVAILABLE options that were not taken.
	for other: MapNodeData in get_all_nodes():
		if other.id == node_id:
			continue
		if other.state == MapNodeData.NodeState.AVAILABLE:
			other.state = MapNodeData.NodeState.LOCKED
	for next_id in node.next_nodes:
		var next_node := get_node(next_id)
		if next_node == null:
			continue
		if next_node.state != MapNodeData.NodeState.VISITED:
			next_node.state = MapNodeData.NodeState.AVAILABLE


func get_connections() -> Array[Dictionary]:
	var connections: Array[Dictionary] = []
	for node: MapNodeData in get_all_nodes():
		for next_id in node.next_nodes:
			if nodes.has(next_id):
				connections.append(
					{
						"from": node.id,
						"to": next_id,
					}
				)
	return connections
