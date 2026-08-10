class_name MainStoryRegistry
extends RefCounted
## Loads MAIN_STORY chapter JSON from res://data/encounters/main_story/.
## Reuses StartingGodRegistry dialog parsing; wraps result as MainStoryEncounterData.

const STORY_DIR := "res://data/encounters/main_story/"


static func load_story_encounter(story_id: String) -> MainStoryEncounterData:
	var path := "%s%s.json" % [STORY_DIR, story_id.strip_edges()]
	if not FileAccess.file_exists(path):
		push_warning("MainStoryRegistry: missing %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("MainStoryRegistry: invalid JSON in %s" % path)
		return null
	return _build_from_dict(parsed as Dictionary)


static func load_opening_for_act(act_index: int) -> MainStoryEncounterData:
	## Act 1 openings are INTRO (gods). Acts 2+ use temporary MAIN_STORY stubs.
	match maxi(1, act_index):
		2:
			return load_story_encounter("act2_opening_temp")
		3:
			return load_story_encounter("act3_opening_temp")
		_:
			return null


static func _build_from_dict(raw: Dictionary) -> MainStoryEncounterData:
	var intro := StartingGodRegistry._build_encounter_from_dict(raw)
	if intro == null:
		return null
	var encounter := MainStoryEncounterData.new()
	encounter.id = intro.id
	encounter.title = intro.title
	encounter.title_key = intro.title_key
	encounter.type = EncounterData.EncounterType.MAIN_STORY
	encounter.story_act = int(raw.get("story_act", intro.story_act))
	encounter.chapter_title = LocalizationManager.pick_en_ru(
		str(raw.get("chapter_title_en", "")),
		str(raw.get("chapter_title_ru", "")),
		str(raw.get("chapter_title", intro.chapter_title))
	)
	encounter.dialog_event = intro.dialog_event
	encounter.encounter_payload = intro.dialog_event
	encounter.payload = {
		"prologue": false,
		"main_story": true,
		"temporary_stub": bool(raw.get("temporary_stub", false)),
		"story_id": encounter.id,
		"act": encounter.story_act,
	}
	return encounter
