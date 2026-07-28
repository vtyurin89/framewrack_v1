class_name AbilityEffect
extends Resource
## Base modular effect applied by EnemyAbilityExecutor.
## `target` is typically the CombatManager Node; `params` starts with [ability, enemy_index, ...csv params].

func apply(_caster: EnemyInstance, _target: Node, _params: Array) -> void:
	## Override in concrete effect handlers.
	pass


static func ability_from_params(params: Array) -> EnemyAbility:
	if params.is_empty():
		return null
	return params[0] as EnemyAbility


static func enemy_index_from_params(params: Array) -> int:
	if params.size() < 2:
		return -1
	return int(params[1])


static func csv_params(params: Array) -> Array:
	if params.size() <= 2:
		return []
	return params.slice(2)
