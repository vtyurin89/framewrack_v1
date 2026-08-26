class_name MapGenerator
extends RefCounted
## Lane-based branching map generator (Slay the Spire style).
## Nodes occupy absolute column indices; connections are limited to adjacent lanes.

const CANVAS_WIDTH := 1000.0
const CANVAS_HEIGHT := 2500.0
const X_SPACING := 150.0
const Y_SPACING := 220.0
const BOTTOM_PADDING := 220.0

## Absolute lane columns: 0 .. MAX_COLUMNS-1
const MAX_COLUMNS := 6
const START_COLUMN := 2
const LAYER1_COLUMNS: Array[int] = [1, 2, 3]
const MIN_MIDDLE_NODES := 3
const MAX_MIDDLE_NODES := 6
const PEAK_MIN_NODES := 5
const SPLIT_CHANCE := 0.32
const SPLIT_CHANCE_PEAK := 0.62
const BRIDGE_CHANCE := 0.22


static func generate_for_act(act_data: ActData) -> MapData:
	var out := MapData.new()
	## Layout: start story → middle → boss → end story → stairs.
	## Needs at least 5 layers (0..4).
	var total_layers := maxi(5, act_data.get_map_layer_count())
	var boss_layer := total_layers - 3
	var finale_layer := total_layers - 2
	var stairs_layer := total_layers - 1

	## Layer 0 — Act 1 opens with INTRO (gods); later acts open with MAIN_STORY.
	var start_type := (
		MapNodeData.MapNodeType.INTRO
		if act_data.act_index == 1
		else MapNodeData.MapNodeType.MAIN_STORY
	)
	var start := _create_node(act_data, 0, START_COLUMN, start_type)
	start.state = MapNodeData.NodeState.AVAILABLE
	out.nodes[start.id] = start

	## Layer 1 — exactly 3 starting arteries (Left / Center / Right).
	var prev_by_col: Dictionary = {}  ## int grid_x -> MapNodeData
	var layer1_types: Dictionary = {}
	for col in LAYER1_COLUMNS:
		var node_type := _type_for_pre_boss_or_roll(act_data, 1, boss_layer, layer1_types)
		layer1_types[node_type] = int(layer1_types.get(node_type, 0)) + 1
		var node := _create_node(act_data, 1, col, node_type)
		out.nodes[node.id] = node
		prev_by_col[col] = node
		start.next_nodes.append(node.id)

	## Middle layers — evolve parallel lanes with local splits / merges.
	for layer in range(2, boss_layer):
		var phase := _density_phase(layer, boss_layer)
		var next_cols := _plan_next_columns(prev_by_col.keys(), phase)
		var next_by_col: Dictionary = {}
		var layer_type_counts: Dictionary = {}
		for col in next_cols:
			var node_type := _type_for_pre_boss_or_roll(
				act_data, layer, boss_layer, layer_type_counts
			)
			layer_type_counts[node_type] = int(layer_type_counts.get(node_type, 0)) + 1
			var node := _create_node(act_data, layer, col, node_type)
			out.nodes[node.id] = node
			next_by_col[col] = node
		_connect_adjacent_layers(prev_by_col, next_by_col)
		prev_by_col = next_by_col

	## Boss convergence → act finale story → stairs to next act.
	var boss := _create_node(act_data, boss_layer, START_COLUMN, MapNodeData.MapNodeType.BOSS)
	if act_data.boss_encounter_data != null:
		boss.encounter_data = act_data.boss_encounter_data.duplicate(true) as EncounterData
		if boss.encounter_data != null:
			boss.encounter_data.payload["map_node_id"] = boss.id
			boss.encounter_data.payload["act"] = act_data.act_index
	out.nodes[boss.id] = boss
	for col in prev_by_col.keys():
		var prev: MapNodeData = prev_by_col[col]
		if not prev.next_nodes.has(boss.id):
			prev.next_nodes.append(boss.id)

	var finale := _create_node(act_data, finale_layer, START_COLUMN, MapNodeData.MapNodeType.MAIN_STORY)
	out.nodes[finale.id] = finale
	boss.next_nodes.append(finale.id)

	var stairs := _create_node(act_data, stairs_layer, START_COLUMN, MapNodeData.MapNodeType.STAIRS)
	out.nodes[stairs.id] = stairs
	finale.next_nodes.append(stairs.id)

	_layout_positions(out)
	return out


