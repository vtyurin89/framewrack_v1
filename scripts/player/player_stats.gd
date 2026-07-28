class_name PlayerStats
extends RefCounted
## Player progression state: level and cumulative experience.

signal leveled_up(new_level: int)
signal exp_changed(
	level: int,
	current_exp: int,
	level_start_exp: int,
	next_level_exp: int,
	max_level: int
)

const MAX_LEVEL: int = 10
const XP_LEVEL_REQUIREMENTS: Array[int] = [0, 30, 70, 120, 180, 260, 360, 480, 620, 800]

var level: int = 1
var current_exp: int = 0


func reset_run() -> void:
	level = 1
	current_exp = 0
	_emit_exp_changed()


func add_exp(amount: int) -> void:
	if amount <= 0:
		return
	if level >= MAX_LEVEL:
		current_exp = _total_exp_required_for_level(MAX_LEVEL)
		_emit_exp_changed()
		return

	current_exp += amount
	while level < MAX_LEVEL and current_exp >= _total_exp_required_for_level(level + 1):
		level += 1
		leveled_up.emit(level)

	if level >= MAX_LEVEL:
		level = MAX_LEVEL
		current_exp = _total_exp_required_for_level(MAX_LEVEL)

	_emit_exp_changed()


func get_current_level_start_exp() -> int:
	return _total_exp_required_for_level(level)


func get_next_level_exp() -> int:
	if level >= MAX_LEVEL:
		return _total_exp_required_for_level(MAX_LEVEL)
	return _total_exp_required_for_level(level + 1)


func get_progress_ratio() -> float:
	if level >= MAX_LEVEL:
		return 1.0
	var start_exp := get_current_level_start_exp()
	var next_exp := get_next_level_exp()
	var span := maxi(next_exp - start_exp, 1)
	return clampf(float(current_exp - start_exp) / float(span), 0.0, 1.0)


func _emit_exp_changed() -> void:
	exp_changed.emit(
		level,
		current_exp,
		get_current_level_start_exp(),
		get_next_level_exp(),
		MAX_LEVEL
	)


func _total_exp_required_for_level(target_level: int) -> int:
	## Level 1 starts at 0 total XP.
	## Level N requires sum of all previous per-level requirements.
	var clamped_level := clampi(target_level, 1, MAX_LEVEL)
	var total := 0
	for i in range(1, clamped_level):
		total += int(XP_LEVEL_REQUIREMENTS[i])
	return total
