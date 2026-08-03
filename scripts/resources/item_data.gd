class_name ItemData
extends Resource
## Blueprint for an equippable body-module / weapon / utility.
## Display text is resolved via translation keys (see translations/translations.csv).
## Icons resolve through get_texture(): item → type default → system fallback.

enum TargetType {
	SELF,
	SINGLE_ENEMY,
	ALL_ENEMIES,
}

const FALLBACK_ICON_PATH := "res://assets/icons/fallback_item.png"

@export var id: String = ""

## Localization keys (preferred). Fall back to display_name / description if empty.
@export var item_name_key: String = "ITEM_UNKNOWN_NAME"
@export var item_desc_key: String = ""

## Optional English editor fallbacks when keys are missing.
@export var display_name: String = "Unknown Module"
@export_multiline var description: String = ""

## Classification / rarity used by adjacency rules and UI.
## Rarity uses the 3-tier system: COMMON / UNCOMMON / RARE (see ItemRarityData.Tier).
@export var item_type: ItemTypeData
@export var rarity: ItemRarityData
@export var sub_type: String = ""  ## HELMET / LEG_ARMOR / CORE / STANDARD / ...

## Optional per-item icon. If null, falls back to item_type.default_type_icon.
@export var texture: Texture2D

## Modular traits gated by adjacency rules at runtime.
@export var traits: Array[TraitData] = []

## Footprint in grid cells (width x height). Swapped on rotate (R while dragging).
@export var size: Vector2i = Vector2i(1, 1)

## If true, at least one occupied cell must touch the grid's outer edge.
@export var requires_edge: bool = false

## Combat activation cost (0 = passive / always-on).
@export var ap_cost: int = 0

## If false, the module cannot be manually activated in combat.
@export var usable: bool = true

## Who this module affects when activated in combat.
@export var target_type: TargetType = TargetType.SINGLE_ENEMY

## Max activations per player turn. -1 or 0 = unlimited (AP still required).
@export var uses_per_turn: int = -1

## If true, activating spends a charge (see max_charges / current_charges).
@export var consumable: bool = false

## Charge pool for exhaustable modules.
@export var max_charges: int = 0

## If true, remove from grid when charges hit 0.
@export var destroy_on_empty: bool = false

## Currency / stackables.
@export var is_stackable: bool = false
@export var max_stack: int = 99
@export var current_stack: int = 1

## Merchant value in Scrap. `null` = cannot be bought or sold.
@export var price: Variant = null

## Intrinsic combat values before active trait modifiers.
@export var base_damage: int = 0
@export var base_armor: int = 0

## Which player ActorStats field scales this module when activated.
enum StatScaling {
	NONE,
	STRENGTH,
	AGILITY,
	INTELLIGENCE,
	ENDURANCE,
	LUCK,
}
@export var scaling_stat: StatScaling = StatScaling.NONE

## Legacy combat fields (kept for older combat paths).
@export var damage: int = 0
@export var block_amount: int = 0

## Flat bonus to the player's max AP while this item is functional.
@export var max_ap_bonus: int = 0

## Damage added to adjacent weapon items when they activate (e.g. Reactor → Weapon).
@export var adjacency_damage_bonus: int = 0

## Extra max AP while this item is adjacent to any functional weapon.
@export var adjacency_ap_bonus: int = 0

## Placeholder tint when no texture is assigned.
@export var placeholder_color: Color = Color(0.7, 0.7, 0.7)

## Runtime: uses spent this player turn (reset on turn start).
var current_turn_uses: int = 0

## Runtime: remaining charges for exhaustable items (-1 = unlimited / not tracked).
var current_charges: int = -1

static var _cached_fallback_icon: Texture2D


# --- Spec aliases -----------------------------------------------------------

var item_name: String:
	get:
		return get_localized_name()
	set(value):
		display_name = value


var is_edge_only: bool:
	get:
		return requires_edge
	set(value):
		requires_edge = value


