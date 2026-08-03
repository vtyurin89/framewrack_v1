class_name ItemRarityData
extends Resource
## Rarity tier used by adjacency rules and loot / UI tinting.
## Framewrack uses exactly 3 tiers: COMMON / UNCOMMON / RARE.

enum Tier {
	COMMON,
	UNCOMMON,
	RARE,
}

const COLOR_COMMON := Color("#BDC3C7")
const COLOR_UNCOMMON := Color("#3498DB")
const COLOR_RARE := Color("#F1C40F")

@export var id: String = ""
@export var rarity_name_key: String = ""
@export var display_name: String = "Common"
@export var tint: Color = COLOR_COMMON
@export var sort_order: int = 0


func get_localized_name() -> String:
	if not rarity_name_key.is_empty():
		return tr(rarity_name_key)
	return display_name


func get_tier() -> Tier:
	match id.strip_edges().to_lower():
		"uncommon":
			return Tier.UNCOMMON
		"rare", "very_rare":
			## Legacy very_rare maps into the 3-tier RARE bucket.
			return Tier.RARE
		_:
			return Tier.COMMON


static func color_for_tier(tier: Tier) -> Color:
	match tier:
		Tier.UNCOMMON:
			return COLOR_UNCOMMON
		Tier.RARE:
			return COLOR_RARE
		_:
			return COLOR_COMMON


static func color_for_id(rarity_id: String) -> Color:
	match rarity_id.strip_edges().to_lower():
		"uncommon":
			return COLOR_UNCOMMON
		"rare", "very_rare":
			return COLOR_RARE
		_:
			return COLOR_COMMON
