class_name DialogNodeData
extends Resource
## One step in a dialog event tree.

@export var id: String = ""
@export var text: String = ""
@export var text_key: String = ""
## Optional split fields (preferred for god JSON).
@export var narrator_text: String = ""
@export var speech_text: String = ""
## Bilingual overrides (resolved at display time).
@export var narrator_text_en: String = ""
@export var narrator_text_ru: String = ""
@export var speech_text_en: String = ""
@export var speech_text_ru: String = ""
@export var text_en: String = ""
@export var text_ru: String = ""
@export var choices: Array[DialogChoiceData] = []
## When true, choices whose choice_id was already attempted this dialog are disabled.
@export var disable_used_choices: bool = false

## Push-your-luck branch (Specimen-614 hub): on a fresh visit the node rolls the
## chance for the current visit index, then its implied Continue leads to the
## escape node on success or the safe node on failure.
@export var branch_chances: Array[float] = []
@export var branch_success_node: String = ""
@export var branch_failure_node: String = ""
## Per-visit narration variants (indexed by visit count; last entry repeats).
@export var narrator_variants_en: Array[String] = []
@export var narrator_variants_ru: Array[String] = []
## Random speech pool (parallel EN/RU lines, one picked per visit).
@export var speech_pool_en: Array[String] = []
@export var speech_pool_ru: Array[String] = []
## Visit indices the speech pool applies to; empty = every visit.
@export var speech_pool_visits: Array[int] = []


func has_branch() -> bool:
	return not branch_chances.is_empty()


func get_branch_chance(visit: int) -> float:
	if branch_chances.is_empty():
		return 0.0
	var idx := clampi(visit, 0, branch_chances.size() - 1)
	return clampf(branch_chances[idx], 0.0, 1.0)


func get_display_text() -> String:
	if not text_key.is_empty():
		return tr(text_key)
	var composed := compose_story_bbcode()
	if not composed.is_empty():
		return composed
	return LocalizationManager.pick_en_ru(text_en, text_ru, text)


func compose_story_bbcode() -> String:
	## Join narrator (italics) + speech with a paragraph break.
	var narrator := LocalizationManager.pick_en_ru(
		narrator_text_en, narrator_text_ru, narrator_text
	).strip_edges()
	var speech := LocalizationManager.pick_en_ru(
		speech_text_en, speech_text_ru, speech_text
	).strip_edges()
	if narrator.is_empty() and speech.is_empty():
		return LocalizationManager.pick_en_ru(text_en, text_ru, text)
	var parts: PackedStringArray = []
	if not narrator.is_empty():
		## One italic block per paragraph so design-doc blank lines stay distinct.
		if narrator.find("[i]") < 0 and narrator.find("[I]") < 0:
			var paras: PackedStringArray = narrator.split("\n\n", false)
			var italic_paras: PackedStringArray = []
			for para in paras:
				var trimmed := str(para).strip_edges()
				if not trimmed.is_empty():
					italic_paras.append("[i]%s[/i]" % trimmed)
			narrator = "\n\n".join(italic_paras)
		parts.append(narrator)
	if not speech.is_empty():
		parts.append(speech)
	return "\n\n".join(parts)
