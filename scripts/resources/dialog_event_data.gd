class_name DialogEventData
extends Resource
## Branching dialog tree used by EVENT encounters.

@export var id: String = ""
@export var title: String = ""
@export var title_key: String = ""
@export var start_node_id: String = "start"
@export var nodes: Array[DialogNodeData] = []


func get_display_title() -> String:
	if not title_key.is_empty():
		return tr(title_key)
	if not title.is_empty():
		return title
	return id


func get_node(node_id: String) -> DialogNodeData:
	var needle := node_id.strip_edges()
	if needle.is_empty():
		needle = start_node_id
	for node: DialogNodeData in nodes:
		if node != null and node.id == needle:
			return node
	if not nodes.is_empty():
		return nodes[0]
	return null


func get_start_node() -> DialogNodeData:
	return get_node(start_node_id)
