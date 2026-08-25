class_name MerchantDialoguePool
extends RefCounted
## Random picker for Bonnie's standard (non–Good Mood) dialogue encounters.

const SHOP_DIR := "res://data/encounters/shop/"
## Encounter #1 (`bonnie.json`), Encounter #3 (`bonnie_03.json`), …
const STANDARD_ENCOUNTER_IDS: Array[String] = [
	"bonnie",
	"bonnie_03",
]
const GOOD_MOOD_ID := "bonnie_good_mood"
const GOOD_MOOD_CHANCE := 0.15
## Shared meta read from Encounter #1 JSON when present.
const META_ENCOUNTER_ID := "bonnie"


static func list_standard_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in STANDARD_ENCOUNTER_IDS:
		var cleaned := str(id).strip_edges()
		if cleaned.is_empty():
			continue
		if FileAccess.file_exists("%s%s.json" % [SHOP_DIR, cleaned]):
			ids.append(cleaned)
	return ids


static func pick_standard_id() -> String:
	var ids := list_standard_ids()
	if ids.is_empty():
		return META_ENCOUNTER_ID
	return ids[randi() % ids.size()]


static func get_good_mood_id(meta: Dictionary = {}) -> String:
	var from_meta := str(meta.get("good_mood_id", "")).strip_edges()
	if not from_meta.is_empty():
		return from_meta
	return GOOD_MOOD_ID


static func get_good_mood_chance(meta: Dictionary = {}) -> float:
	if meta.has("good_mood_chance"):
		return float(meta.get("good_mood_chance", GOOD_MOOD_CHANCE))
	return GOOD_MOOD_CHANCE
