class_name StatusInstance
extends RefCounted
## Runtime instance of an active status on a combatant.

var data: StatusEffectData
var stacks: int = 0
var duration: int = 0


func _init(p_data: StatusEffectData = null, amount: int = 1) -> void:
	data = p_data
	if data == null:
		return
	match data.stack_type:
		StatusEffectData.StackType.DURATION:
			duration = maxi(1, amount)
			stacks = 0
		StatusEffectData.StackType.PERMANENT:
			stacks = 1
			duration = 0
		_:
			stacks = maxi(1, amount)
			duration = 0
			_cap_stacks()


func get_id() -> String:
	return data.id if data != null else ""


func get_display_count() -> int:
	if data == null:
		return 0
	match data.stack_type:
		StatusEffectData.StackType.DURATION:
			return duration
		StatusEffectData.StackType.PERMANENT:
			return 0
		_:
			return stacks


func is_expired() -> bool:
	if data == null:
		return true
	match data.stack_type:
		StatusEffectData.StackType.DURATION:
			return duration <= 0
		StatusEffectData.StackType.PERMANENT:
			## Cleared only via clear_combat_statuses / explicit remove.
			return false
		_:
			return stacks <= 0


func is_permanent() -> bool:
	return data != null and data.stack_type == StatusEffectData.StackType.PERMANENT


func add_amount(amount: int) -> void:
	if data == null or amount == 0:
		return
	match data.stack_type:
		StatusEffectData.StackType.DURATION:
			duration = maxi(0, duration + amount)
		StatusEffectData.StackType.PERMANENT:
			stacks = 1
			duration = 0
		_:
			stacks = maxi(0, stacks + amount)
			_cap_stacks()


func _cap_stacks() -> void:
	if data != null and data.max_stacks > 0:
		stacks = mini(stacks, data.max_stacks)
