class_name ItemData
extends Resource
## Blueprint for an equippable body-module / weapon / utility.
## Display text is resolved via translation keys (see translations/translations.csv).
## Icons resolve through get_texture(): item → type default → system fallback.

const FALLBACK_ICON_PATH := "res://assets/icons/fallback_item.png"

@export var id: String = ""

## Localization keys (preferred). Fall back to display_name / description if empty.
@export var item_name_key: String = "ITEM_UNKNOWN_NAME"
@export var item_desc_key: String = ""

## Optional English editor fallbacks when keys are missing.
@export var display_name: String = "Unknown Module"
@export_multiline var description: String = ""

## Classification / rarity used by adjacency rules and UI.
@export var item_type: ItemTypeData
@export var rarity: ItemRarityData

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

## If true, activating spends a charge (see max_charges).
@export var consumable: bool = false

## Charge pool for consumable / ammo-fed modules (0 = unlimited / N/A).
@export var max_charges: int = 0

## Merchant value in Scrap. `null` = cannot be bought or sold.
@export var price: Variant = null

## Intrinsic combat values before active trait modifiers.
@export var base_damage: int = 0
@export var base_armor: int = 0

## Legacy combat fields (kept for older .tres / combat paths).
## Prefer base_damage / base_armor + get_effective_*().
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


func format_damage_display(use_bbcode: bool = true) -> String:
	## e.g. "⚔️ 8 Damage" or "⚔️ 8 (5 + 3)" with green bonus highlight.
	var effective := get_effective_damage()
	if effective <= 0:
		return ""
	var bonus := get_active_trait_bonus("DAMAGE")
	if bonus > 0:
		if use_bbcode:
			return "⚔️ %d ([color=#7dcea0]%d + %d[/color])" % [effective, base_damage, bonus]
		return "⚔️ %d (%d + %d)" % [effective, base_damage, bonus]
	return "⚔️ %d %s" % [effective, tr("KEY_DAMAGE")]


func format_armor_display(use_bbcode: bool = true) -> String:
	var effective := get_effective_armor()
	if effective <= 0:
		return ""
	var bonus := get_active_trait_bonus("ARMOR")
	if bonus > 0:
		if use_bbcode:
			return "🛡️ %d ([color=#7dcea0]%d + %d[/color])" % [effective, base_armor, bonus]
		return "🛡️ %d (%d + %d)" % [effective, base_armor, bonus]
	return "🛡️ %d %s" % [effective, tr("KEY_ARMOR")]


func is_sellable() -> bool:
	## Merchants only trade items with a positive numeric price.
	return price != null and price > 0


func is_weapon() -> bool:
	return (base_damage > 0 or damage > 0) and ap_cost > 0


func is_shield() -> bool:
	return (base_armor > 0 or block_amount > 0) and ap_cost > 0


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
