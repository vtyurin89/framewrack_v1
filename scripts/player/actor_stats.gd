class_name ActorStats
extends RefCounted
## Shared combat attributes for player and enemy entities.

var strength: int = 1
var agility: int = 1
var endurance: int = 1
var intelligence: int = 1
var luck: int = 1


func get_crit_chance() -> float:
	## At LCK = 1, crit chance is 0%.
	return maxf(0.0, float(luck - 1) * 0.05)


func get_max_hp(base_hp: int = 30) -> int:
	return base_hp + (endurance * 5)


func reset_combat_stats(
	p_strength: int = 1,
	p_agility: int = 1,
	p_endurance: int = 1,
	p_intelligence: int = 1,
	p_luck: int = 1
) -> void:
	strength = p_strength
	agility = p_agility
	endurance = p_endurance
	intelligence = p_intelligence
	luck = p_luck
