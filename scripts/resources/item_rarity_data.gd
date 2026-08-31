class_name ItemRarityData
extends Resource
## Rarity tier used by adjacency rules and loot / UI tinting.
## Framewrack uses 4 tiers: COMMON / UNCOMMON / RARE / VERY_RARE.

enum Tier {
	COMMON,
	UNCOMMON,
	RARE,
	VERY_RARE,
	BOSS,
}

const COLOR_COMMON := Color("#BDC3C7")
const COLOR_UNCOMMON := Color("#3498DB")
const COLOR_RARE := Color("#F1C40F")
const COLOR_VERY_RARE := Color("#9B59B6")
const COLOR_BOSS := Color("#E67E22")

const RARITY_COLORS := {
	Tier.COMMON: COLOR_COMMON,
	Tier.UNCOMMON: COLOR_UNCOMMON,
	Tier.RARE: COLOR_RARE,
	Tier.VERY_RARE: COLOR_VERY_RARE,
	Tier.BOSS: COLOR_BOSS,
}

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
		"boss":
			return Tier.BOSS
		"uncommon":
			return Tier.UNCOMMON
		"rare":
			return Tier.RARE
		"very_rare":
			return Tier.VERY_RARE
		_:
			return Tier.COMMON


func get_tint_color() -> Color:
	return color_for_tier(get_tier())


static func color_for_tier(tier: Tier) -> Color:
	if RARITY_COLORS.has(tier):
		return RARITY_COLORS[tier] as Color
	return COLOR_COMMON


static func color_for_id(rarity_id: String) -> Color:
	match rarity_id.strip_edges().to_lower():
		"boss":
			return COLOR_BOSS
		"uncommon":
			return COLOR_UNCOMMON
		"rare":
			return COLOR_RARE
		"very_rare":
			return COLOR_VERY_RARE
		_:
			return COLOR_COMMON
