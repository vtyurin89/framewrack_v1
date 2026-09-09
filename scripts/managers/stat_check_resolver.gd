class_name StatCheckResolver
extends RefCounted
## Converts semantic difficulty + current Act into required successes (DC) and dice pool modifiers.
## Used by dialog skill checks; legacy JSON may still pass explicit check_dc via Difficulty.AUTO.

enum Difficulty {
	AUTO,
	TRIVIAL,
	EASY,
	MEDIUM,
	HARD,
	EXTREME,
}

## Scaling Matrix: [Act 1..3][Difficulty] -> {dc: required successes (5-6), pool: dice pool bonus}
const BALANCE_TABLE: Dictionary = {
	1: {
		Difficulty.TRIVIAL: {"dc": 1, "pool": 2},
		Difficulty.EASY: {"dc": 1, "pool": 0},
		Difficulty.MEDIUM: {"dc": 1, "pool": -1},
		Difficulty.HARD: {"dc": 2, "pool": 1},
		Difficulty.EXTREME: {"dc": 2, "pool": -1},
	},
	2: {
		Difficulty.TRIVIAL: {"dc": 1, "pool": 1},
		Difficulty.EASY: {"dc": 1, "pool": -1},
		Difficulty.MEDIUM: {"dc": 2, "pool": 1},
		Difficulty.HARD: {"dc": 2, "pool": -1},
		Difficulty.EXTREME: {"dc": 3, "pool": 0},
	},
	3: {
		Difficulty.TRIVIAL: {"dc": 1, "pool": -1},
		Difficulty.EASY: {"dc": 2, "pool": 1},
		Difficulty.MEDIUM: {"dc": 2, "pool": -1},
		Difficulty.HARD: {"dc": 3, "pool": 0},
		Difficulty.EXTREME: {"dc": 3, "pool": -2},
	},
}


static func string_to_difficulty(diff_str: String) -> Difficulty:
	match diff_str.strip_edges().to_upper():
		"TRIVIAL":
			return Difficulty.TRIVIAL
		"EASY":
			return Difficulty.EASY
		"MEDIUM":
			return Difficulty.MEDIUM
		"HARD":
			return Difficulty.HARD
		"EXTREME":
			return Difficulty.EXTREME
		_:
			return Difficulty.AUTO


static func resolve_check_params(
	_stat_name: String,
	difficulty: Difficulty,
	act_number: int,
	explicit_dc: int = 0,
	explicit_pool_bonus: int = 0
) -> Dictionary:
	## Fallback/override for legacy encounters with fixed check_dc.
	if difficulty == Difficulty.AUTO and explicit_dc > 0:
		return {
			"dc": explicit_dc,
			"pool_bonus": explicit_pool_bonus,
		}

	var clamped_act: int = clampi(act_number, 1, 3)
	var act_matrix: Dictionary = BALANCE_TABLE.get(clamped_act, BALANCE_TABLE[1])
	var target_diff: Difficulty = (
		difficulty if difficulty != Difficulty.AUTO else Difficulty.MEDIUM
	)
	var config: Dictionary = act_matrix.get(target_diff, {"dc": 1, "pool": 0})

	return {
		"dc": int(config.get("dc", 1)),
		"pool_bonus": int(config.get("pool", 0)) + explicit_pool_bonus,
	}
