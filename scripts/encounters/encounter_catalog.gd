class_name EncounterCatalog
extends RefCounted
## Builds curated EncounterData presets (prologue + reusable templates).

const PROLOGUE_ID := "OLD_MACHINE_GOD_EVENT"


static func get_encounter(encounter_id: String) -> EncounterData:
	match encounter_id.strip_edges():
		PROLOGUE_ID:
			return build_old_machine_god()
		_:
			return null


static func build_old_machine_god() -> EncounterData:
	## Prologue dialog: The Old Machine God — choices can heal, loot, or spark combat.
	var dialog := DialogEventData.new()
	dialog.id = PROLOGUE_ID
	dialog.title = "The Old Machine God"
	dialog.title_key = "EVENT_OLD_MACHINE_GOD_TITLE"
	dialog.start_node_id = "start"
	dialog.image_path = "res://assets/sprites/gods/sleeping_god.png"

	var start := DialogNodeData.new()
	start.id = "start"
	start.text_key = "EVENT_OLD_MACHINE_GOD_BODY"
	start.text = (
		"In the scrap dark, a half-buried frame still hums. "
		+ "Its optic flickers — not dead, not awake. Something waits for a command."
	)

	## Choice 1: Offer scrap / INT check → repair insight + heal, or spark backlash.
	var choice_commune := DialogChoiceData.new()
	choice_commune.text_key = "EVENT_OLD_MACHINE_GOD_CHOICE_COMMUNE"
	choice_commune.text = "Commune with the machine (INT)"
	choice_commune.stat_check = "INT"
	choice_commune.check_dc = 3
	choice_commune.success_outcome = DialogOutcomeData.make_heal(
		8, "", "EVENT_OLD_MACHINE_GOD_COMMUNE_OK"
	)
	choice_commune.success_outcome.kind = DialogOutcomeData.OutcomeKind.HEAL
	var commune_fail := DialogOutcomeData.make_damage(4, "", "EVENT_OLD_MACHINE_GOD_COMMUNE_FAIL")
	choice_commune.failure_outcome = commune_fail

	## Choice 2: Salvage parts — grant item, end.
	var choice_salvage := DialogChoiceData.new()
	choice_salvage.text_key = "EVENT_OLD_MACHINE_GOD_CHOICE_SALVAGE"
	choice_salvage.text = "Salvage what still works"
	choice_salvage.success_outcome = DialogOutcomeData.make_item(
		"BIO_GEL", "", "EVENT_OLD_MACHINE_GOD_SALVAGE_OK"
	)

	## Choice 3: Force the core awake — leads to combat with a corrupted synthet.
	var choice_force := DialogChoiceData.new()
	choice_force.text_key = "EVENT_OLD_MACHINE_GOD_CHOICE_FORCE"
	choice_force.text = "Force the core online"
	choice_force.success_outcome = DialogOutcomeData.make_combat(
		["corrupted_synthet"], "EVENT_OLD_MACHINE_GOD_FORCE_COMBAT"
	)

	## Choice 4: Walk away.
	var choice_leave := DialogChoiceData.new()
	choice_leave.text_key = "EVENT_OLD_MACHINE_GOD_CHOICE_LEAVE"
	choice_leave.text = "Leave it buried"
	choice_leave.success_outcome = DialogOutcomeData.make_end("EVENT_OLD_MACHINE_GOD_LEAVE")

	start.choices = [choice_commune, choice_salvage, choice_force, choice_leave] as Array[DialogChoiceData]
	dialog.nodes = [start] as Array[DialogNodeData]

	var encounter := EncounterData.new()
	encounter.id = PROLOGUE_ID
	encounter.title = "The Old Machine God"
	encounter.title_key = "EVENT_OLD_MACHINE_GOD_TITLE"
	encounter.type = EncounterData.EncounterType.EVENT
	encounter.encounter_payload = dialog
	encounter.payload = {"prologue": true}
	return encounter


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
		_:
			encounter.type = EncounterData.EncounterType.COMBAT_NORMAL
	var enemy_ids: Array = node.get("enemy_ids", [])
	encounter.payload = {
		"enemy_ids": enemy_ids.duplicate(),
		"faction": str(node.get("faction", "")),
		"threat_budget": int(node.get("threat_budget", 20)),
		"map_node_id": encounter.id,
	}
	## Explicit encounter_id on the node overrides catalog lookup for events.
	var catalog_id := str(node.get("encounter_id", "")).strip_edges()
	if not catalog_id.is_empty():
		var preset := get_encounter(catalog_id)
		if preset != null:
			return preset
	return encounter
