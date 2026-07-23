class_name EnemyData
extends Resource
## Blueprint for a combat encounter enemy.

enum AttackType {
	BASIC,    ## Flat HP damage.
	SPECIAL,  ## HP damage + cell corruption.
}

@export var id: String = ""
@export var display_name: String = "Unknown Host"
@export_multiline var description: String = ""

@export var max_hp: int = 20
@export var basic_damage: int = 5

## Special attack payload.
@export var special_damage: int = 3
@export var corruption_duration: int = 2
@export var special_chance: float = 0.35

@export var placeholder_color: Color = Color(0.85, 0.85, 0.85)


func choose_attack() -> AttackType:
	if randf() < special_chance:
		return AttackType.SPECIAL
	return AttackType.BASIC
