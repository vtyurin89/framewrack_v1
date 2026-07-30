class_name MapGenerator
extends RefCounted

const X_SPACING := 220.0
const Y_SPACING := 250.0
const ORIGIN := Vector2(140.0, 180.0)


static func generate_for_act(act_data: ActData) -> MapData:
	var out := MapData.new()
	var total_layers := maxi(5, act_data.layer_count)
	var boss_layer := total_layers - 2
	var finale_layer := total_layers - 1

	var start := _create_node(act_data, 0, 0, MapNodeData.MapNodeType.MAIN_STORY)
	start.state = MapNodeData.NodeState.AVAILABLE
	out.nodes[start.id] = start

	var previous_ids: Array[String] = [start.id]

	for layer in range(1, boss_layer):
		var count := randi_range(3, 4)
		var layer_ids: Array[String] = []
		for i in count:
			var node_type := _pick_middle_type()
			var node := _create_node(act_data, layer, i, node_type)
			out.nodes[node.id] = node
			layer_ids.append(node.id)
		_wire_layers(out, previous_ids, layer_ids)
		previous_ids = layer_ids

	var boss := _create_node(act_data, boss_layer, 1, MapNodeData.MapNodeType.BOSS)
	if act_data.boss_encounter_data != null:
		boss.encounter_data = act_data.boss_encounter_data.duplicate(true) as EncounterData
	out.nodes[boss.id] = boss
	for prev_id in previous_ids:
		var prev := out.get_node(prev_id)
		if prev != null and not prev.next_nodes.has(boss.id):
			prev.next_nodes.append(boss.id)

	var finale := _create_node(act_data, finale_layer, 1, MapNodeData.MapNodeType.MAIN_STORY)
	out.nodes[finale.id] = finale
	boss.next_nodes.append(finale.id)
	return out


static func _wire_layers(map_data: MapData, from_ids: Array[String], to_ids: Array[String]) -> void:
	if from_ids.is_empty() or to_ids.is_empty():
		return
	for to_id in to_ids:
		var from_id := from_ids[randi() % from_ids.size()]
		var from_node := map_data.get_node(from_id)
		if from_node != null and not from_node.next_nodes.has(to_id):
			from_node.next_nodes.append(to_id)
	for from_id in from_ids:
		var branch_count := 1 + (1 if randf() < 0.35 else 0)
		for _branch in branch_count:
			var to_id := to_ids[randi() % to_ids.size()]
			var from_node := map_data.get_node(from_id)
			if from_node != null and not from_node.next_nodes.has(to_id):
				from_node.next_nodes.append(to_id)


static func _create_node(
	act_data: ActData,
	layer: int,
	grid_x: int,
	node_type: MapNodeData.MapNodeType
) -> MapNodeData:
	var node := MapNodeData.new()
	node.id = "act%s_l%s_n%s" % [act_data.act_index, layer, grid_x]
	node.layer = layer
	node.grid_x = grid_x
	node.position = ORIGIN + Vector2(grid_x * X_SPACING, layer * Y_SPACING)
	node.node_type = node_type
	node.state = MapNodeData.NodeState.LOCKED
	node.encounter_data = _build_encounter_for_node(act_data, node)
	return node


static func _build_encounter_for_node(act_data: ActData, node: MapNodeData) -> EncounterData:
	match node.node_type:
		MapNodeData.MapNodeType.MAIN_STORY:
			return _build_story_encounter(act_data, node)
		MapNodeData.MapNodeType.COMBAT:
			return _build_basic_encounter(node.id, EncounterData.EncounterType.COMBAT_NORMAL, "Skirmish")
		MapNodeData.MapNodeType.EVENT:
			return _build_basic_encounter(node.id, EncounterData.EncounterType.EVENT, "Event")
		MapNodeData.MapNodeType.REPAIR:
			return _build_basic_encounter(node.id, EncounterData.EncounterType.REST_SITE, "Repair")
		MapNodeData.MapNodeType.SHOP:
			return _build_basic_encounter(node.id, EncounterData.EncounterType.SHOP, "Shop")
		MapNodeData.MapNodeType.ELITE:
			return _build_basic_encounter(node.id, EncounterData.EncounterType.COMBAT_ELITE, "Elite")
		MapNodeData.MapNodeType.BOSS:
			return _build_basic_encounter(node.id, EncounterData.EncounterType.COMBAT_BOSS, "Boss")
		_:
			return _build_basic_encounter(node.id, EncounterData.EncounterType.UNKNOWN, "Unknown")


static func _build_story_encounter(act_data: ActData, node: MapNodeData) -> EncounterData:
	if node.layer == 0 and act_data.act_index == 1:
		var god := StartingGodRegistry.pick_random_god_encounter()
		if god != null:
			var copy := god.duplicate(true) as EncounterData
			copy.payload["map_node_id"] = node.id
			copy.payload["prologue"] = false
			return copy
	var story := MainStoryEncounterData.new()
	story.id = "%s_story" % node.id
	story.title = "Act %d Story" % act_data.act_index
	story.story_act = act_data.act_index
	story.payload = {"map_node_id": node.id}
	return story


static func _build_basic_encounter(id: String, kind: EncounterData.EncounterType, title: String) -> EncounterData:
	var encounter := EncounterData.new()
	encounter.id = id
	encounter.type = kind
	encounter.title = title
	encounter.payload = {"map_node_id": id}
	return encounter


static func _pick_middle_type() -> MapNodeData.MapNodeType:
	var roll := randf()
	if roll < 0.45:
		return MapNodeData.MapNodeType.COMBAT
	if roll < 0.65:
		return MapNodeData.MapNodeType.EVENT
	if roll < 0.80:
		return MapNodeData.MapNodeType.REPAIR if randf() < 0.5 else MapNodeData.MapNodeType.SHOP
	if roll < 0.95:
		return MapNodeData.MapNodeType.ELITE
	return MapNodeData.MapNodeType.MAIN_STORY
