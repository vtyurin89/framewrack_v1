class_name ActData
extends Resource
## One act/chapter of a run — loaded from data/acts.csv via ActDatabase.

@export var id: String = ""
@export var act_index: int = 1
@export var title_key: String = ""  ## Localization key (e.g. ACT_1_TITLE)
@export var location_key: String = ""  ## Localization key for map sidebar (e.g. ACT_1_LOCATION)
@export var map_depth: int = 15
@export var boss_encounter_id: String = ""
@export var encounter_pools: Array[String] = []
@export var event_pools: Array[String] = []

## Combat map generation tuning (defaults applied per act when omitted from CSV).
@export var primary_faction: String = "human"
@export var normal_threat_budget: int = 18
@export var elite_threat_budget: int = 32

## Resolved boss node payload for MapGenerator (built from boss_encounter_id).
@export var boss_encounter_data: EncounterData


func get_localized_title() -> String:
	if not title_key.is_empty():
		return tr(title_key)
	return "Act %d" % act_index


func get_localized_location() -> String:
	if not location_key.is_empty():
		return tr(location_key)
	return get_localized_title()


func get_map_layer_count() -> int:
	return maxi(map_depth, 5)


## Back-compat alias used by MapGenerator and older call sites.
var layer_count: int:
	get:
		return get_map_layer_count()
	set(value):
		map_depth = maxi(value, 5)
