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