static func _density_phase(layer: int, boss_layer: int) -> String:
	## expand → peak (≥5 guaranteed) → taper toward boss.
	if layer >= boss_layer - 2:
		return "taper"
	## Peak covers the central middle stretch (everything after first expand layer).
	if layer >= 3 and layer <= boss_layer - 3:
		return "peak"
	## Short maps: if no room for a long peak band, still force peak on the middle-most layer.
	if boss_layer <= 5 and layer == 2:
		return "peak"
	return "expand"


static func _plan_next_columns(prev_cols_variant: Array, phase: String) -> Array[int]:
	var prev_cols: Array[int] = []
	for value in prev_cols_variant:
		prev_cols.append(int(value))
	prev_cols.sort()

	var min_count := MIN_MIDDLE_NODES
	var max_count := MAX_MIDDLE_NODES
	var split_chance := SPLIT_CHANCE
	match phase:
		"peak":
			min_count = PEAK_MIN_NODES
			max_count = MAX_MIDDLE_NODES
			split_chance = SPLIT_CHANCE_PEAK
		"taper":
			min_count = 3
			max_count = 4
			split_chance = 0.12
		_:
			## Early expand: bias toward growing to 4–5 quickly.
			min_count = 4
			max_count = 5
			split_chance = 0.48

	var occupied: Dictionary = {}

	## Seed: each previous lane continues (prefer straight, else nearest free adjacent).
	for x in prev_cols:
		var chosen := _pick_continuation_column(x, occupied)
		occupied[chosen] = true

	## Splits into adjacent empty lanes (more aggressive during peak).
	for x in prev_cols:
		if occupied.size() >= max_count:
			break
		if randf() > split_chance:
			continue
		var side := -1 if randf() < 0.5 else 1
		var split_x := x + side
		if split_x < 0 or split_x >= MAX_COLUMNS:
			continue
		if occupied.has(split_x):
			continue
		if absi(split_x - x) <= 1:
			occupied[split_x] = true

	## During peak, prefer a second pass of forced splits until min_count.
	if phase == "peak":
		_force_fill_to_count(occupied, prev_cols, min_count)

	## Trim if over capacity (prefer dropping edge columns farthest from center).
	while occupied.size() > max_count:
		var drop := _farthest_from_center(occupied.keys())
		occupied.erase(drop)

	## Grow if under capacity by filling adjacent empty lanes.
	_force_fill_to_count(occupied, prev_cols, min_count)

	## Peak bias: often push to 6 when already at 5.
	if phase == "peak" and occupied.size() == 5 and randf() < 0.55:
		_force_fill_to_count(occupied, prev_cols, 6)

	var result: Array[int] = []
	var sorted_keys: Array = occupied.keys()
	sorted_keys.sort()
	for key in sorted_keys:
		result.append(int(key))
	return result


static func _force_fill_to_count(occupied: Dictionary, prev_cols: Array[int], target: int) -> void:
	while occupied.size() < target:
		var added := false
		var keys: Array = occupied.keys()
		keys.sort()
		## Prefer expanding outward from center for cleaner arteries.
		keys.sort_custom(
			func(a, b) -> bool:
				return absi(int(a) - START_COLUMN) < absi(int(b) - START_COLUMN)
		)
		for x in keys:
			for side in [-1, 1]:
				var nx: int = int(x) + side
				if nx < 0 or nx >= MAX_COLUMNS:
					continue
				if occupied.has(nx):
					continue
				if _is_reachable_from_any(nx, prev_cols):
					occupied[nx] = true
					added = true
					break
			if occupied.size() >= target:
				break
		if not added:
			break


static func _pick_continuation_column(from_x: int, occupied: Dictionary) -> int:
	## Prefer straight; fall back to adjacent free; otherwise reuse occupied adjacent.
	if not occupied.has(from_x):
		return from_x
	var sides: Array[int] = [-1, 1]
	if randf() < 0.5:
		sides.reverse()
	for side in sides:
		var nx := from_x + side
		if nx >= 0 and nx < MAX_COLUMNS and not occupied.has(nx):
			return nx
	return from_x


