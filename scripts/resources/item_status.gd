class_name ItemStatus
extends RefCounted
## Runtime status effect attached to a placed body-grid item (cooldown, overload, …).

enum Type {
	COOLDOWN,
	OVERLOAD,
	TAINTED,
}

const TYPE_IDS := {
	Type.COOLDOWN: "COOLDOWN",
	Type.OVERLOAD: "OVERLOAD",
	Type.TAINTED: "TAINTED",
}

var type: Type = Type.COOLDOWN
## Turns remaining before this status expires (decremented by tick_turn).
var remaining_turns: int = 1
## Optional payload, e.g. { "damage": 1 } or { "lightning_icon": true }.
var args: Dictionary = {}


func _init(
	p_type: Type = Type.COOLDOWN,
	p_remaining_turns: int = 1,
	p_args: Dictionary = {}
) -> void:
	type = p_type
	remaining_turns = p_remaining_turns
	args = p_args.duplicate(true)


static func from_id(type_id: String, p_remaining_turns: int = 1, p_args: Dictionary = {}) -> ItemStatus:
	return ItemStatus.new(parse_type_id(type_id), p_remaining_turns, p_args)


static func parse_type_id(type_id: String) -> Type:
	match type_id.strip_edges().to_upper():
		"OVERLOAD":
			return Type.OVERLOAD
		"TAINTED":
			return Type.TAINTED
		_:
			return Type.COOLDOWN


func get_type_id() -> String:
	return str(TYPE_IDS.get(type, "COOLDOWN"))


func tick_turn() -> void:
	remaining_turns = maxi(0, remaining_turns - 1)


func is_expired() -> bool:
	return remaining_turns <= 0


func blocks_activation() -> bool:
	return type == Type.COOLDOWN or type == Type.OVERLOAD


func get_taint_damage() -> int:
	if type != Type.TAINTED:
		return 0
	return maxi(1, int(args.get("damage", 1)))
