class_name EnemyInstance
extends RefCounted
## Runtime enemy: difficulty-scaled HP, stats, ability rolls, and AI selection.

const CRIT_DAMAGE_MULT := 1.3
const MIN_STAT := 1

var data: EnemyData
var strength: int = 1
var agility: int = 1
var endurance: int = 1
var intelligence: int = 1
var luck: int = 1
var max_hp: int = 1
var current_hp: int = 1
var current_block: int = 0
var burn: int = 0
var is_selected: bool = false
var abilities: Array[EnemyAbility] = []


func setup(blueprint: EnemyData) -> void:
	data = blueprint
	if data == null:
		strength = MIN_STAT
		agility = MIN_STAT
		endurance = MIN_STAT
		intelligence = MIN_STAT
		luck = MIN_STAT
		max_hp = 1
		current_hp = 1
		abilities.clear()
		return

	strength = maxi(MIN_STAT, data.strength)
	agility = maxi(MIN_STAT, data.agility)
	endurance = maxi(MIN_STAT, data.endurance)
	intelligence = maxi(MIN_STAT, data.intelligence)
	luck = maxi(MIN_STAT, data.luck)

	var hp_mult := 1.0
	if GameSettings != null:
		hp_mult = GameSettings.get_enemy_hp_multiplier()
	var raw_hp := float(data.get_effective_base_hp()) + float(endurance) * 10.0
	max_hp = maxi(1, int(round(raw_hp * hp_mult)))
	current_hp = max_hp
	current_block = 0
	burn = 0
	is_selected = false

	abilities.clear()
	for ability: EnemyAbility in data.abilities:
		if ability != null:
			abilities.append(ability)


func get_localized_name() -> String:
	if data != null:
		return data.get_localized_name()
	return tr("ENEMY_UNKNOWN_NAME")


func get_localized_description() -> String:
	if data != null:
		return data.get_localized_description()
	return ""


func get_crit_chance() -> float:
	## Crit chance = max(0, (luck - 1) * 0.05).
	return maxf(0.0, float(luck - 1) * 0.05)


func roll_crit() -> bool:
	var chance := get_crit_chance()
	if chance <= 0.0:
		return false
	return randf() < chance


func get_stat(scaling: EnemyAbility.StatScaling) -> int:
	match scaling:
		EnemyAbility.StatScaling.STRENGTH:
			return strength
		EnemyAbility.StatScaling.AGILITY:
			return agility
		EnemyAbility.StatScaling.ENDURANCE:
			return endurance
		EnemyAbility.StatScaling.INTELLIGENCE:
			return intelligence
		EnemyAbility.StatScaling.LUCK:
			return luck
		_:
			return 0


func get_ability_value_range(ability: EnemyAbility) -> Vector2i:
	if ability == null:
		return Vector2i.ZERO
	var r := ability.get_clamped_range()
	var stat := get_stat(ability.stat_scaling)
	return Vector2i(r.x + stat, r.y + stat)


func format_ability_tooltip(ability: EnemyAbility) -> String:
	if ability == null:
		return ""
	var r := ability.get_clamped_range()
	var scaled := get_ability_value_range(ability)
	var stat := get_stat(ability.stat_scaling)
	var stat_key := ability.stat_label_key()
	var action_verb := tr("KEY_ABILITY_DEALS")
	match ability.type:
		EnemyAbility.AbilityType.BLOCK:
			action_verb = tr("KEY_ABILITY_BLOCKS")
		EnemyAbility.AbilityType.HEAL:
			action_verb = tr("KEY_ABILITY_HEALS")
		EnemyAbility.AbilityType.SPECIAL:
			action_verb = tr("KEY_ABILITY_SPECIAL")
		_:
			action_verb = tr("KEY_ABILITY_DEALS")
	if stat > 0 and not stat_key.is_empty():
		return tr("KEY_ABILITY_RANGE_STAT_FMT") % [
			action_verb,
			scaled.x,
			scaled.y,
			r.x,
			r.y,
			stat,
			tr(stat_key),
		]
	return tr("KEY_ABILITY_RANGE_FMT") % [action_verb, scaled.x, scaled.y, r.x, r.y]


func choose_ability() -> EnemyAbility:
	if abilities.is_empty():
		return null
	var total := 0.0
	var weights: Array[float] = []
	for ability: EnemyAbility in abilities:
		var w := ability.base_ai_weight
		if GameSettings != null:
			w *= GameSettings.get_ability_weight_multiplier(int(ability.weight_class))
		w = maxf(0.01, w)
		weights.append(w)
		total += w
	var roll := randf() * total
	var cursor := 0.0
	for i in abilities.size():
		cursor += weights[i]
		if roll <= cursor:
			return abilities[i]
	return abilities[abilities.size() - 1]


func resolve_ability(ability: EnemyAbility) -> Dictionary:
	## Returns { amount, is_crit, base_roll, stat, type, ability }.
	var result := {
		"amount": 0,
		"is_crit": false,
		"base_roll": 0,
		"stat": 0,
		"type": EnemyAbility.AbilityType.DAMAGE,
		"ability": ability,
	}
	if ability == null:
		return result

	var base_roll := ability.roll_base()
	var stat := get_stat(ability.stat_scaling)
	var raw := base_roll + stat
	var is_crit := roll_crit()
	var amount := raw
	if is_crit:
		amount = int(round(float(raw) * CRIT_DAMAGE_MULT))

	match ability.type:
		EnemyAbility.AbilityType.DAMAGE, EnemyAbility.AbilityType.SPECIAL:
			if GameSettings != null:
				amount = int(round(float(amount) * GameSettings.get_enemy_damage_multiplier()))
		_:
			pass

	result["amount"] = maxi(0, amount)
	result["is_crit"] = is_crit
	result["base_roll"] = base_roll
	result["stat"] = stat
	result["type"] = ability.type
	return result


func apply_incoming_damage(amount: int) -> int:
	## Absorb with enemy block first; returns HP lost.
	var remaining := maxi(0, amount)
	if current_block > 0:
		var absorbed := mini(current_block, remaining)
		current_block -= absorbed
		remaining -= absorbed
	var before := current_hp
	current_hp = maxi(0, current_hp - remaining)
	return before - current_hp


func gain_block(amount: int) -> void:
	if amount > 0:
		current_block += amount


func heal(amount: int) -> int:
	if amount <= 0:
		return 0
	var before := current_hp
	current_hp = mini(max_hp, current_hp + amount)
	return current_hp - before


func is_alive() -> bool:
	return current_hp > 0
