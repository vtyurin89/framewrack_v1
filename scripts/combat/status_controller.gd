class_name StatusController
extends RefCounted
## Manages active status instances for one combatant (player or enemy).

signal statuses_updated(active_statuses: Array)

## Weakness: -25% outgoing physical damage.
const WEAKNESS_OUTGOING_MULT := 0.75
## Vulnerability: +50% incoming physical damage.
const VULN_INCOMING_MULT := 1.5
## Ferocity: crit damage multiplier override.
const FEROCITY_CRIT_MULT := 1.7
## Rust: 10% fail/miss chance per stack.
const RUST_FAIL_CHANCE_PER_STACK := 0.10

var _statuses: Array[StatusInstance] = []


func get_active_statuses() -> Array[StatusInstance]:
	var result: Array[StatusInstance] = []
	for status: StatusInstance in _statuses:
		if status != null and not status.is_expired():
			result.append(status)
	return result


func has_status(status_id: String) -> bool:
	return get_instance(status_id) != null


func get_instance(status_id: String) -> StatusInstance:
	var needle := status_id.strip_edges().to_lower()
	for status: StatusInstance in _statuses:
		if status == null or status.data == null or status.is_expired():
			continue
		if status.data.id.to_lower() == needle:
			return status
	return null


func get_stacks(status_id: String) -> int:
	var status := get_instance(status_id)
	if status == null:
		return 0
	if status.data.stack_type == StatusEffectData.StackType.DURATION:
		return status.duration
	return status.stacks


func apply_status(data: StatusEffectData, amount: int = 1) -> StatusInstance:
	if data == null or amount == 0:
		return null
	var existing := get_instance(data.id)
	if existing != null:
		existing.add_amount(amount)
		_prune_expired()
		_emit_updated()
		return existing
	var created := StatusInstance.new(data, amount)
	_statuses.append(created)
	_emit_updated()
	return created


func apply_status_by_id(status_id: String, amount: int = 1) -> StatusInstance:
	if StatusEffectDatabase == null:
		return null
	var data: StatusEffectData = StatusEffectDatabase.get_status(status_id)
	if data == null:
		push_warning("StatusController: unknown status id '%s'" % status_id)
		return null
	return apply_status(data, amount)


func clear_combat_statuses() -> void:
	_statuses.clear()
	_emit_updated()


func clear_debuffs() -> void:
	var kept: Array[StatusInstance] = []
	for status: StatusInstance in _statuses:
		if status == null or status.data == null or status.is_expired():
			continue
		if not status.data.is_debuff:
			kept.append(status)
	_statuses = kept
	_emit_updated()


## --- Phase ticks -----------------------------------------------------------

func tick_negative_statuses() -> Dictionary:
	## Returns { damage: int, skip_turn: bool, logs: PackedStringArray }.
	var damage := 0
	var skip_turn := false
	var logs: PackedStringArray = []

	var poison := get_instance("poison")
	if poison != null and poison.stacks > 0:
		damage += poison.stacks
		logs.append("poison:%d" % poison.stacks)
		poison.stacks = maxi(0, poison.stacks - 1)

	var burn := get_instance("burn")
	if burn != null and burn.stacks > 0:
		damage += burn.stacks
		logs.append("burn:%d" % burn.stacks)
		burn.stacks = 0

	var stun := get_instance("stun")
	if stun != null and stun.duration > 0:
		skip_turn = true
		logs.append("stun:%d" % stun.duration)
		stun.duration = maxi(0, stun.duration - 1)

	## Duration-based ON_ATTACK / ON_TAKE_DAMAGE debuffs tick down at pre-turn too
	## so they expire after their stated turns (weakness / vulnerability).
	_tick_duration_for_phase(StatusEffectData.TriggerPhase.ON_ATTACK)
	_tick_duration_for_phase(StatusEffectData.TriggerPhase.ON_TAKE_DAMAGE)

	_prune_expired()
	_emit_updated()
	return {"damage": damage, "skip_turn": skip_turn, "logs": logs}


func tick_positive_statuses() -> Dictionary:
	## Returns { heal: int, logs: PackedStringArray }.
	var heal_amount := 0
	var logs: PackedStringArray = []
	for status: StatusInstance in get_active_statuses():
		if status.data == null:
			continue
		if status.data.trigger_phase != StatusEffectData.TriggerPhase.START_TURN_POSITIVE:
			continue
		var id := status.data.id.to_lower()
		if id in ["healing", "repair"]:
			var amount := maxi(1, status.data.base_value)
			heal_amount += amount
			logs.append("%s:%d" % [id, amount])
			if status.data.stack_type == StatusEffectData.StackType.DURATION:
				status.duration = maxi(0, status.duration - 1)
	_prune_expired()
	_emit_updated()
	return {"heal": heal_amount, "logs": logs}


func tick_post_turn() -> void:
	_tick_duration_for_phase(StatusEffectData.TriggerPhase.POST_TURN)
	_prune_expired()
	_emit_updated()


## --- Combat modifiers ------------------------------------------------------

func modify_outgoing_damage(amount: int) -> int:
	if amount <= 0:
		return 0
	var result := float(amount)
	if has_status("weakness"):
		result *= WEAKNESS_OUTGOING_MULT
	return maxi(0, int(round(result)))


func modify_incoming_damage(amount: int) -> int:
	if amount <= 0:
		return 0
	var result := float(amount)
	if has_status("vulnerability"):
		result *= VULN_INCOMING_MULT
	return maxi(0, int(round(result)))


func get_crit_damage_multiplier(default_mult: float = 1.4) -> float:
	if has_status("ferocity"):
		return FEROCITY_CRIT_MULT
	return default_mult


func roll_rust_fail() -> bool:
	## True = jam (player) or miss (enemy).
	var rust_stacks := get_stacks("rust")
	if rust_stacks <= 0:
		return false
	return randf() < clampf(float(rust_stacks) * RUST_FAIL_CHANCE_PER_STACK, 0.0, 1.0)


func get_thorns_reflect() -> int:
	## Damage reflected to attacker on take-damage.
	return get_stacks("thorns")


## --- Internals -------------------------------------------------------------

func _tick_duration_for_phase(phase: StatusEffectData.TriggerPhase) -> void:
	for status: StatusInstance in _statuses:
		if status == null or status.data == null or status.is_expired():
			continue
		if status.data.stack_type != StatusEffectData.StackType.DURATION:
			continue
		if status.data.trigger_phase != phase:
			continue
		## Stun is handled explicitly in tick_negative_statuses.
		if status.data.id.to_lower() == "stun":
			continue
		status.duration = maxi(0, status.duration - 1)


func _prune_expired() -> void:
	var kept: Array[StatusInstance] = []
	for status: StatusInstance in _statuses:
		if status != null and not status.is_expired():
			kept.append(status)
	_statuses = kept


func _emit_updated() -> void:
	var active: Array = []
	for status: StatusInstance in get_active_statuses():
		active.append(status)
	statuses_updated.emit(active)
