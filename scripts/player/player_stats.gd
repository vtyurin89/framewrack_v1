class_name PlayerStats
extends ActorStats
## Player progression + combat attributes. Humanity is unique to the protagonist.

signal leveled_up(new_level: int)
signal pending_level_ups_changed(count: int)
signal exp_changed(
	level: int,
	current_exp: int,
	level_start_exp: int,
	next_level_exp: int,
	max_level: int
)
## Emitted when effective combat stats change (base, flat bonus, or equipment).
signal stats_changed

const MAX_LEVEL: int = 10
const XP_LEVEL_REQUIREMENTS: Array[int] = [0, 30, 70, 120, 180, 260, 360, 480, 620, 800]
const DEFAULT_BASE_HP: int = 30
const MIN_STAT: int = 1

## UNIQUE to PlayerStats — not present on EnemyData / ActorStats.
@export var humanity: int = 5

## Intrinsic frame values before flat / equipment modifiers.
var base_strength: int = 1
var base_agility: int = 1
var base_endurance: int = 2
var base_intelligence: int = 1
var base_luck: int = 1
var base_humanity: int = 5

## Permanent / consumable modifiers (accumulate via add_stat_bonus).
var _flat_bonuses: Dictionary = {}
## Rebuilt from BodyGrid equipment on recalculate_from_equipment().
var _equipment_bonuses: Dictionary = {}

var level: int = 1
var current_exp: int = 0
## Queued level-up reveals waiting for the player to confirm in Body Grid UI.
var pending_level_ups: int = 0

var max_exp: int:
	get:
		return get_next_level_exp()


func _init() -> void:
	_apply_protagonist_defaults()
	recalculate_stats()


func _apply_protagonist_defaults() -> void:
	## Starting frame: END 2 → Max HP 40 with base 30.
	base_strength = 1
	base_agility = 1
	base_endurance = 2
	base_intelligence = 1
	base_luck = 1
	base_humanity = 5
	_flat_bonuses.clear()
	_equipment_bonuses.clear()


func get_player_max_hp() -> int:
	return get_max_hp(DEFAULT_BASE_HP)


func reset_run() -> void:
	_apply_protagonist_defaults()
	level = 1
	current_exp = 0
	pending_level_ups = 0
	recalculate_stats()
	_emit_exp_changed()
	pending_level_ups_changed.emit(pending_level_ups)


func add_stat_bonus(stat_name: String, value: int) -> void:
	## Permanent / consumable delta. Pass negative value to remove a prior bonus.
	if value == 0:
		return
	var key := _normalize_stat_key(stat_name)
	if key.is_empty():
		return
	_flat_bonuses[key] = int(_flat_bonuses.get(key, 0)) + value
	recalculate_stats()


func set_base_stat(stat_name: String, value: int) -> void:
	var key := _normalize_stat_key(stat_name)
	var clamped := maxi(MIN_STAT, value) if key != "humanity" else value
	match key:
		"strength":
			base_strength = clamped
		"agility":
			base_agility = clamped
		"endurance":
			base_endurance = clamped
		"intelligence":
			base_intelligence = clamped
		"luck":
			base_luck = clamped
		"humanity":
			base_humanity = value
		_:
			return
	recalculate_stats()


func recalculate_from_equipment(grid: BodyGrid) -> void:
	## Rebuild equipment modifiers from functional body-grid modules, then refresh.
	_equipment_bonuses.clear()
	if grid != null:
		for placed: PlacedItem in grid.items:
			if placed == null or placed.data == null:
				continue
			if not grid.is_item_functional(placed):
				continue
			var mods: Dictionary = placed.data.get_equipment_stat_modifiers()
			for stat_key in mods.keys():
				var key := _normalize_stat_key(str(stat_key))
				if key.is_empty():
					continue
				_equipment_bonuses[key] = int(_equipment_bonuses.get(key, 0)) + int(mods[stat_key])
	recalculate_stats()


func recalculate_stats() -> void:
	## Effective = base + flat bonuses + equipment bonuses.
	strength = maxi(MIN_STAT, base_strength + _bonus_total("strength"))
	agility = maxi(MIN_STAT, base_agility + _bonus_total("agility"))
	endurance = maxi(MIN_STAT, base_endurance + _bonus_total("endurance"))
	intelligence = maxi(MIN_STAT, base_intelligence + _bonus_total("intelligence"))
	luck = maxi(MIN_STAT, base_luck + _bonus_total("luck"))
	humanity = base_humanity + _bonus_total("humanity")
	stats_changed.emit()


func format_stats_header() -> String:
	return "STR: %d | AGI: %d | END: %d | INT: %d | LCK: %d | HUM: %d" % [
		strength,
		agility,
		endurance,
		intelligence,
		luck,
		humanity,
	]


func format_stats_tooltip_body() -> String:
	## Detailed hover breakdown for the BODY GRID stats header.
	var max_hp := get_player_max_hp()
	var end_bonus := endurance * 5
	var crit_pct := get_crit_chance() * 100.0
	return "\n".join([
		"STR (%d): Physical Damage +%d" % [strength, strength],
		"AGI (%d): Shield Block +%d" % [agility, agility],
		"END (%d): Max HP %d (30 Base + %d)" % [endurance, max_hp, end_bonus],
		"INT (%d): Skill Power +%d" % [intelligence, intelligence],
		"LCK (%d): Crit Chance %.0f%%" % [luck, crit_pct],
		"HUM (%d): Humanity (Protagonist Stat)" % humanity,
	])


func _bonus_total(stat_key: String) -> int:
	return int(_flat_bonuses.get(stat_key, 0)) + int(_equipment_bonuses.get(stat_key, 0))


func _normalize_stat_key(raw: String) -> String:
	match raw.strip_edges().to_lower():
		"str", "strength":
			return "strength"
		"agi", "agility":
			return "agility"
		"end", "endurance":
			return "endurance"
		"int", "intelligence":
			return "intelligence"
		"lck", "luck":
			return "luck"
		"hum", "humanity":
			return "humanity"
		_:
			return ""


func add_exp(amount: int) -> void:
	if amount <= 0:
		return
	if level >= MAX_LEVEL:
		current_exp = _total_exp_required_for_level(MAX_LEVEL)
		_emit_exp_changed()
		return

	current_exp += amount
	var gained_levels := 0
	while level < MAX_LEVEL and current_exp >= _total_exp_required_for_level(level + 1):
		level += 1
		gained_levels += 1
		leveled_up.emit(level)

	if gained_levels > 0:
		pending_level_ups += gained_levels
		pending_level_ups_changed.emit(pending_level_ups)

	if level >= MAX_LEVEL:
		level = MAX_LEVEL
		current_exp = _total_exp_required_for_level(MAX_LEVEL)

	_emit_exp_changed()


func consume_pending_level_up() -> bool:
	## Spend one pending level-up after the player confirms the unlock reveal.
	if pending_level_ups <= 0:
		return false
	pending_level_ups -= 1
	pending_level_ups_changed.emit(pending_level_ups)
	return true


func has_pending_level_ups() -> bool:
	return pending_level_ups > 0


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
