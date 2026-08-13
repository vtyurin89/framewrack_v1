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


static func parse_flat_block(ability: EnemyAbility) -> int:
	## Reads flat Block from effect_params: "block|6" / "shield|7" (no agility).
	if ability == null:
		return 0
	var csv := ability.get_effect_param_list()
	var amount := 0
	var i := 0
	while i < csv.size():
		var token := str(csv[i]).strip_edges().to_lower()
		if token in ["block", "guard", "shield"] and i + 1 < csv.size() and str(csv[i + 1]).is_valid_int():
			amount = maxi(amount, int(csv[i + 1]))
			i += 2
			continue
		if token.begins_with("block:") or token.begins_with("shield:"):
			var parts := token.split(":")
			if parts.size() >= 2 and parts[1].is_valid_int():
				amount = maxi(amount, int(parts[1]))
		i += 1
	return amount
