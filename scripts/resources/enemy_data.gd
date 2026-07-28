class_name EnemyData
extends Resource
## Blueprint for a combat encounter enemy (CSV / editor).
## Runtime combat state lives on EnemyInstance after setup().

enum AttackType {
	BASIC,
	SPECIAL,
}

@export var id: String = ""

## Localization keys (preferred). Fallbacks: display_name / description.
@export var enemy_name_key: String = "ENEMY_UNKNOWN_NAME"
@export var enemy_desc_key: String = ""
@export var display_name: String = "Unknown Host"
@export_multiline var description: String = ""

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
@export var corruption_duration: int = 2
@export var special_chance: float = 0.35


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


func choose_attack() -> AttackType:
	## Fallback when an enemy has no ability list.
	if randf() < special_chance:
		return AttackType.SPECIAL
	return AttackType.BASIC
