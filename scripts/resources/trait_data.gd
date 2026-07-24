class_name TraitData
extends Resource
## Modular trait attached to an ItemData.
## Adjacency rules gate whether the trait is currently active on the body grid.
##
## Note: `is_active` is runtime state. Prefer deep-duplicating ItemData (and its
## traits) per placed instance so shared .tres prototypes do not fight over it.

@export var id: String = ""
@export var trait_name_key: String = ""
@export var display_name: String = "Trait"
@export_multiline var description: String = ""

## Spatial rules that must all pass for this trait to stay active.
@export var adjacency_rules: Array[AdjacencyRuleData] = []

## Runtime: updated by evaluate_active_status() after grid layout changes.
var is_active: bool = true


func get_localized_name() -> String:
	if not trait_name_key.is_empty():
		return tr(trait_name_key)
	return display_name


func get_localized_description() -> String:
	if not trait_name_key.is_empty():
		var desc_key := trait_name_key.replace("_NAME", "_DESC")
		if desc_key != trait_name_key:
			return tr(desc_key)
	return description


func evaluate_active_status(adjacent_items: Array[ItemData]) -> bool:
	## Iterates adjacency_rules. Any failure deactivates the trait.
	for rule: AdjacencyRuleData in adjacency_rules:
		if rule == null:
			continue
		if not rule.is_condition_met(adjacent_items):
			is_active = false
			return false
	is_active = true
	return true
