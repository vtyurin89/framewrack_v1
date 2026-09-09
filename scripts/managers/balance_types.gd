class_name BalanceTypes
extends RefCounted
## Shared semantic reward / penalty tiers for narrative systems.

enum Tier {
	NONE,
	TRIVIAL,
	MINOR,
	MEDIUM,
	MAJOR,
	COLOSSAL,
}


static func string_to_tier(tier_str: String) -> Tier:
	match tier_str.strip_edges().to_upper():
		"TRIVIAL":
			return Tier.TRIVIAL
		"MINOR":
			return Tier.MINOR
		"MEDIUM":
			return Tier.MEDIUM
		"MAJOR":
			return Tier.MAJOR
		"COLOSSAL":
			return Tier.COLOSSAL
		_:
			return Tier.NONE
