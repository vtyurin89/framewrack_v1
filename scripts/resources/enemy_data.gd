class_name EnemyData
extends Resource
## Blueprint for a combat encounter enemy (CSV / editor).
## Runtime combat state lives on EnemyInstance after setup().

enum AttackType {
	BASIC,
	SPECIAL,
}

const FACTION_HUMAN := "human"
const FACTION_SYNTHET := "synthet"
const FACTION_CHIMERA := "chimera"

const TIER_NORMAL := "normal"
const TIER_ELITE := "elite"
const TIER_BOSS := "boss"

const ROLE_MINION := "minion"
const ROLE_DAMAGE := "damage"
const ROLE_SUPPORT := "support"
const ROLE_BOSS := "boss"

## Hidden enemy trait: Block does not expire at the start of this enemy's turn.
const TRAIT_PERMANENT_SHIELD := "permanent_shield"
## Hidden enemy trait: always reroll telegraphed intention after taking HP damage.
const TRAIT_ALWAYS_REROLL_INTENT := "always_reroll_intent"
## Chem-Junkie: same as always_reroll_intent (localized as Unpredictable).
const TRAIT_UNPREDICTABLE := "unpredictable"
## Chem-Junkie: +1 STR after 3 direct attack HP hits in one player turn.
const TRAIT_PSYCHOSIS := "psychosis"
## Trait ids that are combat mechanics, not StatusEffectData blueprints.
const MECHANIC_TRAIT_IDS: Array[String] = [
	TRAIT_PERMANENT_SHIELD,
	TRAIT_ALWAYS_REROLL_INTENT,
	TRAIT_UNPREDICTABLE,
	TRAIT_PSYCHOSIS,
	"stasis_pod",
]

@export var id: String = ""

## Localization keys (preferred). Fallbacks: display_name / description.
@export var enemy_name_key: String = "ENEMY_UNKNOWN_NAME"
@export var enemy_desc_key: String = ""
@export var display_name: String = "Unknown Host"
@export_multiline var description: String = ""

## Lore faction — encounters must never mix factions.
@export var faction: String = FACTION_HUMAN
## Encounter pool category: normal | elite | boss.
@export var combat_tier: String = TIER_NORMAL
## Combat role: minion | damage | support | boss.
@export var role: String = ROLE_DAMAGE
## Difficulty cost for dynamic threat budgets.
@export var threat_level: int = 10
## Encounter-generator power weight (group budgets). Defaults to threat_level when unset in CSV.
@export var power_rating: int = 1

## Base HP before endurance / difficulty scaling. 0 = fall back to legacy max_hp.
@export var base_hp: int = 0
## Legacy flat HP used when base_hp is unset in old .tres files.
@export var max_hp: int = 20

@export var strength: int = 1
@export var agility: int = 1
@export var endurance: int = 1
@export var intelligence: int = 1
@export var luck: int = 1

@export var exp_reward: int = 30
@export var abilities: Array[EnemyAbility] = []
@export var trait_ids: Array[String] = []
@export var sprite_path: String = ""
@export var placeholder_color: Color = Color(0.85, 0.85, 0.85)

## Legacy attack fields kept for older content / fallback AI.
@export var basic_damage: int = 5
@export var special_damage: int = 3
@export var corruption_duration: int = 0
@export var special_chance: float = 0.0


func get_localized_name() -> String:
	if not enemy_name_key.is_empty():
		return tr(enemy_name_key)
	return display_name


func get_localized_description() -> String:
	if not enemy_desc_key.is_empty():
		return tr(enemy_desc_key)
	return description


func get_effective_base_hp() -> int:
	## Prefer explicit base_hp; fall back to legacy max_hp for .tres content.
	if base_hp > 0:
		return base_hp
	return maxi(max_hp, 1)


func get_faction() -> String:
	return faction.strip_edges().to_lower()


func get_combat_tier() -> String:
	return combat_tier.strip_edges().to_lower()


func get_role() -> String:
	return role.strip_edges().to_lower()


func is_boss_tier() -> bool:
	return get_combat_tier() == TIER_BOSS or get_role() == ROLE_BOSS


func choose_attack() -> AttackType:
	## Fallback when an enemy has no ability list.
	if randf() < special_chance:
		return AttackType.SPECIAL
	return AttackType.BASIC
