class_name CurrencyRewardResolver
extends RefCounted
## Neuro-Chip rewards: Act-scaled narrative tiers + combat (base + layer×2).
## Returns pre-grant base amounts; GameManager.add_chips applies chip_bonus_multiplier.

## Act-based scaling for dialogue / event chip rewards: [Act][Tier] → chips.
const ENCOUNTER_CHIPS_TABLE: Dictionary = {
	1: {
		BalanceTypes.Tier.TRIVIAL: 15,
		BalanceTypes.Tier.MINOR: 30,
		BalanceTypes.Tier.MEDIUM: 60,
		BalanceTypes.Tier.MAJOR: 120,
		BalanceTypes.Tier.COLOSSAL: 200,
	},
	2: {
		BalanceTypes.Tier.TRIVIAL: 25,
		BalanceTypes.Tier.MINOR: 50,
		BalanceTypes.Tier.MEDIUM: 100,
		BalanceTypes.Tier.MAJOR: 180,
		BalanceTypes.Tier.COLOSSAL: 300,
	},
	3: {
		BalanceTypes.Tier.TRIVIAL: 40,
		BalanceTypes.Tier.MINOR: 80,
		BalanceTypes.Tier.MEDIUM: 160,
		BalanceTypes.Tier.MAJOR: 280,
		BalanceTypes.Tier.COLOSSAL: 450,
	},
}

const COMBAT_BASE_REWARD: Dictionary = {
	"STANDARD": 20,
	"NORMAL": 20,
	"ELITE": 50,
	"BOSS": 120,
}

const CHIPS_PER_LAYER := 2


## Narrative / encounter chip rewards (before GameManager gain modifiers).
static func resolve_encounter_chips(
	tier: BalanceTypes.Tier = BalanceTypes.Tier.NONE,
	act: int = 1,
	raw_amount: int = 0
) -> int:
	var base_chips := 0
	if raw_amount > 0:
		base_chips = raw_amount
	elif tier != BalanceTypes.Tier.NONE:
		var clamped_act: int = clampi(act, 1, 3)
		var act_dict: Dictionary = ENCOUNTER_CHIPS_TABLE.get(
			clamped_act, ENCOUNTER_CHIPS_TABLE[1]
		)
		base_chips = int(act_dict.get(tier, 30))
	return maxi(0, base_chips)


## Combat victory currency base: base(type) + layer × 2 (before gain modifiers).
static func resolve_combat_chips(encounter_type: String, layer: int) -> int:
	var kind := encounter_type.strip_edges().to_upper()
	match kind:
		"COMBAT_ELITE":
			kind = "ELITE"
		"COMBAT_BOSS":
			kind = "BOSS"
		"COMBAT_NORMAL", "":
			kind = "STANDARD"
	var base_val: int = int(COMBAT_BASE_REWARD.get(kind, COMBAT_BASE_REWARD["STANDARD"]))
	return maxi(0, base_val + maxi(layer, 0) * CHIPS_PER_LAYER)
