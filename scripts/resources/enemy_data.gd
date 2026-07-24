class_name EnemyData
extends Resource
## Blueprint for a combat encounter enemy.
## Display text is resolved via translation keys (see translations/translations.csv).

enum AttackType {
	BASIC,    ## Flat HP damage.
	SPECIAL,  ## HP damage + cell corruption.
}

@export var id: String = ""

## Localization keys (preferred). Fall back to display_name / description if empty.
@export var enemy_name_key: String = "ENEMY_UNKNOWN_NAME"
@export var enemy_desc_key: String = ""

## Optional English editor fallbacks when keys are missing.
@export var display_name: String = "Unknown Host"
@export_multiline var description: String = ""

@export var max_hp: int = 20
@export var basic_damage: int = 5

## Special attack payload.
@export var special_damage: int = 3
@export var corruption_duration: int = 2
@export var special_chance: float = 0.35

@export var placeholder_color: Color = Color(0.85, 0.85, 0.85)


func get_localized_name() -> String:
	if not enemy_name_key.is_empty():
		return tr(enemy_name_key)
	return display_name


func get_localized_description() -> String:
	if not enemy_desc_key.is_empty():
		return tr(enemy_desc_key)
	return description


func choose_attack() -> AttackType:
	if randf() < special_chance:
		return AttackType.SPECIAL
	return AttackType.BASIC
