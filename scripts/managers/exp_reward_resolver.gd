class_name ExpRewardResolver
extends RefCounted
## Resolves EXP for narrative tiers / percents and combat enemy sums.
## Applies optional player-wide EXP gain modifiers before grant.

## Fraction of current level-step capacity (XP needed for N → N+1).
const TIER_PERCENT_MAP: Dictionary = {
	BalanceTypes.Tier.TRIVIAL: 0.08,
	BalanceTypes.Tier.MINOR: 0.15,
	BalanceTypes.Tier.MEDIUM: 0.25,
	BalanceTypes.Tier.MAJOR: 0.40,
	BalanceTypes.Tier.COLOSSAL: 0.60,
}


## Resolves final EXP value.
## - tier: semantic % of current level capacity
## - raw_amount: explicit EXP (enemy sums / legacy JSON)
## - custom_percent: explicit fraction of level capacity (e.g. 0.40)
static func resolve_exp(
	tier: BalanceTypes.Tier = BalanceTypes.Tier.NONE,
	raw_amount: int = 0,
	custom_percent: float = 0.0,
	player_stats: PlayerStats = null
) -> int:
	var level_capacity := _level_capacity(player_stats)
	var base_exp: float = 0.0

	if custom_percent > 0.0:
		base_exp = float(level_capacity) * custom_percent
	elif tier != BalanceTypes.Tier.NONE:
		var pct: float = float(TIER_PERCENT_MAP.get(tier, 0.15))
		base_exp = float(level_capacity) * pct
	else:
		base_exp = float(maxi(0, raw_amount))

	if base_exp <= 0.0:
		return 0

	var exp_modifier: float = 1.0 + _exp_gain_modifier(player_stats)
	return int(round(maxi(0.0, base_exp * exp_modifier)))


## Sum combat EXP from EnemyData blueprints or EnemyInstance-like objects.
static func resolve_combat_exp(
	enemies: Array, player_stats: PlayerStats = null
) -> int:
	var total_raw_exp := 0
	for enemy in enemies:
		var data := _enemy_data_from(enemy)
		if data == null:
			continue
		if data.exp_reward <= 0:
			continue
		if "summoned_creature" in data.trait_ids:
			continue
		total_raw_exp += maxi(data.exp_reward, 0)
	return resolve_exp(BalanceTypes.Tier.NONE, total_raw_exp, 0.0, player_stats)


static func _level_capacity(player_stats: PlayerStats) -> int:
	if player_stats != null and player_stats.has_method("get_current_level_capacity"):
		return maxi(1, int(player_stats.get_current_level_capacity()))
	## Fallback: level-1 step from PlayerStats defaults.
	return 30


static func _exp_gain_modifier(_player_stats: PlayerStats) -> float:
	## Hook for relics / implants. No global EXP modifier exists yet.
	if _player_stats != null and _player_stats.has_method("get_exp_gain_modifier"):
		return float(_player_stats.get_exp_gain_modifier())
	return 0.0


static func _enemy_data_from(enemy: Variant) -> EnemyData:
	if enemy is EnemyData:
		return enemy as EnemyData
	if enemy == null:
		return null
	if typeof(enemy) == TYPE_OBJECT and enemy.get("data") is EnemyData:
		return enemy.data as EnemyData
	return null
