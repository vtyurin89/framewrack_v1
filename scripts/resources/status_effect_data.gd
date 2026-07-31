class_name StatusEffectData
extends Resource
## Blueprint for a combat status effect (poison, rust, stun, …).

enum StackType {
	STACKS,
	DURATION,
}

enum TriggerPhase {
	PRE_TURN_NEGATIVE,
	START_TURN_POSITIVE,
	ON_ATTACK,
	ON_TAKE_DAMAGE,
	POST_TURN,
}

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var is_debuff: bool = true
@export var stack_type: StackType = StackType.STACKS
@export var trigger_phase: TriggerPhase = TriggerPhase.PRE_TURN_NEGATIVE
@export var base_value: int = 1
## -1 = unlimited stacks.
@export var max_stacks: int = -1


func get_display_title() -> String:
	if not title.is_empty():
		return title
	return id.capitalize()


func get_display_description(stacks: int = 1, duration: int = 1) -> String:
	var text := description
	if text.is_empty():
		return ""
	return (
		text
		.replace("{stacks}", str(stacks))
		.replace("{duration}", str(duration))
		.replace("{base_value}", str(base_value))
		.replace("{value}", str(base_value * maxi(stacks, 1)))
	)


func get_ui_glyph() -> String:
	match id.strip_edges().to_lower():
		"poison":
			return "🧪"
		"burn":
			return "🔥"
		"stun":
			return "💫"
		"weakness":
			return "💀"
		"vulnerability":
			return "💥"
		"rust":
			return "⚙️"
		"healing", "repair":
			return "💚"
		"thorns":
			return "🌵"
		"ferocity":
			return "🩸"
		"evasion":
			return "🌀"
		"fleeing":
			return "👢"
		"summoned_creature":
			return "🔗"
		"frenzy":
			return "😡"
		"bleed":
			return "🩸"
		"slow":
			return "🐢"
		_:
			return "•"
