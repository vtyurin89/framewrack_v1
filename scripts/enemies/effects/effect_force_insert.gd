class_name EffectForceInsert
extends AbilityEffect
## Forces a harmful item into the player's Body Grid via ForcedItemScreen.


func apply(caster: EnemyInstance, target: Node, params: Array) -> void:
	if target == null or not target.has_method("request_forced_item_insertion"):
		return
	var csv := AbilityEffect.csv_params(params)
	var item_id := "SLIMY_PARASITE"
	if csv.size() >= 1 and str(csv[0]).strip_edges() != "":
		item_id = str(csv[0]).strip_edges().to_upper()
	## Skip if the parasite is already lodged in the frame.
	if target.has_method("has_item_in_grid") and bool(target.call("has_item_in_grid", item_id)):
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_PARASITE_ALREADY") % [
				caster.get_localized_name() if caster != null else "?",
			]
		)
		return
	if caster != null:
		EventBus.combat_log_message.emit(
			tr("KEY_LOG_PARASITE_INJECT") % caster.get_localized_name()
		)
	target.call("request_forced_item_insertion", item_id)
