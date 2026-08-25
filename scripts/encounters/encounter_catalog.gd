class_name EncounterCatalog
extends RefCounted
## Builds curated EncounterData presets and bridges map nodes → encounters.

const PROLOGUE_ID := "SLEEPER_GOD"


static func get_encounter(encounter_id: String) -> EncounterData:
	var id := encounter_id.strip_edges()
	## Prefer god JSON registry (INTRO), then legacy hardcoded builders.
	var from_gods := StartingGodRegistry.load_god_encounter(id.to_lower())
	if from_gods == null and id == "SLEEPER_GOD":
		from_gods = StartingGodRegistry.load_god_encounter("sleeper_god")
	if from_gods != null:
		return from_gods
	var from_story := MainStoryRegistry.load_story_encounter(id.to_lower())
	if from_story != null:
		return from_story
	return null


static func build_prologue() -> EncounterData:
	return StartingGodRegistry.pick_random_god_encounter()


static func from_map_node(node: Dictionary) -> EncounterData:
	## Bridge legacy MapManager node dicts into EncounterData.
	var encounter := EncounterData.new()
	encounter.id = str(node.get("id", ""))
	encounter.title = str(node.get("label", encounter.id))
	encounter.title_key = str(node.get("label_key", ""))
	var node_type: int = int(node.get("type", MapManager.NodeType.COMBAT))
	match node_type:
		MapManager.NodeType.BOSS:
			encounter.type = EncounterData.EncounterType.COMBAT_BOSS
		MapManager.NodeType.REPAIR:
			encounter.type = EncounterData.EncounterType.REST_SITE
		MapManager.NodeType.EVENT:
			encounter.type = EncounterData.EncounterType.EVENT
		MapManager.NodeType.MAIN_STORY:
			encounter.type = EncounterData.EncounterType.MAIN_STORY
		MapManager.NodeType.INTRO:
			encounter.type = EncounterData.EncounterType.INTRO
		_:
			encounter.type = EncounterData.EncounterType.COMBAT_NORMAL
	var enemy_ids: Array = node.get("enemy_ids", [])
	encounter.payload = {
		"enemy_ids": enemy_ids.duplicate(),
		"faction": str(node.get("faction", "")),
		"threat_budget": int(node.get("threat_budget", 20)),
		"act": int(node.get("act", 1)),
		"layer": int(node.get("layer", 1)),
		"map_node_id": encounter.id,
	}
	## Explicit encounter_id on the node overrides catalog lookup for events.
	var catalog_id := str(node.get("encounter_id", "")).strip_edges()
	if not catalog_id.is_empty():
		var preset := get_encounter(catalog_id)
		if preset != null:
			return preset
	## Starting INTRO node: pick a random god encounter from pool.
	if encounter.type == EncounterData.EncounterType.INTRO:
		var god_encounter := StartingGodRegistry.pick_random_god_encounter()
		if god_encounter != null:
			god_encounter.payload["map_node_id"] = encounter.id
			god_encounter.payload["prologue"] = false
			return god_encounter
	return encounter
