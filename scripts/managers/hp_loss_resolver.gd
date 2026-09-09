class_name HpLossResolver
extends RefCounted
## HP penalties for text / dialogue encounters (not combat ability damage).
## Prefers % of Max HP; supports flat overrides; non-lethal by default.

const TIER_PERCENT_MAP: Dictionary = {
	BalanceTypes.Tier.TRIVIAL: 0.05,
	BalanceTypes.Tier.MINOR: 0.10,
	BalanceTypes.Tier.MEDIUM: 0.20,
	BalanceTypes.Tier.MAJOR: 0.35,
	BalanceTypes.Tier.COLOSSAL: 0.50,
}


## Resolves direct HP penalty for narrative encounters.
## Priority: raw_amount > custom_percent > tier.
## When allow_lethal is false, clamps so at least 1 HP remains.
static func resolve_hp_loss(
	tier: BalanceTypes.Tier = BalanceTypes.Tier.NONE,
	raw_amount: int = 0,
	custom_percent: float = 0.0,
	allow_lethal: bool = false,
	max_hp: int = 0,
	current_hp: int = 0
) -> int:
	var calculated_damage := 0

	if raw_amount > 0:
		calculated_damage = raw_amount
	elif custom_percent > 0.0:
		calculated_damage = int(ceil(float(maxi(1, max_hp)) * custom_percent))
	elif tier != BalanceTypes.Tier.NONE:
		var pct: float = float(TIER_PERCENT_MAP.get(tier, 0.10))
		calculated_damage = int(ceil(float(maxi(1, max_hp)) * pct))

	if calculated_damage <= 0:
		return 0

	calculated_damage = maxi(1, calculated_damage)

	if not allow_lethal:
		calculated_damage = mini(calculated_damage, maxi(0, current_hp - 1))

	return calculated_damage


static func resolve_hp_loss_for_inventory(
	inventory: InventoryController,
	tier: BalanceTypes.Tier = BalanceTypes.Tier.NONE,
	raw_amount: int = 0,
	custom_percent: float = 0.0,
	allow_lethal: bool = false
) -> int:
	var max_hp := 1
	var current_hp := 1
	if inventory != null:
		max_hp = maxi(1, inventory.max_hp)
		current_hp = maxi(0, inventory.current_hp)
	return resolve_hp_loss(
		tier, raw_amount, custom_percent, allow_lethal, max_hp, current_hp
	)
