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
## Rarity tiers: COMMON / UNCOMMON / RARE / VERY_RARE (see ItemRarityData).
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
## Max activations for the whole combat. -1 or 0 = unlimited.
@export var uses_per_combat: int = -1

## Combat cooldown in player turns (0 = none). After use, applies a COOLDOWN ItemStatus.
@export var cooldown: int = 0

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

## If false, cannot be discarded into Space during post-combat rewards.
@export var dropable: bool = true

## Harmful / parasitic modules forced into the Body Grid (cannot be discarded).
@export var is_harmful: bool = false

## If true, this consumable can only be activated during combat.
@export var is_combat_only: bool = false

## Intrinsic combat values before active trait modifiers.
## Damaging modules roll between min_damage and max_damage on hit.
@export var min_damage: int = 0
@export var max_damage: int = 0
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
## Runtime: uses spent this combat (reset on combat start).
var current_combat_uses: int = 0

## Runtime statuses (COOLDOWN / OVERLOAD / TAINTED). Append is LIFO for primary display.
var statuses: Array[ItemStatus] = []

## Runtime: remaining charges for exhaustable items (-1 = unlimited / not tracked).
var current_charges: int = -1
## Runtime: temporary flat damage for this turn only (e.g. War Module adjacency buff).
var temp_flat_damage_bonus: int = 0
## Runtime: permanent flat damage growth kept on this item instance.
var permanent_damage_bonus: int = 0

static var _cached_fallback_icon: Texture2D

## Compat: remaining COOLDOWN turns (0 if none).
var current_cd: int:
	get:
		var s := get_status(ItemStatus.Type.COOLDOWN)
		return s.remaining_turns if s != null else 0
	set(value):
		var turns := maxi(0, value)
		if turns <= 0:
			clear_status(ItemStatus.Type.COOLDOWN)
		else:
			apply_status(ItemStatus.Type.COOLDOWN, turns)


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
	current_combat_uses = 0
	statuses.clear()
	temp_flat_damage_bonus = 0
	permanent_damage_bonus = 0
	if consumable:
		current_charges = maxi(max_charges, 0)
	else:
		current_charges = -1
	current_stack = clampi(current_stack, 1, maxi(max_stack, 1))


func reset_turn_uses() -> void:
	current_turn_uses = 0


func reset_combat_uses() -> void:
	current_combat_uses = 0


func clear_temporary_combat_bonuses() -> void:
	temp_flat_damage_bonus = 0


func apply_status(
	status_type: ItemStatus.Type,
	remaining_turns: int = 1,
	args: Dictionary = {}
) -> ItemStatus:
	## Replace any existing status of the same type, then append (LIFO primary).
	clear_status(status_type)
	var status := ItemStatus.new(status_type, maxi(1, remaining_turns), args)
	statuses.append(status)
	return status


func add_status(status: ItemStatus) -> void:
	if status == null:
		return
	clear_status(status.type)
	statuses.append(status)


func clear_status(status_type: ItemStatus.Type) -> void:
	var kept: Array[ItemStatus] = []
	for s: ItemStatus in statuses:
		if s != null and s.type != status_type:
			kept.append(s)
	statuses = kept


func get_status(status_type: ItemStatus.Type) -> ItemStatus:
	## Most recently added status of this type (LIFO scan).
	for i in range(statuses.size() - 1, -1, -1):
		var s: ItemStatus = statuses[i]
		if s != null and s.type == status_type and not s.is_expired():
			return s
	return null


func has_status(status_type: ItemStatus.Type) -> bool:
	return get_status(status_type) != null


func get_primary_status() -> ItemStatus:
	## Latest non-expired status drives overlay / primary behavior display.
	for i in range(statuses.size() - 1, -1, -1):
		var s: ItemStatus = statuses[i]
		if s != null and not s.is_expired():
			return s
	return null


func has_blocking_status() -> bool:
	for s: ItemStatus in statuses:
		if s != null and not s.is_expired() and s.blocks_activation():
			return true
	return false


func get_taint_damage() -> int:
	var s := get_status(ItemStatus.Type.TAINTED)
	return s.get_taint_damage() if s != null else 0


func tick_statuses() -> void:
	for s: ItemStatus in statuses:
		if s != null:
			s.tick_turn()
	prune_expired_statuses()