var cost_ap: int:
	get:
		return ap_cost
	set(value):
		ap_cost = value


var adjacency_dmg_bonus: int:
	get:
		return adjacency_damage_bonus
	set(value):
		adjacency_damage_bonus = value


var exhaustable: bool:
	get:
		return consumable
	set(value):
		consumable = value


func initialize_runtime_state() -> void:
	## Call after duplicating a prototype for a placed / inventory instance.
	current_turn_uses = 0
	if consumable:
		current_charges = maxi(max_charges, 0)
	else:
		current_charges = -1
	current_stack = clampi(current_stack, 1, maxi(max_stack, 1))


func reset_turn_uses() -> void:
	current_turn_uses = 0


func has_unlimited_turn_uses() -> bool:
	return uses_per_turn <= 0


func can_use_this_turn() -> bool:
	if has_unlimited_turn_uses():
		return true
	return current_turn_uses < uses_per_turn


func has_charges_remaining() -> bool:
	if not consumable:
		return true
	return current_charges > 0


func get_localized_name() -> String:
	if not item_name_key.is_empty():
		return tr(item_name_key)
	return display_name


func get_localized_description() -> String:
	if not item_desc_key.is_empty():
		return tr(item_desc_key)
	return description


func get_texture() -> Texture2D:
	## item texture → type default icon → system fallback PNG.
	if texture != null:
		return texture
	if item_type != null and item_type.default_type_icon != null:
		return item_type.default_type_icon
	return _get_system_fallback_icon()


func _get_system_fallback_icon() -> Texture2D:
	if _cached_fallback_icon != null:
		return _cached_fallback_icon
	if ResourceLoader.exists(FALLBACK_ICON_PATH):
		_cached_fallback_icon = load(FALLBACK_ICON_PATH) as Texture2D
	return _cached_fallback_icon


func get_active_traits() -> Array[TraitData]:
	var result: Array[TraitData] = []
	for item_trait: TraitData in traits:
		if item_trait != null and item_trait.is_active:
			result.append(item_trait)
	return result


func get_active_trait_bonus(effect_target: String) -> int:
	## Sum effect_value from active traits whose effect_target matches (e.g. DAMAGE / ARMOR).
	var target := effect_target.strip_edges().to_upper()
	if target.is_empty():
		return 0
	var total := 0
	for item_trait: TraitData in traits:
		if item_trait == null or not item_trait.is_active:
			continue
		if item_trait.effect_target.strip_edges().to_upper() != target:
			continue
		total += item_trait.effect_value
	return total


func get_effective_damage() -> int:
	return base_damage + get_active_trait_bonus("DAMAGE")


func get_effective_armor() -> int:
	return base_armor + get_active_trait_bonus("ARMOR")


func get_stat_scaling_bonus(stats: ActorStats) -> int:
	## Flat ActorStats bonus applied on activation (STR / AGI / INT / …).
	if stats == null:
		return 0
	match scaling_stat:
		StatScaling.STRENGTH:
			return stats.strength
		StatScaling.AGILITY:
			return stats.agility
		StatScaling.INTELLIGENCE:
			return stats.intelligence
		StatScaling.ENDURANCE:
			return stats.endurance
		StatScaling.LUCK:
			return stats.luck
		_:
			return 0


func get_damage_stat_bonus(stats: ActorStats = null) -> int:
	## Only STR / INT feed weapon (or spell) damage — never AGI.
	match scaling_stat:
		StatScaling.STRENGTH, StatScaling.INTELLIGENCE:
			return get_stat_scaling_bonus(stats)
		_:
			return 0


func get_armor_stat_bonus(stats: ActorStats = null) -> int:
	## Only AGI feeds block / armor modules — never STR/INT.
	match scaling_stat:
		StatScaling.AGILITY:
			return get_stat_scaling_bonus(stats)
		_:
			return 0


func get_scaled_damage(stats: ActorStats = null) -> int:
	return get_effective_damage() + get_damage_stat_bonus(stats)


