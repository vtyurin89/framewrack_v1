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


func get_stat_tag() -> String:
	return stat_check.strip_edges().to_upper()


## effective_stat already includes pool bonus; drives dice count preview.
func format_stat_check_label(effective_stat: int) -> String:
	var tag := get_stat_tag()
	var action := _strip_stat_check_prefix(get_display_text())
	var dice := 1
	if StatCheckManager != null:
		dice = StatCheckManager.preview_dice_count(maxi(1, effective_stat))
	else:
		dice = maxi(1, effective_stat)
	var need := get_required_successes()
	var need_key := (
		"KEY_STAT_CHECK_NEED_ONE" if need == 1 else "KEY_STAT_CHECK_NEED_MANY"
	)
	var need_str := tr(need_key) % need
	return tr("KEY_STAT_CHECK_CHOICE_FMT") % [tag, action, tag, dice, need_str]


func _strip_stat_check_prefix(raw: String) -> String:
	var t := raw.strip_edges()
	var re := RegEx.new()
	## [STR Check], [INT check], [Проверка СИЛ], [Bargain — …], [Intelligence check]
	var patterns: PackedStringArray = [
		"^\\[[A-Za-z]{2,4}\\s*[Cc]heck\\]\\s*",
		"^\\[Проверка\\s+[^\\]]+\\]\\s*",
		"^\\[Bargain[^\\]]*\\]\\s*",
		"^\\[Поторговаться[^\\]]*\\]\\s*",
		"^\\[Intelligence check\\]\\s*",
		"^\\[Проверка интеллекта\\]\\s*",
	]
	for pattern in patterns:
		if re.compile(pattern) != OK:
			continue
		var m := re.search(t)
		if m != null and m.get_start() == 0:
			t = t.substr(m.get_end()).strip_edges()
			break
	if re.compile("\\s*\\((INT|STR|AGI|END|LCK|HUM|ИНТ|СИЛ|ЛОВ|ВЫН|УДЧ|ЧЕЛ)\\)\\s*$") == OK:
		var trail := re.search(t)
		if trail != null:
			t = t.substr(0, trail.get_start()).strip_edges()
	return t if not t.is_empty() else raw.strip_edges()


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