func prune_expired_statuses() -> void:
	var kept: Array[ItemStatus] = []
	for s: ItemStatus in statuses:
		if s != null and not s.is_expired():
			kept.append(s)
	statuses = kept


func tick_cooldown() -> void:
	## Legacy alias — ticks all item statuses (end-of-turn pipeline).
	tick_statuses()


func start_cooldown(turns: int = -1) -> void:
	var duration := cooldown if turns < 0 else turns
	if duration <= 0:
		return
	apply_status(ItemStatus.Type.COOLDOWN, duration)


func apply_overload(turns: int = 1, args: Dictionary = {}) -> void:
	var payload := args.duplicate(true)
	if not payload.has("lightning_icon"):
		payload["lightning_icon"] = true
	apply_status(ItemStatus.Type.OVERLOAD, maxi(1, turns), payload)


func apply_tainted(turns: int = 1, damage: int = 1) -> void:
	apply_status(ItemStatus.Type.TAINTED, maxi(1, turns), {"damage": maxi(1, damage)})


func is_on_cooldown() -> bool:
	return has_status(ItemStatus.Type.COOLDOWN)


func is_overloaded() -> bool:
	return has_status(ItemStatus.Type.OVERLOAD)


func is_tainted() -> bool:
	return has_status(ItemStatus.Type.TAINTED)


func has_unlimited_turn_uses() -> bool:
	return uses_per_turn <= 0


func has_unlimited_combat_uses() -> bool:
	return uses_per_combat <= 0


func can_use_this_turn() -> bool:
	if has_blocking_status():
		return false
	if has_unlimited_turn_uses():
		return true
	return current_turn_uses < uses_per_turn


func can_use_this_combat() -> bool:
	if has_unlimited_combat_uses():
		return true
	return current_combat_uses < uses_per_combat


func has_charges_remaining() -> bool:
	if not consumable:
		return true
	return current_charges > 0


func get_localized_name() -> String:
	if not item_name_key.is_empty():
		return tr(item_name_key)
	return display_name


func get_rarity_color() -> Color:
	if rarity != null:
		return rarity.get_tint_color()
	return ItemRarityData.COLOR_COMMON


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


func get_damage_roll_bounds() -> Vector2i:
	## Inclusive roll window after normalizing min/max.
	if min_damage <= 0 and max_damage <= 0:
		return Vector2i.ZERO
	var lo := mini(min_damage, max_damage)
	var hi := maxi(min_damage, max_damage)
	return Vector2i(lo, hi)


func get_effective_damage_bounds() -> Vector2i:
	var bounds := get_damage_roll_bounds()
	if bounds == Vector2i.ZERO:
		return Vector2i.ZERO
	var bonus := get_active_trait_bonus("DAMAGE") + temp_flat_damage_bonus + permanent_damage_bonus
	return Vector2i(bounds.x + bonus, bounds.y + bonus)


func get_effective_damage() -> int:
	## Midpoint of the rolled window (UI / legacy callers).
	var bounds := get_effective_damage_bounds()
	if bounds == Vector2i.ZERO:
		return 0
	return int(round((float(bounds.x) + float(bounds.y)) * 0.5))


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


func get_scaled_damage_bounds(stats: ActorStats = null) -> Vector2i:
	var bounds := get_effective_damage_bounds()
	if bounds == Vector2i.ZERO:
		return Vector2i.ZERO
	var stat_bonus := get_damage_stat_bonus(stats)
	return Vector2i(bounds.x + stat_bonus, bounds.y + stat_bonus)


func roll_damage(stats: ActorStats = null) -> int:
	## Combat hit: random roll in [min, max] plus trait / stat bonuses.
	var bounds := get_scaled_damage_bounds(stats)
	if bounds == Vector2i.ZERO:
		return 0
	var lo := mini(bounds.x, bounds.y)
	var hi := maxi(bounds.x, bounds.y)
	return randi_range(lo, hi)


func get_scaled_damage(stats: ActorStats = null) -> int:
	## Midpoint of scaled bounds (tooltips / non-combat). Combat uses roll_damage().
	var bounds := get_scaled_damage_bounds(stats)
	if bounds == Vector2i.ZERO:
		return 0
	return int(round((float(bounds.x) + float(bounds.y)) * 0.5))


