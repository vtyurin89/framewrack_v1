class_name CombatIntention
extends RefCounted
## Slay-the-Spire-style telegraph for an enemy's committed next action.

enum Type {
	ATTACK,
	DEFEND,
	HEAL,
	BUFF,
	DEBUFF,
	SECRET,
	UNKNOWN,
}

var primary_type: Type = Type.UNKNOWN
## Per-hit damage preview (min, max). Zero when not an attack.
var damage_range: Vector2i = Vector2i.ZERO
var hit_count: int = 1
var block_value: int = 0
var heal_value: int = 0
## Entries: { "type": String, "stacks": int }
var applied_debuffs: Array[Dictionary] = []
var is_secret: bool = false
var source_ability: EnemyAbility = null


## Legacy aliases used by older call sites.
var type: Type:
	get:
		return primary_type
	set(value):
		primary_type = value


var value: int:
	get:
		return get_primary_value()
	set(value):
		if primary_type == Type.ATTACK:
			damage_range = Vector2i(value, value)
		elif primary_type == Type.DEFEND:
			block_value = value
		elif primary_type == Type.HEAL:
			heal_value = value


func clear() -> void:
	primary_type = Type.UNKNOWN
	damage_range = Vector2i.ZERO
	hit_count = 1
	block_value = 0
	heal_value = 0
	applied_debuffs.clear()
	is_secret = false
	source_ability = null


func is_empty() -> bool:
	return primary_type == Type.UNKNOWN and source_ability == null and not is_secret


func get_primary_value() -> int:
	match primary_type:
		Type.ATTACK:
			return damage_range.y if damage_range.y > 0 else damage_range.x
		Type.DEFEND:
			return block_value
		Type.HEAL:
			return heal_value
		Type.DEBUFF:
			if not applied_debuffs.is_empty():
				return int(applied_debuffs[0].get("stacks", 0))
			return 0
		_:
			return 0


func get_damage_text() -> String:
	if is_secret or primary_type != Type.ATTACK:
		return ""
	var lo := mini(damage_range.x, damage_range.y)
	var hi := maxi(damage_range.x, damage_range.y)
	var base := str(lo) if lo == hi else "%d-%d" % [lo, hi]
	if hit_count > 1:
		return "%s x%d" % [base, hit_count]
	return base


func get_icon_glyph() -> String:
	if is_secret:
		return "?"
	match primary_type:
		Type.ATTACK:
			return "⚔️"
		Type.DEFEND:
			return "🛡️"
		Type.HEAL:
			return "💊"
		Type.BUFF:
			return "⬆️"
		Type.DEBUFF:
			return "🧪"
		Type.SECRET:
			return "?"
		_:
			return "?"


func get_debuff_glyph(status_id: String) -> String:
	match status_id.strip_edges().to_lower():
		"poison":
			return "🧪"
		"burn":
			return "🔥"
		"rust":
			return "⚙️"
		"weak":
			return "💀"
		_:
			return "🧪"


static func from_ability(enemy: EnemyInstance, ability: EnemyAbility) -> CombatIntention:
	var intent := CombatIntention.new()
	if enemy == null or ability == null:
		intent.primary_type = Type.UNKNOWN
		return intent

	intent.source_ability = ability
	var effect := ability.infer_main_effect()
	var scaled := enemy.get_ability_value_range(ability)

	match effect:
		"damage":
			intent.primary_type = Type.ATTACK
			intent.damage_range = _apply_damage_mult(scaled)
			intent.hit_count = maxi(1, ability.hit_count)
			if ability.type == EnemyAbility.AbilityType.MULTI_HIT:
				intent.hit_count = ability.hit_count if ability.hit_count > 0 else 3
		"shield":
			intent.primary_type = Type.DEFEND
			intent.block_value = maxi(scaled.x, scaled.y)
		"heal":
			intent.primary_type = Type.HEAL
			intent.heal_value = maxi(scaled.x, scaled.y)
		"modify_stat":
			intent.primary_type = Type.BUFF
		"status":
			intent.primary_type = Type.DEBUFF
			intent.applied_debuffs = _parse_debuffs(ability, enemy, scaled)
			## Some status rows are actually attacks with a rider — keep damage if typed DAMAGE.
			if ability.type == EnemyAbility.AbilityType.DAMAGE:
				intent.primary_type = Type.ATTACK
				intent.damage_range = _apply_damage_mult(scaled)
				intent.hit_count = maxi(1, ability.hit_count)
		"summon":
			intent.primary_type = Type.SECRET
			intent.is_secret = true
		_:
			if ability.type == EnemyAbility.AbilityType.SPECIAL:
				intent.primary_type = Type.SECRET
				intent.is_secret = true
			else:
				intent.primary_type = Type.UNKNOWN

	## Hybrid: shield amount encoded alongside damage via effect_params "block|N".
	_apply_hybrid_params(intent, ability, enemy)
	return intent


static func make_secret() -> CombatIntention:
	var intent := CombatIntention.new()
	intent.primary_type = Type.SECRET
	intent.is_secret = true
	return intent


static func _apply_damage_mult(scaled: Vector2i) -> Vector2i:
	if GameSettings == null:
		return scaled
	var mult := GameSettings.get_enemy_damage_multiplier()
	return Vector2i(
		maxi(0, int(round(float(scaled.x) * mult))),
		maxi(0, int(round(float(scaled.y) * mult)))
	)


static func _parse_debuffs(
	ability: EnemyAbility, enemy: EnemyInstance, scaled: Vector2i
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var csv := ability.get_effect_param_list()
	var status_id := "poison"
	var stacks := maxi(scaled.x, scaled.y)
	if csv.size() >= 1 and str(csv[0]).strip_edges() != "":
		status_id = str(csv[0]).strip_edges().to_lower()
	if csv.size() >= 2 and str(csv[1]).is_valid_int():
		stacks = int(csv[1])
	elif stacks <= 0 and enemy != null:
		stacks = ability.roll_base() + enemy.get_stat(ability.stat_scaling)
	if status_id in ["block", "guard", "shield"]:
		return result
	result.append({"type": status_id, "stacks": maxi(1, stacks)})
	return result


static func _apply_hybrid_params(
	intent: CombatIntention, ability: EnemyAbility, enemy: EnemyInstance
) -> void:
	if ability == null:
		return
	var csv := ability.get_effect_param_list()
	for i in csv.size():
		var token := str(csv[i]).strip_edges().to_lower()
		if token in ["block", "guard", "shield"] and i + 1 < csv.size() and str(csv[i + 1]).is_valid_int():
			intent.block_value = maxi(intent.block_value, int(csv[i + 1]) + (enemy.agility if enemy else 0))
		elif token.begins_with("block:") or token.begins_with("shield:"):
			var parts := token.split(":")
			if parts.size() >= 2 and parts[1].is_valid_int():
				intent.block_value = maxi(
					intent.block_value, int(parts[1]) + (enemy.agility if enemy else 0)
				)
