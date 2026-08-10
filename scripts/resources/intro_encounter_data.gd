class_name IntroEncounterData
extends EventEncounterData
## Opening god / intro beat (Act 1 start and prologue). Dialog logic matches MAIN_STORY.

@export var story_act: int = 1
@export var chapter_title: String = ""


func _init() -> void:
	type = EncounterType.INTRO