func get_scaled_armor(stats: ActorStats = null) -> int:
	return get_effective_armor() + get_armor_stat_bonus(stats)


func format_damage_display(use_bbcode: bool = true, stats: ActorStats = null) -> String:
	## Weapons / damaging modules only — never show on pure armor.
	var base_bounds := get_damage_roll_bounds()
	if base_bounds == Vector2i.ZERO:
		return ""
	var trait_bonus := get_active_trait_bonus("DAMAGE")
	var stat_bonus := get_damage_stat_bonus(stats)
	var lo := base_bounds.x + trait_bonus + stat_bonus
	var hi := base_bounds.y + trait_bonus + stat_bonus
	var range_text := str(lo) if lo == hi else "%d-%d" % [lo, hi]
	var parts: PackedStringArray = []
	if base_bounds.x == base_bounds.y:
		parts.append(str(base_bounds.x))
	else:
		parts.append("%d-%d" % [base_bounds.x, base_bounds.y])
	if trait_bonus != 0:
		parts.append("%+d" % trait_bonus)
	if stat_bonus != 0:
		parts.append("%+d" % stat_bonus)
	if permanent_damage_bonus != 0:
		parts.append("%+d" % permanent_damage_bonus)
	if temp_flat_damage_bonus != 0:
		parts.append("%+d" % temp_flat_damage_bonus)
	if parts.size() > 1:
		if use_bbcode:
			return "⚔️ %s ([color=#7dcea0]%s[/color])" % [range_text, " ".join(parts)]
		return "⚔️ %s (%s)" % [range_text, " ".join(parts)]
	return "⚔️ %s %s" % [range_text, tr("KEY_DAMAGE")]


func format_armor_display(use_bbcode: bool = true, stats: ActorStats = null) -> String:
	## Armor / shield modules only — never show on pure weapons.
	if base_armor <= 0:
		return ""
	var trait_bonus := get_active_trait_bonus("ARMOR")
	var stat_bonus := get_armor_stat_bonus(stats)
	var effective := base_armor + trait_bonus + stat_bonus
	var label_key := "KEY_SHIELD" if is_shield() else "KEY_ARMOR"
	var parts: PackedStringArray = []
	parts.append(str(base_armor))
	if trait_bonus != 0:
		parts.append("%+d" % trait_bonus)
	if stat_bonus != 0:
		parts.append("%+d" % stat_bonus)
	if parts.size() > 1:
		if use_bbcode:
			return "🛡️ %d ([color=#7dcea0]%s[/color]) %s" % [effective, " ".join(parts), tr(label_key)]
		return "🛡️ %d (%s) %s" % [effective, " ".join(parts), tr(label_key)]
	return "🛡️ %d %s" % [effective, tr(label_key)]


func applies_dot_on_hit() -> bool:
	## Burn / Poison application traits (weapons + throwables).
	return (
		TraitManager.has_trait(self, "TRAIT_FUEL_BURST")
		or TraitManager.has_trait(self, "TRAIT_APPLY_BURN")
		or TraitManager.has_trait(self, "TRAIT_BURN_DAMAGE")
		or TraitManager.has_trait(self, "TRAIT_FANG_POISON")
	)


func format_adjacency_bonus_notes(grid: BodyGrid, use_bbcode: bool = true) -> String:
	## Live neighbour bonuses shown under combat stats (not baked into damage numbers).
	if grid == null:
		return ""
	var placed := grid.find_placed_by_data(self)
	if placed == null:
		return ""
	var lines: PackedStringArray = []
	var dmg_bonus := grid.get_adjacency_damage_bonus_for(placed)
	if dmg_bonus > 0:
		if use_bbcode:
			lines.append(tr("KEY_ADJ_DMG_BONUS_NOTE") % dmg_bonus)
		else:
			lines.append(tr("KEY_ADJ_DMG_BONUS_NOTE_PLAIN") % dmg_bonus)
	if applies_dot_on_hit():
		var dot_bonus := grid.get_adjacent_dot_amplify_bonus(placed)
		if dot_bonus > 0:
			if use_bbcode:
				lines.append(tr("KEY_ADJ_DOT_BONUS_NOTE") % dot_bonus)
			else:
				lines.append(tr("KEY_ADJ_DOT_BONUS_NOTE_PLAIN") % dot_bonus)
	if temp_flat_damage_bonus > 0:
		if use_bbcode:
			lines.append(tr("KEY_TEMP_DMG_BONUS_NOTE") % temp_flat_damage_bonus)
		else:
			lines.append(tr("KEY_TEMP_DMG_BONUS_NOTE_PLAIN") % temp_flat_damage_bonus)
	return "\n".join(lines)


