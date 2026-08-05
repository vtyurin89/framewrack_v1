extends Node
## Autoload: act story-event queues + narrative flags (Pale Maiden / White Fog / Faceless Lady).

signal flags_changed
signal queues_rebuilt

const EVENTS_DIR := "res://data/encounters/events/"
const WHITE_FOG_ID := "white_fog"
const FACELESS_LADY_ID := "faceless_lady"
const FACELESS_INJECT_CHANCE := 0.35

## Narrative markers
var pale_maiden_pact_made: bool = false
var white_fog_event_triggered: bool = false
var faceless_lady_spawned: bool = false
var faceless_lady_defeated: bool = false

var act1_event_queue: Array[StoryEvent] = []
var act2_event_queue: Array[StoryEvent] = []
var act3_event_queue: Array[StoryEvent] = []

## Catalog of authored events keyed by id.
var _catalog: Dictionary = {}  # String -> StoryEvent


func _ready() -> void:
	_rebuild_catalog()
	reset_run()


func reset_run() -> void:
	pale_maiden_pact_made = false
	white_fog_event_triggered = false
	faceless_lady_spawned = false
	faceless_lady_defeated = false
	rebuild_act_queues()
	flags_changed.emit()


func mark_pale_maiden_pact() -> void:
	pale_maiden_pact_made = true
	flags_changed.emit()


func mark_white_fog_triggered() -> void:
	white_fog_event_triggered = true
	flags_changed.emit()


func mark_faceless_lady_spawned() -> void:
	faceless_lady_spawned = true
	flags_changed.emit()


func mark_faceless_lady_defeated() -> void:
	faceless_lady_defeated = true
	flags_changed.emit()


func can_spawn_faceless_lady() -> bool:
	## Pact unlocks her; defeat permanently removes her from spawn tables.
	return pale_maiden_pact_made and not faceless_lady_defeated


func rebuild_act_queues() -> void:
	_rebuild_catalog()
	act1_event_queue = _build_queue_for_act(1)
	act2_event_queue = _build_queue_for_act(2)
	act3_event_queue = _build_queue_for_act(3)
	queues_rebuilt.emit()


func get_queue_for_act(act_index: int) -> Array[StoryEvent]:
	match maxi(act_index, 1):
		2:
			return act2_event_queue
		3:
			return act3_event_queue
		_:
			return act1_event_queue


func get_next_event_for_act(act_index: int) -> StoryEvent:
	## Pop from back, push to front (cycle). Skip spent one-shots (White Fog).
	var queue := get_queue_for_act(act_index)
	if queue.is_empty():
		rebuild_act_queues()
		queue = get_queue_for_act(act_index)
	if queue.is_empty():
		return null

	var guard := queue.size() + 2
	while guard > 0:
		guard -= 1
		var pulled: StoryEvent = queue.pop_back()
		if pulled == null:
			continue
		if pulled.id == WHITE_FOG_ID and act_index < 2:
			## Should not be in Act 1 queues; cycle past if present.
			queue.push_front(pulled)
			continue
		if pulled.id == WHITE_FOG_ID and white_fog_event_triggered:
			## Cycle past spent one-shot without re-queueing at front as "active".
			queue.push_front(pulled)
			continue
		queue.push_front(pulled)
		return pulled
	return null


func notify_event_started(event_id: String) -> void:
	var key := event_id.strip_edges().to_lower()
	if key == WHITE_FOG_ID:
		mark_white_fog_triggered()


func build_encounter_for_act(act_index: int) -> EncounterData:
	var story := get_next_event_for_act(act_index)
	if story == null:
		return null
	var json_id := story.encounter_json_id.strip_edges()
	if json_id.is_empty():
		json_id = story.id
	var encounter := StoryEventRegistry.load_event_encounter(json_id)
	if encounter == null:
		return null
	encounter.payload["story_event_id"] = story.id
	encounter.payload["act"] = maxi(act_index, 1)
	encounter.payload["faction_tag"] = story.get_faction_key()
	return encounter


