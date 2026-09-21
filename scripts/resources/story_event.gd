class_name StoryEvent
extends Resource
## One entry in an act story-event queue (faction-tagged narrative beat).

enum Faction {
	HUMAN,
	ROBOT,
	CHIMERA,
	GENERIC,
}

@export var id: String = ""
@export var faction: Faction = Faction.HUMAN
@export var encounter_json_id: String = ""
@export var one_shot: bool = false
## Empty = all acts. Otherwise only these act indices may roll the event.
@export var allowed_acts: Array[int] = []


func get_faction_key() -> String:
	match faction:
		Faction.ROBOT:
			return "robot"
		Faction.CHIMERA:
			return "chimera"
		Faction.GENERIC:
			return "generic"
		_:
			return "human"


func is_allowed_for_act(act_index: int) -> bool:
	if allowed_acts.is_empty():
		return true
	var act := maxi(act_index, 1)
	return allowed_acts.has(act)
