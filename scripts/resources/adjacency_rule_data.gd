class_name AdjacencyRuleData
extends Resource
## Spatial constraint evaluated against orthogonally adjacent grid neighbours.

enum RuleType {
	MUST_TOUCH,      ## At least one neighbour must match the filters.
	MUST_NOT_TOUCH,  ## No neighbour may match the filters.
}

@export var rule_type: RuleType = RuleType.MUST_TOUCH

## Optional filters — empty/null means "any item".
@export var target_item_type: ItemTypeData
@export var target_specific_item: ItemData
@export var target_rarity: ItemRarityData


func is_condition_met(adjacent_items: Array[ItemData]) -> bool:
	## Returns true when this spatial rule is satisfied by the neighbour set.
	var matched := false
	for item: ItemData in adjacent_items:
		if item == null:
			continue
		if _matches_filters(item):
			matched = true
			break

	match rule_type:
		RuleType.MUST_TOUCH:
			return matched
		RuleType.MUST_NOT_TOUCH:
			return not matched
		_:
			return false


func _matches_filters(item: ItemData) -> bool:
	## All set filters must pass. Unset filters are ignored ("any").
	if target_specific_item != null and not _is_same_item(item, target_specific_item):
		return false
	if target_item_type != null and not _same_type(item.item_type, target_item_type):
		return false
	if target_rarity != null and not _same_rarity(item.rarity, target_rarity):
		return false
	return true


func _is_same_item(a: ItemData, b: ItemData) -> bool:
	if a == b:
		return true
	if a == null or b == null:
		return false
	if a.id.is_empty() or b.id.is_empty():
		return false
	return a.id == b.id


func _same_type(a: ItemTypeData, b: ItemTypeData) -> bool:
	if a == null or b == null:
		return false
	if a == b:
		return true
	if a.id.is_empty() or b.id.is_empty():
		return false
	return a.id == b.id


func _same_rarity(a: ItemRarityData, b: ItemRarityData) -> bool:
	if a == null or b == null:
		return false
	if a == b:
		return true
	if a.id.is_empty() or b.id.is_empty():
		return false
	return a.id == b.id
