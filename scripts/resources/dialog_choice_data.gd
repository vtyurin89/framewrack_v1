class_name DialogChoiceData
extends Resource
## A single player choice on a dialog node.

@export var text: String = ""
@export var text_key: String = ""
@export var text_en: String = ""
@export var text_ru: String = ""
## Optional stat gate: "" | STR | AGI | END | INT | LCK
@export var stat_check: String = ""
@export var check_dc: int = 0
@export var success_outcome: DialogOutcomeData
@export var failure_outcome: DialogOutcomeData


func get_display_text() -> String:
	if not text_key.is_empty():
		return tr(text_key)
	return LocalizationManager.pick_en_ru(text_en, text_ru, text)


func has_stat_check() -> bool:
	return not stat_check.strip_edges().is_empty() and check_dc > 0
