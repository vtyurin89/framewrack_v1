class_name BurnStatus
extends RefCounted
## Burn: stacks = remaining turns of fire.
## Each turn start deals fixed DAMAGE_PER_TURN, then stacks decrease by 1.

const STATUS_ID := "burn"
const DAMAGE_PER_TURN: int = 2


static func tick(stacks: int) -> Dictionary:
	## Returns { damage: int, stacks_after: int }.
	if stacks <= 0:
		return {"damage": 0, "stacks_after": 0}
	return {"damage": DAMAGE_PER_TURN, "stacks_after": stacks - 1}
