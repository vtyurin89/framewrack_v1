class_name StoryEvent
extends Resource
## One entry in an act story-event queue (faction-tagged narrative beat).

enum Faction {
	HUMAN,
	ROBOT,
	CHIMERA,
}

@export var id: String = ""
@export var faction: Faction = Faction.HUMAN
@export var encounter_json_id: String = ""
@export var one_shot: bool = false


func get_faction_key() -> String:
	match faction:
		Faction.ROBOT:
			return "robot"
		Faction.CHIMERA:
			return "chimera"
		_:
			return "human"
