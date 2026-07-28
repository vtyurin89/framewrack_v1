class_name EnemyAbility
extends Resource
## Scalable enemy combat action driven by main_effect + AbilityEffect handlers.

enum AbilityType {
	DAMAGE,
	BLOCK,
	HEAL,
	SPECIAL,
	PRE_ACTION,
	MULTI_HIT,
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
## self | player | ally | all_allies
@export var target_type: String = "player"
## damage | heal | modify_stat | status | summon
@export var main_effect: String = "damage"
## Raw CSV effect_params (pipe-separated).
@export var effect_params: String = ""
@export var type: AbilityType = AbilityType.DAMAGE
@export var min_val: int = 1
@export var max_val: int = 3
@export var stat_scaling: StatScaling = StatScaling.STRENGTH
@export var weight_class: WeightClass = WeightClass.STANDARD
@export var base_ai_weight: float = 1.0
@export var hit_count: int = 1
@export var hp_threshold: float = 0.0
@export var cooldown_turns: int = 0
@export var max_charges: int = -1
@export var trigger_interval: int = 0
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


func get_effect_param_list() -> Array:
	var result: Array = []
	var cleaned := effect_params.strip_edges().trim_prefix("\"").trim_suffix("\"")
	if cleaned.is_empty():
		return result
	for part in cleaned.split("|", false):
		var token := str(part).strip_edges()
		if not token.is_empty():
			result.append(token)
	return result


func is_main_deck_ability() -> bool:
	return type != AbilityType.PRE_ACTION and type != AbilityType.MULTI_HIT


func requires_defensive_cooldown() -> bool:
	if type in [AbilityType.HEAL, AbilityType.BLOCK]:
		return true
	var effect := main_effect.strip_edges().to_lower()
	if effect == "heal":
		return true
	## Defensive status shields / guards.
	var params := effect_params.strip_edges().to_lower()
	if params.begins_with("block") or params.begins_with("guard") or params.begins_with("shield"):
		return true
	return false


func infer_main_effect() -> String:
	if not main_effect.strip_edges().is_empty():
		return main_effect.strip_edges().to_lower()
	match type:
		AbilityType.HEAL:
			return "heal"
		AbilityType.BLOCK:
			return "status"
		AbilityType.PRE_ACTION:
			return "modify_stat"
		_:
			return "damage"


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


static func parse_main_effect(raw: String) -> String:
	match raw.strip_edges().to_lower():
		"heal", "repair":
			return "heal"
		"modify_stat", "buff", "stat":
			return "modify_stat"
		"status", "block", "shield", "debuff":
			return "status"
		"summon":
			return "summon"
		"damage", "attack", "multi_hit", "":
			return "damage"
		_:
			return raw.strip_edges().to_lower()


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