static func _farthest_from_center(cols: Array) -> int:
	var best := int(cols[0])
	var best_dist := -1
	for value in cols:
		var col := int(value)
		var dist := absi(col - START_COLUMN)
		if dist > best_dist:
			best_dist = dist
			best = col
	return best


static func _is_reachable_from_any(col: int, prev_cols: Array[int]) -> bool:
	for px in prev_cols:
		if absi(col - px) <= 1:
			return true
	return false


static func _connect_adjacent_layers(prev_by_col: Dictionary, next_by_col: Dictionary) -> void:
	## Primary: every previous node gets at least one legal forward edge.
	for px_variant in prev_by_col.keys():
		var px := int(px_variant)
		var prev: MapNodeData = prev_by_col[px]
		var candidates: Array[int] = _adjacent_columns_present(px, next_by_col)
		if candidates.is_empty():
			## Should be rare; snap to closest next column.
			candidates = [_closest_column(px, next_by_col.keys())] as Array[int]
		## Prefer straight continuation.
		var primary: int = px if candidates.has(px) else candidates[randi() % candidates.size()]
		_add_edge(prev, next_by_col[primary] as MapNodeData)

		## Rare bridge to another adjacent lane.
		if candidates.size() > 1 and randf() < BRIDGE_CHANCE:
			var others: Array[int] = []
			for c in candidates:
				if c != primary:
					others.append(c)
			if not others.is_empty():
				var bridge: int = others[randi() % others.size()]
				_add_edge(prev, next_by_col[bridge] as MapNodeData)

	## Guarantee every next node has a parent (no orphans).
	for nx_variant in next_by_col.keys():
		var nx := int(nx_variant)
		var next: MapNodeData = next_by_col[nx]
		if _has_any_parent(next.id, prev_by_col):
			continue
		var parents: Array[int] = _adjacent_columns_present(nx, prev_by_col)
		if parents.is_empty():
			parents = [_closest_column(nx, prev_by_col.keys())] as Array[int]
		var parent_x: int = parents[randi() % parents.size()]
		_add_edge(prev_by_col[parent_x] as MapNodeData, next)


