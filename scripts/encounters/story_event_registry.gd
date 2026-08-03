class_name StoryEventRegistry
extends RefCounted
## Loads map story-event dialogs from res://data/encounters/events/.
## Reuses StartingGodRegistry parsing so authoring matches god JSON.

const EVENTS_DIR := "res://data/encounters/events/"


static func load_event_encounter(event_id: String) -> EventEncounterData:
	var path := "%s%s.json" % [EVENTS_DIR, event_id.strip_edges()]
	if not FileAccess.file_exists(path):
		push_warning("StoryEventRegistry: missing %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("StoryEventRegistry: invalid JSON in %s" % path)
		return null
	return _build_encounter_from_dict(parsed as Dictionary)


static func _build_encounter_from_dict(raw: Dictionary) -> EventEncounterData:
	## Delegate dialog tree + rewards to the god registry parser, then wrap as EVENT.
	var main_story := StartingGodRegistry._build_encounter_from_dict(raw)
	if main_story == null:
		return null
	var encounter := EventEncounterData.new()
	encounter.id = main_story.id
	encounter.title = main_story.title
	encounter.title_key = main_story.title_key
	encounter.type = EncounterData.EncounterType.EVENT
	encounter.dialog_event = main_story.dialog_event
	encounter.encounter_payload = main_story.dialog_event
	encounter.payload = {
		"story_event": true,
		"event_id": encounter.id,
	}
	return encounter