func get_scaled_armor(stats: ActorStats = null) -> int:
	return get_effective_armor() + get_armor_stat_bonus(stats)


func format_damage_display(use_bbcode: bool = true, stats: ActorStats = null) -> String:
	## Weapons / damaging modules only — never show on pure armor.
	if base_damage <= 0:
		return ""
	var trait_bonus := get_active_trait_bonus("DAMAGE")
	var stat_bonus := get_damage_stat_bonus(stats)
	var effective := base_damage + trait_bonus + stat_bonus
	var parts: PackedStringArray = []
	parts.append(str(base_damage))
	if trait_bonus != 0:
		parts.append("%+d" % trait_bonus)
	if stat_bonus != 0:
		parts.append("%+d" % stat_bonus)
	if parts.size() > 1:
		if use_bbcode:
			return "⚔️ %d ([color=#7dcea0]%s[/color])" % [effective, " ".join(parts)]
		return "⚔️ %d (%s)" % [effective, " ".join(parts)]
	return "⚔️ %d %s" % [effective, tr("KEY_DAMAGE")]


func format_armor_display(use_bbcode: bool = true, stats: ActorStats = null) -> String:
	## Armor / shield modules only — never show on pure weapons.
	if base_armor <= 0:
		return ""
	var trait_bonus := get_active_trait_bonus("ARMOR")
	var stat_bonus := get_armor_stat_bonus(stats)
	var effective := base_armor + trait_bonus + stat_bonus
	var parts: PackedStringArray = []
	parts.append(str(base_armor))
	if trait_bonus != 0:
		parts.append("%+d" % trait_bonus)
	if stat_bonus != 0:
		parts.append("%+d" % stat_bonus)
	if parts.size() > 1:
		if use_bbcode:
			return "🛡️ %d ([color=#7dcea0]%s[/color])" % [effective, " ".join(parts)]
		return "🛡️ %d (%s)" % [effective, " ".join(parts)]
	return "🛡️ %d %s" % [effective, tr("KEY_ARMOR")]


func is_sellable() -> bool:
	## Merchants only trade items with a positive numeric price.
	return price != null and price > 0


func is_weapon() -> bool:
	return (base_damage > 0 or damage > 0) and ap_cost > 0


func is_armor() -> bool:
	if item_type == null:
		return false
	return item_type.id.strip_edges().to_upper() == "ARMOR"


func is_currency() -> bool:
	if item_type == null:
		return false
	return item_type.id.strip_edges().to_upper() == "CURRENCY"


func is_shield() -> bool:
	return (base_armor > 0 or block_amount > 0) and ap_cost > 0


func get_equipment_stat_modifiers() -> Dictionary:
	## Flat ActorStats granted while this module is functional on the body grid.
	## Traits with effect_target STR/AGI/END/INT/LCK/HUM contribute when active.
	var result: Dictionary = {}
	for item_trait: TraitData in traits:
		if item_trait == null or not item_trait.is_active:
			continue
		if item_trait.effect_value == 0:
			continue
		var key := _equipment_stat_key(item_trait.effect_target)
		if key.is_empty():
			continue
		result[key] = int(result.get(key, 0)) + item_trait.effect_value
	return result


func _equipment_stat_key(raw: String) -> String:
	match raw.strip_edges().to_upper():
		"STR", "STRENGTH":
			return "strength"
		"AGI", "AGILITY":
			return "agility"
		"END", "ENDURANCE":
			return "endurance"
		"INT", "INTELLIGENCE":
			return "intelligence"
		"LCK", "LUCK":
			return "luck"
		"HUM", "HUMANITY":
			return "humanity"
		_:
			return ""


func rotate_size() -> void:
	size = Vector2i(size.y, size.x)


func footprint_for(footprint: Vector2i, origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in footprint.y:
		for x in footprint.x:
			cells.append(origin + Vector2i(x, y))
	return cells


func footprint_cells(origin: Vector2i) -> Array[Vector2i]:
	return footprint_for(size, origin)