func is_sellable() -> bool:
	## Merchants only trade items with a positive numeric price.
	return price != null and price > 0


func get_price_value() -> int:
	if price == null:
		return 0
	return maxi(0, int(price))


func is_weapon() -> bool:
	return (max_damage > 0 or min_damage > 0 or damage > 0) and ap_cost > 0


func is_harmful_item() -> bool:
	return is_harmful


func enforce_harmful_constraints() -> void:
	## Harmful modules cannot stack, cannot be discarded, and must be activatable.
	if not is_harmful:
		return
	dropable = false
	is_stackable = false
	usable = true


func is_armor() -> bool:
	if item_type == null:
		return false
	var type_id := item_type.id.strip_edges().to_upper()
	return type_id == "ARMOR" or type_id == "SHIELD"


func is_shield() -> bool:
	if item_type == null:
		return false
	return item_type.id.strip_edges().to_upper() == "SHIELD"


func is_currency() -> bool:
	if item_type == null:
		return false
	return item_type.id.strip_edges().to_upper() == "CURRENCY"


func is_consumable_item() -> bool:
	if consumable:
		return true
	if item_type == null:
		return false
	return item_type.id.strip_edges().to_upper() == "CONSUMABLE"


func can_use_out_of_combat() -> bool:
	## Utility / heal / grid tools — not combat-only grenades or harmful parasites.
	if not usable or is_harmful or is_combat_only:
		return false
	return is_consumable_item()


func grants_ap_on_use() -> bool:
	for item_trait: TraitData in traits:
		if item_trait == null:
			continue
		var tid := item_trait.id.strip_edges().to_upper()
		if tid in ["TRAIT_GIVE_AP", "TRAIT_NEURO_STIM", "TRAIT_SYNAPSE_BOOSTER"]:
			return true
	return false


func is_grid_expander() -> bool:
	return id.strip_edges().to_upper() == "GRID_EXPANDER"


func is_implant() -> bool:
	if item_type == null:
		return false
	return item_type.id.strip_edges().to_upper() == "IMPLANT"


func is_amplifier() -> bool:
	if item_type == null:
		return false
	return item_type.id.strip_edges().to_upper() == "AMPLIFIER"


func is_active_module() -> bool:
	if item_type == null:
		return false
	return item_type.id.strip_edges().to_upper() == "ACTIVE_MODULE"


func is_quest_item() -> bool:
	if item_type == null:
		return false
	return item_type.id.strip_edges().to_upper() == "QUEST_ITEM"


func is_neuron_amplifier() -> bool:
	return id.strip_edges().to_upper() == "NEURON_AMPLIFIER"


func on_combat_end(player: InventoryController) -> void:
	## Passive implant / module triggers after a victorious fight.
	if player == null:
		return
	if TraitManager.has_trait(self, "TRAIT_HEAL_ON_COMBAT_END"):
		var heal_amt := TraitManager.get_trait_value(self, "TRAIT_HEAL_ON_COMBAT_END", 2)
		if heal_amt > 0:
			player.current_hp = mini(player.max_hp, player.current_hp + heal_amt)
			EventBus.player_hp_changed.emit(player.current_hp, player.max_hp)
			EventBus.combat_log_message.emit(
				tr("KEY_LOG_COMBAT_END_HEAL") % [get_localized_name(), heal_amt]
			)
	if TraitManager.has_trait(self, "TRAIT_CHIPS_ON_COMBAT_END"):
		var chips := TraitManager.get_trait_value(self, "TRAIT_CHIPS_ON_COMBAT_END", 4)
		if chips > 0 and GameManager != null:
			var gained: int = GameManager.add_chips(chips)
			if gained > 0:
				EventBus.combat_log_message.emit(
					tr("KEY_LOG_COMBAT_END_CHIPS") % [get_localized_name(), gained]
				)


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
