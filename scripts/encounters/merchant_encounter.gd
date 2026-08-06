class_name MerchantEncounter
extends RefCounted
## Loads EVERYMART / Bonnie dialog JSON from res://data/encounters/shop/.
## Applies Act-scaled INT bargain modifiers at runtime.

const SHOP_DIR := "res://data/encounters/shop/"
const DEFAULT_MERCHANT_ID := "bonnie"
const GOOD_MOOD_CHANCE := 0.15


static func build_dialog(act: int, force_good_mood: Variant = null) -> DialogEventData:
	var raw := _load_json_dict(DEFAULT_MERCHANT_ID)
	if raw.is_empty():
		push_warning("MerchantEncounter: missing shop dialog JSON for %s" % DEFAULT_MERCHANT_ID)
		return _fallback_dialog()

	var good_mood := false
	if force_good_mood == null:
		var chance := float(raw.get("good_mood_chance", GOOD_MOOD_CHANCE))
		good_mood = randf() < chance
	else:
		good_mood = bool(force_good_mood)

	if good_mood:
		var mood_id := str(raw.get("good_mood_id", "bonnie_good_mood")).strip_edges()
		var mood_raw := _load_json_dict(mood_id)
		if not mood_raw.is_empty():
			raw = mood_raw
		else:
			push_warning("MerchantEncounter: missing good-mood JSON %s" % mood_id)

	var dialog := _dialog_from_raw(raw)
	if dialog == null:
		return _fallback_dialog()

	if not good_mood:
		_apply_welcome_pool(dialog, raw)
	_apply_act_int_modifiers(dialog, act)
	return dialog


static func int_check_pool_bonus(act: int) -> int:
	match maxi(1, act):
		2:
			return -1
		3:
			return 1
		_:
			return 0


static func int_check_required(act: int) -> int:
	return 2 if maxi(1, act) >= 3 else 1


static func _load_json_dict(json_id: String) -> Dictionary:
	var path := "%s%s.json" % [SHOP_DIR, json_id.strip_edges()]
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("MerchantEncounter: invalid JSON in %s" % path)
		return {}
	return parsed as Dictionary


static func _dialog_from_raw(raw: Dictionary) -> DialogEventData:
	## Reuse god/event dialog authoring parser.
	var wrapped := StartingGodRegistry._build_encounter_from_dict(raw)
	if wrapped == null or wrapped.dialog_event == null:
		return null
	var dialog := wrapped.dialog_event
	## Prefer merchant_name over god_name for display title when title_key is empty.
	if dialog.title_key.is_empty():
		dialog.title = LocalizationManager.pick_en_ru(
			str(raw.get("merchant_name", raw.get("god_name", dialog.id))),
			str(raw.get("merchant_name_ru", raw.get("god_name_ru", ""))),
			dialog.title
		)
	return dialog


static func _apply_welcome_pool(dialog: DialogEventData, raw: Dictionary) -> void:
	var pool_raw: Variant = raw.get("welcome_pool", [])
	if typeof(pool_raw) != TYPE_ARRAY:
		return
	var pool: Array = pool_raw
	if pool.is_empty():
		return
	var pick: Variant = pool[randi() % pool.size()]
	if typeof(pick) != TYPE_DICTIONARY:
		return
	var entry: Dictionary = pick
	var start := dialog.get_node("start")
	if start == null:
		return
	var narrator_en := str(entry.get("narrator_text_en", "")).strip_edges()
	var narrator_ru := str(entry.get("narrator_text_ru", entry.get("narrator_text", ""))).strip_edges()
	if not narrator_en.is_empty():
		start.narrator_text_en = narrator_en
	if not narrator_ru.is_empty():
		start.narrator_text_ru = narrator_ru
	var speech_en := str(entry.get("speech_text_en", "")).strip_edges()
	var speech_ru := str(entry.get("speech_text_ru", entry.get("speech_text", ""))).strip_edges()
	if not speech_en.is_empty():
		start.speech_text_en = speech_en
	if not speech_ru.is_empty():
		start.speech_text_ru = speech_ru


static func _apply_act_int_modifiers(dialog: DialogEventData, act: int) -> void:
	if dialog == null:
		return
	var bonus := int_check_pool_bonus(act)
	var required := int_check_required(act)
	for node: DialogNodeData in dialog.nodes:
		if node == null:
			continue
		for choice: DialogChoiceData in node.choices:
			if choice == null:
				continue
			if choice.stat_check.strip_edges().to_upper() != "INT":
				continue
			choice.stat_pool_bonus = bonus
			choice.check_dc = required


static func _fallback_dialog() -> DialogEventData:
	## Minimal hardcoded tree if JSON is missing (keeps SHOP encounters playable).
	var dialog := DialogEventData.new()
	dialog.id = "bonnie_fallback"
	dialog.title_key = "KEY_MERCHANT_TITLE"
	dialog.start_node_id = "start"
	var node := DialogNodeData.new()
	node.id = "start"
	node.speech_text_en = "Bonnie shrugs. The booth is still open."
	node.speech_text_ru = "Бонни пожимает плечами. Ларёк всё ещё открыт."
	var trade := DialogChoiceData.new()
	trade.text_key = "KEY_MERCHANT_CHOICE_TRADE"
	trade.success_outcome = DialogOutcomeData.make_shop(ShopManager.PRICE_LIST)
	var leave := DialogChoiceData.new()
	leave.text_key = "KEY_MERCHANT_CHOICE_LEAVE"
	leave.success_outcome = DialogOutcomeData.make_end("KEY_STATUS_SHOP")
	node.choices = [trade, leave]
	dialog.nodes = [node]
	return dialog
