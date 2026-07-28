extends Node
## Autoload: global gameplay settings (debug tools, combat difficulty).

signal difficulty_changed(new_difficulty: int)

enum Difficulty {
	EASY = 0,
	NORMAL = 1,
	HARD = 2,
}

@export var hide_debug_tools: bool = false
@export var difficulty: Difficulty = Difficulty.NORMAL

## HP / damage multipliers applied when EnemyInstance.setup() runs.
const HP_MULT: Dictionary = {
	Difficulty.EASY: 0.85,
	Difficulty.NORMAL: 1.0,
	Difficulty.HARD: 1.25,
}
const DAMAGE_MULT: Dictionary = {
	Difficulty.EASY: 0.85,
	Difficulty.NORMAL: 1.0,
	Difficulty.HARD: 1.15,
}
## Multiplier applied to HEAVY ability AI selection weights.
const HEAVY_ABILITY_WEIGHT_MULT: Dictionary = {
	Difficulty.EASY: 0.35,
	Difficulty.NORMAL: 1.0,
	Difficulty.HARD: 1.75,
}
const LIGHT_ABILITY_WEIGHT_MULT: Dictionary = {
	Difficulty.EASY: 1.35,
	Difficulty.NORMAL: 1.0,
	Difficulty.HARD: 0.75,
}


func toggle_debug_tools(hide: bool) -> void:
	hide_debug_tools = hide
	get_tree().call_group("debug_ui", "set_visible", not hide)


func set_difficulty(level: Difficulty) -> void:
	if difficulty == level:
		return
	difficulty = level
	difficulty_changed.emit(int(difficulty))


func get_enemy_hp_multiplier() -> float:
	return float(HP_MULT.get(difficulty, 1.0))


func get_enemy_damage_multiplier() -> float:
	return float(DAMAGE_MULT.get(difficulty, 1.0))


func get_heavy_ability_weight_multiplier() -> float:
	return float(HEAVY_ABILITY_WEIGHT_MULT.get(difficulty, 1.0))


func get_light_ability_weight_multiplier() -> float:
	return float(LIGHT_ABILITY_WEIGHT_MULT.get(difficulty, 1.0))


func get_ability_weight_multiplier(weight_class: int) -> float:
	## weight_class matches EnemyAbility.WeightClass.
	match weight_class:
		1: ## HEAVY
			return get_heavy_ability_weight_multiplier()
		2: ## LIGHT
			return get_light_ability_weight_multiplier()
		_:
			return 1.0


func difficulty_label_key(level: int = -1) -> String:
	var resolved := level if level >= 0 else int(difficulty)
	match resolved:
		Difficulty.EASY:
			return "KEY_DIFFICULTY_EASY"
		Difficulty.HARD:
			return "KEY_DIFFICULTY_HARD"
		_:
			return "KEY_DIFFICULTY_NORMAL"
