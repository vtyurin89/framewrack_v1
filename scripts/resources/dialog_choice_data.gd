class_name DialogChoiceData
extends Resource
## A single player choice on a dialog node.

@export var text: String = ""
@export var text_key: String = ""
@export var text_en: String = ""
@export var text_ru: String = ""
## Optional stat gate: "" | STR | AGI | END | INT | LCK
@export var stat_check: String = ""
## Required number of 5–6 successes on the d6 pool (StatCheckManager).
@export var check_dc: int = 0
## Hidden pool modifier (e.g. Act 2 INT check uses INT - 1). Applied as max(1, stat + bonus).
@export var stat_pool_bonus: int = 0
## Hide/disable choice unless the player has at least this many Neuro-Chips.
@export var require_chips: int = 0
## Spend this many Neuro-Chips when the choice is taken (after require check).
@export var cost_chips: int = 0
## Hide/disable choice unless this item id is present in the Body Grid.
@export var require_item_id: String = ""
@export var success_outcome: DialogOutcomeData
@export var failure_outcome: DialogOutcomeData


func get_display_text() -> String:
	if not text_key.is_empty():
		return tr(text_key)
	return LocalizationManager.pick_en_ru(text_en, text_ru, text)


func has_stat_check() -> bool:
	return not stat_check.strip_edges().is_empty()


func get_required_successes() -> int:
	return maxi(1, check_dc)


func is_available(inventory: InventoryController = null) -> bool:
	if require_chips > 0:
		var chips := 0
		if GameManager != null:
			chips = GameManager.get_chips()
		if chips < require_chips:
			return false
	var item_need := require_item_id.strip_edges().to_upper()
	if not item_need.is_empty():
		if item_need == "FAKE_VIP_CARD":
			item_need = "FAKE_VIP_CARD_GOLD_PARTNER"
		if inventory == null or not inventory.has_item(item_need):
			return false
	return true
