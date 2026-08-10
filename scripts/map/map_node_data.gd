class_name MapNodeData
extends Resource

enum MapNodeType {
	INTRO,
	MAIN_STORY,
	COMBAT,
	EVENT,
	REPAIR,
	SHOP,
	ELITE,
	BOSS,
	STAIRS,
	REWARD,
}

enum NodeState {
	LOCKED,
	AVAILABLE,
	VISITED,
}

@export var id: String = ""
@export var layer: int = 0
@export var grid_x: int = 0
@export var position: Vector2 = Vector2.ZERO
@export var node_type: MapNodeType = MapNodeType.COMBAT
@export var next_nodes: Array[String] = []
@export var state: NodeState = NodeState.LOCKED
@export var encounter_data: EncounterData