static func _adjacent_columns_present(col: int, by_col: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for dx: int in [-1, 0, 1]:
		var nx: int = col + dx
		if by_col.has(nx):
			result.append(nx)
	return result


static func _closest_column(col: int, cols: Array) -> int:
	var best := int(cols[0])
	var best_dist := absi(best - col)
	for value in cols:
		var c := int(value)
		var dist := absi(c - col)
		if dist < best_dist:
			best_dist = dist
			best = c
	return best


static func _has_any_parent(node_id: String, prev_by_col: Dictionary) -> bool:
	for value in prev_by_col.values():
		var prev: MapNodeData = value
		if prev.next_nodes.has(node_id):
			return true
	return false


static func _add_edge(from_node: MapNodeData, to_node: MapNodeData) -> void:
	if from_node == null or to_node == null:
		return
	if not from_node.next_nodes.has(to_node.id):
		from_node.next_nodes.append(to_node.id)


static func _layout_positions(map_data: MapData) -> void:
	## Absolute column layout keeps lanes visually parallel (no per-layer reindexing).
	const MIN_NODE_SEPARATION := 72.0
	const JITTER_X := 20.0
	const JITTER_Y := 15.0
	var origin_x := CANVAS_WIDTH * 0.5 - float(MAX_COLUMNS - 1) * X_SPACING * 0.5

	var by_layer: Dictionary = {}
	for node: MapNodeData in map_data.get_all_nodes():
		var y := CANVAS_HEIGHT - BOTTOM_PADDING - float(node.layer) * Y_SPACING
		y = maxf(y, 80.0)
		node.position = Vector2(origin_x + float(node.grid_x) * X_SPACING, y)
		if not by_layer.has(node.layer):
			by_layer[node.layer] = []
		(by_layer[node.layer] as Array).append(node)

	## Organic jitter with same-layer overlap resolution.
	for layer in by_layer.keys():
		var layer_nodes: Array = by_layer[layer]
		layer_nodes.sort_custom(
			func(a: MapNodeData, b: MapNodeData) -> bool:
				return a.grid_x < b.grid_x
		)
		for node: MapNodeData in layer_nodes:
			node.position += Vector2(randf_range(-JITTER_X, JITTER_X), randf_range(-JITTER_Y, JITTER_Y))
		## Push apart horizontally if jitter caused overlap.
		for _pass in 4:
			for i in range(layer_nodes.size() - 1):
				var left: MapNodeData = layer_nodes[i]
				var right: MapNodeData = layer_nodes[i + 1]
				var gap := right.position.x - left.position.x
				if gap >= MIN_NODE_SEPARATION:
					continue
				var push := (MIN_NODE_SEPARATION - gap) * 0.5
				left.position.x -= push
				right.position.x += push


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
	node.position = Vector2.ZERO
	node.node_type = node_type
	node.state = MapNodeData.NodeState.LOCKED
	node.encounter_data = _build_encounter_for_node(act_data, node)
	return node


static func _build_encounter_for_node(act_data: ActData, node: MapNodeData) -> EncounterData:
	match node.node_type:
		MapNodeData.MapNodeType.INTRO:
			return _build_intro_encounter(act_data, node)
		MapNodeData.MapNodeType.MAIN_STORY:
			return _build_story_encounter(act_data, node)
		MapNodeData.MapNodeType.COMBAT:
			return _build_combat_encounter(
				act_data, node, EncounterData.EncounterType.COMBAT_NORMAL, "Skirmish"
			)
		MapNodeData.MapNodeType.EVENT:
			return _build_event_encounter(act_data, node)
		MapNodeData.MapNodeType.REPAIR:
			return _build_basic_encounter(node.id, EncounterData.EncounterType.REST_SITE, "Repair")
		MapNodeData.MapNodeType.SHOP:
			return _build_shop_encounter(act_data, node)
		MapNodeData.MapNodeType.ELITE:
			return _build_combat_encounter(
				act_data, node, EncounterData.EncounterType.COMBAT_ELITE, "Elite"
			)
		MapNodeData.MapNodeType.BOSS:
			return _build_combat_encounter(
				act_data, node, EncounterData.EncounterType.COMBAT_BOSS, "Boss"
			)
		MapNodeData.MapNodeType.STAIRS:
			return _build_basic_encounter(node.id, EncounterData.EncounterType.STAIRS, "Stairs")
		MapNodeData.MapNodeType.REWARD:
			return _build_chest_encounter(act_data, node)
		_:
			return _build_basic_encounter(node.id, EncounterData.EncounterType.UNKNOWN, "Unknown")


static func _build_intro_encounter(act_data: ActData, node: MapNodeData) -> EncounterData:
	## Act 1 opening: random starting-god INTRO dialog.
	var god := StartingGodRegistry.pick_random_god_encounter()
	if god != null:
		var copy := god.duplicate(true) as EncounterData
		copy.payload["map_node_id"] = node.id
		copy.payload["prologue"] = false
		copy.payload["act"] = act_data.act_index if act_data != null else 1
		return copy
	var fallback := IntroEncounterData.new()
	fallback.id = "%s_intro" % node.id
	fallback.title_key = "KEY_TYPE_INTRO"
	fallback.payload = {
		"map_node_id": node.id,
		"act": act_data.act_index if act_data != null else 1,
	}
	return fallback


static func _build_story_encounter(act_data: ActData, node: MapNodeData) -> EncounterData:
	## Opening beat (layer 0): MAIN_STORY stubs for acts 2+.
	if node.layer == 0:
		var opening := MainStoryRegistry.load_opening_for_act(act_data.act_index)
		if opening != null:
			var copy := opening.duplicate(true) as EncounterData
			copy.payload["map_node_id"] = node.id
			copy.payload["act"] = act_data.act_index
			return copy
	var story := MainStoryEncounterData.new()
	story.id = "%s_story" % node.id
	story.title = "Act %d Story" % act_data.act_index
	story.story_act = act_data.act_index
	story.title_key = "KEY_TYPE_MAIN_STORY"
	story.payload = {
		"map_node_id": node.id,
		"act": act_data.act_index,
		## Finale story (after boss) should not re-roll a starting god.
		"act_finale": node.layer > 0,
	}
	return story


static func _build_event_encounter(act_data: ActData, node: MapNodeData) -> EncounterData:
	var act_index := act_data.act_index if act_data != null else 1
	## Prefer StoryEventManager act queues (Pale Maiden, White Fog, faction fillers).
	if StoryEventManager != null:
		var story_enc := StoryEventManager.build_encounter_for_act(act_index)
		if story_enc != null:
			story_enc.payload["map_node_id"] = node.id
			story_enc.payload["act"] = act_index
			story_enc.payload["layer"] = node.layer
			return story_enc
	var encounter := EncounterData.new()
	encounter.id = node.id
	encounter.type = EncounterData.EncounterType.EVENT
	encounter.title = "Event"
	encounter.title_key = "KEY_TYPE_EVENT"
	encounter.payload = {
		"map_node_id": node.id,
		"act": act_index,
		"item_id": "REBEL_CLEAVER",
		"heal_amount": 10,
	}
	return encounter


static func _build_combat_encounter(
	act_data: ActData,
	node: MapNodeData,
	kind: EncounterData.EncounterType,
	title: String
) -> EncounterData:
	var encounter := EncounterData.new()
	encounter.id = node.id
	encounter.type = kind
	encounter.title = title
	encounter.title_key = _title_key_for_type(kind)
	var faction := _faction_for_act(act_data)
	## Enemy packs are resolved at launch via EnemyGroup (layer + elite flag).
	encounter.payload = {
		"map_node_id": node.id,
		"act": act_data.act_index if act_data != null else 1,
		"faction": faction,
		"layer": node.layer,
		"enemy_ids": [],
	}
	return encounter


static func _build_basic_encounter(id: String, kind: EncounterData.EncounterType, title: String) -> EncounterData:
	var encounter := EncounterData.new()
	encounter.id = id
	encounter.type = kind
	encounter.title = title
	encounter.title_key = _title_key_for_type(kind)
	encounter.payload = {"map_node_id": id}
	return encounter


static func _build_shop_encounter(act_data: ActData, node: MapNodeData) -> EncounterData:
	var encounter := _build_basic_encounter(node.id, EncounterData.EncounterType.SHOP, "Shop")
	var act_index := act_data.act_index if act_data != null else 1
	encounter.payload["act"] = maxi(1, act_index)
	encounter.payload["layer"] = node.layer
	return encounter


static func _build_chest_encounter(act_data: ActData, node: MapNodeData) -> EncounterData:
	## Rare map reward site — locked chests need a Lockpick.
	var encounter := _build_basic_encounter(node.id, EncounterData.EncounterType.CHEST, "Reward")
	var act_index := act_data.act_index if act_data != null else 1
	encounter.payload["act"] = maxi(1, act_index)
	encounter.payload["layer"] = node.layer
	## ~55% locked — encourages carrying a lockpick.
	encounter.payload["locked"] = randf() < 0.55
	return encounter


static func _faction_for_act(act_data: ActData) -> String:
	if act_data != null and not act_data.primary_faction.strip_edges().is_empty():
		return act_data.primary_faction.strip_edges().to_lower()
	var act_index := act_data.act_index if act_data != null else 1
	match act_index:
		2:
			return "synthet"
		3:
			return "chimera"
		_:
			return "human"


static func _threat_budget_for(
	act_data: ActData, layer: int, kind: EncounterData.EncounterType
) -> int:
	var base := 18
	var elite := 32
	if act_data != null:
		base = maxi(8, act_data.normal_threat_budget)
		elite = maxi(base + 6, act_data.elite_threat_budget)
	## Mild scaling by depth so early fights stay lighter.
	var depth_bonus := maxi(0, layer - 1) * 2
	match kind:
		EncounterData.EncounterType.COMBAT_ELITE:
			return elite + depth_bonus
		EncounterData.EncounterType.COMBAT_BOSS:
			return elite + depth_bonus + 12
		_:
			return base + depth_bonus


static func _title_key_for_type(kind: EncounterData.EncounterType) -> String:
	match kind:
		EncounterData.EncounterType.COMBAT_NORMAL:
			return "KEY_TYPE_COMBAT"
		EncounterData.EncounterType.COMBAT_ELITE:
			return "KEY_TYPE_ELITE"
		EncounterData.EncounterType.COMBAT_BOSS:
			return "KEY_TYPE_BOSS"
		EncounterData.EncounterType.EVENT:
			return "KEY_TYPE_EVENT"
		EncounterData.EncounterType.INTRO:
			return "KEY_TYPE_INTRO"
		EncounterData.EncounterType.REST_SITE:
			return "KEY_TYPE_REPAIR"
		EncounterData.EncounterType.SHOP:
			return "KEY_TYPE_SHOP"
		EncounterData.EncounterType.MAIN_STORY:
			return "KEY_TYPE_MAIN_STORY"
		EncounterData.EncounterType.STAIRS:
			return "KEY_TYPE_STAIRS"
		EncounterData.EncounterType.CHEST:
			return "KEY_TYPE_REWARD"
		_:
			return ""


static func _type_for_pre_boss_or_roll(
	act_data: ActData,
	layer: int,
	boss_layer: int,
	layer_type_counts: Dictionary
) -> MapNodeData.MapNodeType:
	## Hard rule: every node that feeds the act boss is a repair site.
	## Overrides weighted rolls / early-act REPAIR exclusions.
	if layer == boss_layer - 1:
		return MapNodeData.MapNodeType.REPAIR
	return _pick_middle_type(act_data, layer, layer_type_counts)


static func _pick_middle_type(
	act_data: ActData,
	layer: int,
	layer_type_counts: Dictionary
) -> MapNodeData.MapNodeType:
	## Weighted pick with layer caps and Act 1 early-layer exclusions.
	## INTRO / MAIN_STORY / STAIRS / BOSS are never rolled here — fixed at act ends.
	for _attempt in 24:
		var candidate := _roll_middle_type(act_data, layer)
		if int(layer_type_counts.get(candidate, 0)) >= 3:
			continue
		return candidate
	## Fallback: first allowed type under the per-layer cap.
	for candidate in _allowed_middle_types(act_data, layer):
		if int(layer_type_counts.get(candidate, 0)) < 3:
			return candidate as MapNodeData.MapNodeType
	return MapNodeData.MapNodeType.COMBAT


static func _allowed_middle_types(act_data: ActData, layer: int) -> Array:
	var types: Array = [
		MapNodeData.MapNodeType.COMBAT,
		MapNodeData.MapNodeType.EVENT,
		MapNodeData.MapNodeType.SHOP,
		MapNodeData.MapNodeType.REPAIR,
		MapNodeData.MapNodeType.ELITE,
		MapNodeData.MapNodeType.REWARD,
	]
	if act_data != null and act_data.act_index == 1 and layer <= 2:
		types.erase(MapNodeData.MapNodeType.ELITE)
		types.erase(MapNodeData.MapNodeType.REPAIR)
		types.erase(MapNodeData.MapNodeType.REWARD)
	return types


static func _roll_middle_type(act_data: ActData, layer: int) -> MapNodeData.MapNodeType:
	var exclude_elite_repair := act_data != null and act_data.act_index == 1 and layer <= 2
	## Re-roll until we land on an allowed type (keeps original weight feel).
	## REWARD is the rarest bucket (~4%).
	for _attempt in 16:
		var roll := randf()
		var picked: MapNodeData.MapNodeType
		if roll < 0.44:
			picked = MapNodeData.MapNodeType.COMBAT
		elif roll < 0.68:
			picked = MapNodeData.MapNodeType.EVENT
		elif roll < 0.82:
			picked = MapNodeData.MapNodeType.REPAIR if randf() < 0.5 else MapNodeData.MapNodeType.SHOP
		elif roll < 0.96:
			picked = MapNodeData.MapNodeType.ELITE
		else:
			picked = MapNodeData.MapNodeType.REWARD
		if exclude_elite_repair and picked in [
			MapNodeData.MapNodeType.ELITE,
			MapNodeData.MapNodeType.REPAIR,
			MapNodeData.MapNodeType.REWARD,
		]:
			continue
		return picked
	return MapNodeData.MapNodeType.COMBAT
