class_name RunFlowManager
extends Node

enum RunState {
	RUN_START,
	ACT_INTRO,
	MAP_VIEW,
	ENCOUNTER_ACTIVE,
	REWARD_PHASE,
	ACT_COMPLETE,
	VICTORY,
	GAME_OVER,
}

signal run_state_changed(previous_state: RunState, new_state: RunState)
signal map_changed(map_data: MapData)
signal node_selected(node_data: MapNodeData)
signal focus_layer_requested(layer: int)
signal placeholder_requested(title: String, message: String)

@export var act_definitions: Array[ActData] = []

var current_act: int = 1
var state: RunState = RunState.RUN_START
var current_map_data: MapData
var current_act_data: ActData

var _encounter_manager: EncounterManager
var _pending_node_id: String = ""
var _waiting_placeholder: bool = false


func setup(encounter_manager: EncounterManager) -> void:
	_encounter_manager = encounter_manager
	if _encounter_manager and not _encounter_manager.encounter_completed.is_connected(_on_encounter_completed):
		_encounter_manager.encounter_completed.connect(_on_encounter_completed)


func start_new_run() -> void:
	current_act = 1
	_set_state(RunState.RUN_START)
	current_act_data = _get_or_build_act_data(current_act)
	current_map_data = MapGenerator.generate_for_act(current_act_data)
	map_changed.emit(current_map_data)
	_start_act_intro()


func select_node(node_data: MapNodeData) -> bool:
	if node_data == null or current_map_data == null:
		return false
	if node_data.state != MapNodeData.NodeState.AVAILABLE:
		return false
	_pending_node_id = node_data.id
	current_map_data.current_node_id = node_data.id
	node_selected.emit(node_data)
	_set_state(RunState.ENCOUNTER_ACTIVE)
	if _is_placeholder_node(node_data.node_type):
		_waiting_placeholder = true
		placeholder_requested.emit("Placeholder", "This node type is not implemented yet.")
		return true
	if _encounter_manager != null and node_data.encounter_data != null:
		_encounter_manager.start_encounter(node_data.encounter_data)
	else:
		complete_current_node()
	return true


func select_node_by_id(node_id: String) -> bool:
	if current_map_data == null:
		return false
	return select_node(current_map_data.get_node(node_id))


func continue_placeholder_node() -> void:
	if not _waiting_placeholder:
		return
	_waiting_placeholder = false
	complete_current_node()


func complete_current_node() -> void:
	if current_map_data == null or _pending_node_id.is_empty():
		return
	var completed_id := _pending_node_id
	_pending_node_id = ""
	current_map_data.mark_visited(completed_id)
	var completed := current_map_data.get_node(completed_id)
	if completed != null and completed.next_nodes.is_empty():
		complete_act()
		return
	_set_state(RunState.MAP_VIEW)
	map_changed.emit(current_map_data)
	emit_focus_for_current_progress()


func complete_act() -> void:
	_set_state(RunState.ACT_COMPLETE)
	if current_act < 3:
		current_act += 1
		current_act_data = _get_or_build_act_data(current_act)
		current_map_data = MapGenerator.generate_for_act(current_act_data)
		_set_state(RunState.ACT_INTRO)
		map_changed.emit(current_map_data)
		_start_act_intro()
		return
	_set_state(RunState.VICTORY)
	EventBus.run_ended.emit(true)


func emit_focus_for_current_progress() -> void:
	if current_map_data == null:
		return
	var max_layer := 0
	for node: MapNodeData in current_map_data.get_available_nodes():
		max_layer = maxi(max_layer, node.layer)
	focus_layer_requested.emit(max_layer)


func get_map_data() -> MapData:
	return current_map_data


func _on_encounter_completed(_rewards: Dictionary) -> void:
	if state != RunState.ENCOUNTER_ACTIVE:
		return
	complete_current_node()


func _set_state(new_state: RunState) -> void:
	if state == new_state:
		return
	var previous := state
	state = new_state
	run_state_changed.emit(previous, new_state)


func _get_or_build_act_data(act_index: int) -> ActData:
	for act in act_definitions:
		if act != null and act.act_index == act_index:
			return act
	var built := ActData.new()
	built.act_index = act_index
	built.title = "Act %d" % act_index
	built.layer_count = 10
	return built


func _is_placeholder_node(node_type: MapNodeData.MapNodeType) -> bool:
	return node_type in [MapNodeData.MapNodeType.SHOP, MapNodeData.MapNodeType.REPAIR]


func _start_act_intro() -> void:
	if current_map_data == null:
		return
	var intro_node: MapNodeData = null
	for node: MapNodeData in current_map_data.get_available_nodes():
		if node.layer == 0 and node.node_type == MapNodeData.MapNodeType.MAIN_STORY:
			intro_node = node
			break
	if intro_node == null:
		_set_state(RunState.MAP_VIEW)
		emit_focus_for_current_progress()
		return
	_set_state(RunState.ACT_INTRO)
	select_node(intro_node)
