class_name StatCheckBoostDefinition
extends RefCounted
## One source of extra dice / guaranteed success for dialog stat checks.

enum Effect {
	## Adds ap_value "AP units" → +ap_value * 2 d6 via StatCheckManager.
	DICE_AP,
	## Forces a guaranteed success for the next check.
	GUARANTEE_SUCCESS,
}

enum SourceKind {
	ITEM,
	ABILITY,
}

var id: String = ""
var source_kind: SourceKind = SourceKind.ITEM
## Inventory item id when source_kind == ITEM.
var item_id: String = ""
## Future: ability / trait id when source_kind == ABILITY.
var ability_id: String = ""
var label_key: String = ""
var effect: Effect = Effect.DICE_AP
## AP-equivalent boost for DICE_AP (each AP → +2d6).
var ap_value: int = 0
## Neuron Amplifier-style: pay HP instead of consuming a charge.
var costs_hp: bool = false
## Only one staging of this boost per prepare session.
var once_per_check: bool = true


static func make_item_dice(
	boost_id: String,
	item_id: String,
	label_key: String,
	ap_value: int,
	costs_hp: bool = false
) -> StatCheckBoostDefinition:
	var def := StatCheckBoostDefinition.new()
	def.id = boost_id.strip_edges().to_upper()
	def.source_kind = SourceKind.ITEM
	def.item_id = item_id.strip_edges().to_upper()
	def.label_key = label_key
	def.effect = Effect.DICE_AP
	def.ap_value = maxi(0, ap_value)
	def.costs_hp = costs_hp
	return def


static func make_item_guarantee(
	boost_id: String,
	item_id: String,
	label_key: String
) -> StatCheckBoostDefinition:
	var def := StatCheckBoostDefinition.new()
	def.id = boost_id.strip_edges().to_upper()
	def.source_kind = SourceKind.ITEM
	def.item_id = item_id.strip_edges().to_upper()
	def.label_key = label_key
	def.effect = Effect.GUARANTEE_SUCCESS
	return def
