class_name EnemyAbility
extends Resource
## Scalable enemy combat action: min–max roll + stat bonus + weighted / phased AI.

enum AbilityType {
	DAMAGE,
	BLOCK,
	HEAL,
	SPECIAL,
	PRE_ACTION, ## Passive-start buff / study phase (not a main-deck pick).
	MULTI_HIT, ## Priority frenzy: multiple base rolls without stat bonus.
}

enum StatScaling {
	NONE,
	STRENGTH,
	AGILITY,
	ENDURANCE,
	INTELLIGENCE,
	LUCK,
}

enum WeightClass {
	STANDARD = 0,
	HEAVY = 1,
	LIGHT = 2,
}

@export var id: String = ""
@export var ability_name_key: String = ""
@export var description_key: String = ""
@export var type: AbilityType = AbilityType.DAMAGE
@export var min_val: int = 1
@export var max_val: int = 3
@export var stat_scaling: StatScaling = StatScaling.STRENGTH
@export var weight_class: WeightClass = WeightClass.STANDARD
@export var base_ai_weight: float = 1.0
## MULTI_HIT: number of consecutive base rolls.
@export var hit_count: int = 1
## MULTI_HIT: unlock when current_hp / max_hp <= this ratio (0 = always).
@export var hp_threshold: float = 0.0
## Turns that must pass after use before this ability can fire again.
@export var cooldown_turns: int = 0
## PRE_ACTION: fire on turn numbers divisible by this interval (e.g. 2 → turns 2,4,6…).
@export var trigger_interval: int = 0
## Localization key (or plain text) shown as floating combat notice over the enemy.
@export var combat_text: String = ""


func get_localized_name() -> String:
	if not ability_name_key.is_empty():
		return tr(ability_name_key)
	return id


func get_localized_description() -> String:
	if not description_key.is_empty():
		return tr(description_key)
	return ""


func get_combat_notice_text() -> String:
	## Prefer CSV combat_text; fall back to the ability display name.
	if not combat_text.is_empty():
		return tr(combat_text)
	return get_localized_name()


func get_clamped_range() -> Vector2i:
	var lo := mini(min_val, max_val)
	var hi := maxi(min_val, max_val)
	return Vector2i(lo, hi)


func roll_base() -> int:
	var r := get_clamped_range()
	return randi_range(r.x, r.y)


func is_main_deck_ability() -> bool:
	## Pre-action / multi-hit priority skills are resolved outside weighted picks.
	return type != AbilityType.PRE_ACTION and type != AbilityType.MULTI_HIT


static func parse_type(raw: String) -> AbilityType:
	match raw.strip_edges().to_upper():
		"BLOCK", "SHIELD":
			return AbilityType.BLOCK
		"HEAL", "REPAIR":
			return AbilityType.HEAL
		"PRE_ACTION", "BUFF", "PASSIVE":
			return AbilityType.PRE_ACTION
		"MULTI_HIT", "FRENZY":
			return AbilityType.MULTI_HIT
		"SPECIAL":
			return AbilityType.SPECIAL
		_:
			return AbilityType.DAMAGE


static func parse_stat_scaling(raw: String) -> StatScaling:
	match raw.strip_edges().to_upper():
		"STR", "STRENGTH":
			return StatScaling.STRENGTH
		"AGI", "AGILITY":
			return StatScaling.AGILITY
		"END", "ENDURANCE":
			return StatScaling.ENDURANCE
		"INT", "INTELLIGENCE":
			return StatScaling.INTELLIGENCE
		"LCK", "LUCK":
			return StatScaling.LUCK
		_:
			return StatScaling.NONE


static func parse_weight_class(raw: String) -> WeightClass:
	match raw.strip_edges().to_upper():
		"HEAVY":
			return WeightClass.HEAVY
		"LIGHT":
			return WeightClass.LIGHT
		_:
			return WeightClass.STANDARD


func stat_label_key() -> String:
	match stat_scaling:
		StatScaling.STRENGTH:
			return "KEY_STR"
		StatScaling.AGILITY:
			return "KEY_AGI"
		StatScaling.ENDURANCE:
			return "KEY_END"
		StatScaling.INTELLIGENCE:
			return "KEY_INT"
		StatScaling.LUCK:
			return "KEY_LCK"
		_:
			return ""
