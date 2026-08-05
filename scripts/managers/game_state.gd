class_name RunCurrencyState
extends RefCounted
## Neuro-Chip currency + modifiers (owned by GameManager).
## File kept as game_state.gd per design; not an autoload (avoids GameManager.GameState clash).

signal chips_changed(new_amount: int)
signal chip_modifiers_changed

var neuro_chips: int = 0
## Additive bonus on gains (0.15 = +15% from all sources via add_chips).
var chip_bonus_multiplier: float = 0.0
## Absolute block — add_chips / combat awards grant nothing while true.
var is_chip_gain_blocked: bool = false

const STARTING_CHIPS := 30

const BASE_CHIPS_NORMAL := 8
const BASE_CHIPS_ELITE := 18
const BASE_CHIPS_BOSS := 40
const CHIPS_PER_DEPTH := 2


func reset_run() -> void:
	neuro_chips = STARTING_CHIPS
	chip_bonus_multiplier = 0.0
	is_chip_gain_blocked = false
	chips_changed.emit(neuro_chips)
	chip_modifiers_changed.emit()


func get_chips() -> int:
	return neuro_chips


func set_chip_bonus_multiplier(value: float) -> void:
	chip_bonus_multiplier = value
	chip_modifiers_changed.emit()


func add_chip_bonus_multiplier(delta: float) -> void:
	chip_bonus_multiplier += delta
	chip_modifiers_changed.emit()


func set_chip_gain_blocked(blocked: bool) -> void:
	is_chip_gain_blocked = blocked
	chip_modifiers_changed.emit()


func preview_chip_gain(amount: int) -> int:
	if is_chip_gain_blocked or amount <= 0:
		return 0
	return maxi(0, int(floor(float(amount) * (1.0 + chip_bonus_multiplier))))


func add_chips(amount: int) -> int:
	if is_chip_gain_blocked or amount <= 0:
		return 0
	var final_amount: int = preview_chip_gain(amount)
	if final_amount <= 0:
		return 0
	neuro_chips += final_amount
	chips_changed.emit(neuro_chips)
	return final_amount


func restore_chips(amount: int) -> int:
	## Refund without bonus / block (theft recovery).
	if amount <= 0:
		return 0
	neuro_chips += amount
	chips_changed.emit(neuro_chips)
	return amount


func spend_chips(amount: int) -> bool:
	if amount <= 0:
		return true
	if neuro_chips < amount:
		return false
	neuro_chips -= amount
	chips_changed.emit(neuro_chips)
	return true


func take_chips(amount: int) -> int:
	## Theft: remove up to amount. Returns taken.
	if amount <= 0 or neuro_chips <= 0:
		return 0
	var taken: int = mini(neuro_chips, amount)
	neuro_chips -= taken
	chips_changed.emit(neuro_chips)
	return taken


func calculate_combat_chip_base(encounter_kind: String, act_depth: int) -> int:
	var kind := encounter_kind.strip_edges().to_upper()
	var base: int = BASE_CHIPS_NORMAL
	match kind:
		"ELITE", "COMBAT_ELITE":
			base = BASE_CHIPS_ELITE
		"BOSS", "COMBAT_BOSS":
			base = BASE_CHIPS_BOSS
		_:
			base = BASE_CHIPS_NORMAL
	return maxi(0, base + maxi(act_depth, 0) * CHIPS_PER_DEPTH)


func calculate_combat_chip_reward(encounter_kind: String, act_depth: int) -> int:
	return preview_chip_gain(calculate_combat_chip_base(encounter_kind, act_depth))


func award_combat_chips(encounter_kind: String, act_depth: int) -> int:
	return add_chips(calculate_combat_chip_base(encounter_kind, act_depth))
