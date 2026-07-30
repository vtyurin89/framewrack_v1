class_name MainStoryEncounterData
extends EventEncounterData
## Main story encounter payload for god/chapter narrative beats.

@export var story_act: int = 1
@export var chapter_title: String = ""


func _init() -> void:
	type = EncounterType.MAIN_STORY