func maybe_inject_faceless_lady(
	enemy_datas: Array[EnemyData], act_index: int = 1
) -> Array[EnemyData]:
	## Optionally append / replace with Faceless Lady when pact is active (Act 2+ only).
	if act_index < 2:
		return enemy_datas
	if not can_spawn_faceless_lady():
		return enemy_datas
	if EnemyDatabase == null or not EnemyDatabase.has_enemy(FACELESS_LADY_ID):
		return enemy_datas
	for existing: EnemyData in enemy_datas:
		if existing != null and existing.id.strip_edges().to_lower() == FACELESS_LADY_ID:
			return enemy_datas
	if randf() > FACELESS_INJECT_CHANCE:
		return enemy_datas
	var lady := EnemyDatabase.create_blueprint(FACELESS_LADY_ID)
	if lady == null:
		return enemy_datas
	var out: Array[EnemyData] = enemy_datas.duplicate()
	if out.size() >= 3:
		out[out.size() - 1] = lady
	else:
		out.append(lady)
	mark_faceless_lady_spawned()
	return out


func _rebuild_catalog() -> void:
	_catalog.clear()
	## Pale Maiden is a starting god (data/encounters/gods/), not a map event.
	_register_event(WHITE_FOG_ID, StoryEvent.Faction.HUMAN, WHITE_FOG_ID, true)
	## Act 1 city beats — travel through the ruins of Ra'im.
	_register_event("raim_great_ascent", StoryEvent.Faction.HUMAN, "raim_great_ascent", false)
	_register_event("raim_hollow_windows", StoryEvent.Faction.HUMAN, "raim_hollow_windows", false)


func _register_event(
	event_id: String, faction: StoryEvent.Faction, json_id: String, one_shot: bool
) -> void:
	var ev := StoryEvent.new()
	ev.id = event_id
	ev.faction = faction
	ev.encounter_json_id = json_id
	ev.one_shot = one_shot
	_catalog[event_id] = ev


func _build_queue_for_act(act_index: int) -> Array[StoryEvent]:
	var weights := _faction_weights_for_act(act_index)
	var by_faction: Dictionary = {
		"human": [],
		"robot": [],
		"chimera": [],
	}
	for key in _catalog.keys():
		var ev: StoryEvent = _catalog[key]
		if ev == null:
			continue
		## White Fog is Act 2+ only (post-Ra'im narrative beat).
		if ev.id == WHITE_FOG_ID and act_index < 2:
			continue
		by_faction[ev.get_faction_key()].append(ev)

	var queue: Array[StoryEvent] = []
	var target_size := 12
	for _i in target_size:
		var faction_key := _roll_faction(weights)
		var pool: Array = by_faction.get(faction_key, [])
		if pool.is_empty():
			## Fallback any catalog entry allowed for this act.
			var all_keys: Array = []
			for catalog_key in _catalog.keys():
				var candidate: StoryEvent = _catalog[catalog_key]
				if candidate == null:
					continue
				if candidate.id == WHITE_FOG_ID and act_index < 2:
					continue
				all_keys.append(catalog_key)
			if all_keys.is_empty():
				break
			var pick_id: String = str(all_keys[randi() % all_keys.size()])
			queue.append((_catalog[pick_id] as StoryEvent).duplicate(true) as StoryEvent)
			continue
		var pick: StoryEvent = pool[randi() % pool.size()]
		queue.append(pick.duplicate(true) as StoryEvent)
	queue.shuffle()
	return queue


func _faction_weights_for_act(act_index: int) -> Dictionary:
	## human / robot / chimera weights summing to 1.0
	match maxi(act_index, 1):
		2:
			return {"human": 0.15, "robot": 0.60, "chimera": 0.25}
		3:
			return {"human": 0.10, "robot": 0.30, "chimera": 0.60}
		_:
			return {"human": 0.70, "robot": 0.20, "chimera": 0.10}


func _roll_faction(weights: Dictionary) -> String:
	var roll := randf()
	var acc := 0.0
	for key in ["human", "robot", "chimera"]:
		acc += float(weights.get(key, 0.0))
		if roll <= acc:
			return key
	return "human"
