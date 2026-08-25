class_name MainStoryEncounterData
extends EventEncounterData
## Chapter / act story beats (not starting-god INTRO encounters).

@export var story_act: int = 1
@export var chapter_title: String = ""


func _init() -> void:
	type = EncounterType.MAIN_STORY
