class_name StatCheckBoostCatalog
extends RefCounted
## Authoritative list of items/abilities that can add dice to a dialog stat check.
## Dialog prepare UI and StatCheckManager consume logic should read from here.

const ID_NEURO := "NEURO_STIMULATOR"
const ID_SYNAPSE := "SYNAPSE_BOOSTER"
const ID_NEURON_AMP := "NEURON_AMPLIFIER"

const AP_NEURO := 2
const AP_NEURON_AMP := 1


static func all_definitions() -> Array[StatCheckBoostDefinition]:
	var out: Array[StatCheckBoostDefinition] = []
	out.append(
		StatCheckBoostDefinition.make_item_dice(
			ID_NEURO, "NEURO_STIMULATOR", "KEY_STAT_CHECK_USE_NEURO", AP_NEURO
		)
	)
	out.append(
		StatCheckBoostDefinition.make_item_guarantee(
			ID_SYNAPSE, "SYNAPSE_BOOSTER", "KEY_STAT_CHECK_USE_SYNAPSE"
		)
	)
	out.append(
		StatCheckBoostDefinition.make_item_dice(
			ID_NEURON_AMP,
			"NEURON_AMPLIFIER",
			"KEY_STAT_CHECK_USE_NEURON",
			AP_NEURON_AMP,
			true
		)
	)
	return out


static func find_by_id(boost_id: String) -> StatCheckBoostDefinition:
	var needle := boost_id.strip_edges().to_upper()
	if needle.is_empty():
		return null
	for def: StatCheckBoostDefinition in all_definitions():
		if def != null and def.id == needle:
			return def
	return null


static func list_offerable(
	inventory: InventoryController,
	staged_ids: Array[String]
) -> Array[StatCheckBoostDefinition]:
	## Boosts the player can still stage in the prepare phase.
	var staged: Dictionary = {}
	for sid in staged_ids:
		staged[sid.strip_edges().to_upper()] = true
	var out: Array[StatCheckBoostDefinition] = []
	for def: StatCheckBoostDefinition in all_definitions():
		if def == null:
			continue
		if def.once_per_check and staged.has(def.id):
			continue
		if not is_present(def, inventory):
			continue
		out.append(def)
	return out


static func is_present(def: StatCheckBoostDefinition, inventory: InventoryController) -> bool:
	if def == null or StatCheckManager == null:
		return false
	match def.source_kind:
		StatCheckBoostDefinition.SourceKind.ITEM:
			return StatCheckManager.inventory_has_item(inventory, def.item_id)
		StatCheckBoostDefinition.SourceKind.ABILITY:
			## Hook for future ability/trait-based dice boosts.
			return false
		_:
			return false


static func is_safe_to_stage(def: StatCheckBoostDefinition, inventory: InventoryController) -> bool:
	if def == null:
		return false
	if not is_present(def, inventory):
		return false
	if def.costs_hp:
		return inventory != null and inventory.can_safely_use_neuron_amplifier()
	return true


static func format_choice_label(
	def: StatCheckBoostDefinition,
	inventory: InventoryController
) -> String:
	if def == null:
		return ""
	var key := def.label_key
	if key.is_empty():
		return def.id
	var translated := TranslationServer.translate(key)
	if def.costs_hp:
		var cost := 4
		if inventory != null:
			cost = inventory.get_neuron_amplifier_hp_cost()
		return translated % cost
	return translated


static func ap_bonus_from_staged(staged_ids: Array[String]) -> int:
	var total := 0
	for sid in staged_ids:
		var def := find_by_id(sid)
		if def == null:
			continue
		if def.effect == StatCheckBoostDefinition.Effect.DICE_AP:
			total += maxi(0, def.ap_value)
	return total


static func has_guarantee_staged(staged_ids: Array[String]) -> bool:
	for sid in staged_ids:
		var def := find_by_id(sid)
		if def != null and def.effect == StatCheckBoostDefinition.Effect.GUARANTEE_SUCCESS:
			return true
	return false


static func preview_extra_dice(staged_ids: Array[String]) -> int:
	return ap_bonus_from_staged(staged_ids) * 2


static func commit_staged(
	staged_ids: Array[String],
	inventory: InventoryController
) -> int:
	## Consume staged boosts. Returns surviving AP-equivalent dice boost.
	var ap := 0
	for sid in staged_ids:
		var def := find_by_id(sid)
		if def == null:
			continue
		if not _consume(def, inventory):
			continue
		if def.effect == StatCheckBoostDefinition.Effect.DICE_AP:
			ap += maxi(0, def.ap_value)
	return ap


static func _consume(def: StatCheckBoostDefinition, inventory: InventoryController) -> bool:
	if def == null or StatCheckManager == null:
		return false
	match def.source_kind:
		StatCheckBoostDefinition.SourceKind.ITEM:
			return _consume_item(def, inventory)
		StatCheckBoostDefinition.SourceKind.ABILITY:
			return false
		_:
			return false


static func _consume_item(def: StatCheckBoostDefinition, inventory: InventoryController) -> bool:
	match def.effect:
		StatCheckBoostDefinition.Effect.GUARANTEE_SUCCESS:
			if not StatCheckManager.consume_inventory_item(inventory, def.item_id):
				return false
			StatCheckManager.set_guaranteed_success(true, false)
			return true
		StatCheckBoostDefinition.Effect.DICE_AP:
			if def.costs_hp:
				if inventory == null:
					return false
				if not inventory.can_safely_use_neuron_amplifier():
					return false
				return inventory.pay_neuron_amplifier_hp(false)
			return StatCheckManager.consume_inventory_item(inventory, def.item_id)
		_:
			return false
