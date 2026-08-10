class_name EncounterData
extends Resource
## Blueprint for a map / prologue encounter (combat, event, shop, rest, etc.).

enum EncounterType {
	COMBAT_NORMAL,
	COMBAT_ELITE,
	COMBAT_BOSS,
	EVENT,
	INTRO,
	MAIN_STORY,
	CHEST,
	SHOP,
	REST_SITE,
	STAIRS,
	UNKNOWN,
}

@export var id: String = ""
@export var title: String = ""
@export var title_key: String = ""
@export var icon: Texture2D
@export var type: EncounterType = EncounterType.UNKNOWN
## Typed payload (DialogEventData, etc.) - preferred for structured content.
@export var encounter_payload: Resource
## Loose parameters: enemy_ids, faction, threat_budget, item_ids, heal_amount, ...
@export var payload: Dictionary = {}


func get_display_title() -> String:
	if not title_key.is_empty():
		return tr(title_key)
	if not title.is_empty():
		return title
	return id


func is_combat() -> bool:
	return type in [
		EncounterType.COMBAT_NORMAL,
		EncounterType.COMBAT_ELITE,
		EncounterType.COMBAT_BOSS,
	]


func get_enemy_ids() -> Array[String]:
	var result: Array[String] = []
	var raw: Variant = payload.get("enemy_ids", [])
	if raw is Array:
		for eid in raw:
			var s := str(eid).strip_edges()
			if not s.is_empty():
				result.append(s)
	return result


func get_dialog_event() -> DialogEventData:
	if encounter_payload is DialogEventData:
		return encounter_payload as DialogEventData
	return null


func duplicate_resolved() -> EncounterData:
	return duplicate(true) as EncounterData