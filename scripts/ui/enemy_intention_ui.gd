class_name EnemyIntentionUI
extends Control
## Rich StS-style intention panel: emoji icon + value + hybrid/debuff badges.

signal pop_finished

const POP_DURATION := 0.28
const FADE_OUT_DURATION := 0.2
const THINKING_DURATION := 0.4
const FADE_IN_DURATION := 0.3

var _intention: CombatIntention
var _hidden_for_enemy_turn: bool = false
var _transition_token: int = 0
var _active_tween: Tween

@onready var _root: Control = %IntentRoot
@onready var _icon: Label = %IntentIcon
@onready var _value: Label = %IntentValue
@onready var _badges: HBoxContainer = %IntentBadges


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _root:
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.pivot_offset = _root.custom_minimum_size * 0.5
	visible = false
	modulate.a = 1.0
	scale = Vector2.ONE


func set_intention(intention: CombatIntention, animate_transition: bool = false) -> void:
	if animate_transition and visible and _intention != null and not _intention.is_empty():
		play_reevaluate_transition(intention)
		return
	_intention = intention
	_refresh()


func clear_intention() -> void:
	_transition_token += 1
	_kill_active_tween()
	_intention = null
	_refresh()


func set_enemy_turn_hidden(hidden: bool) -> void:
	_hidden_for_enemy_turn = hidden
	if hidden:
		_transition_token += 1
		_kill_active_tween()
	_refresh_visibility()


func _refresh() -> void:
	if _intention == null or _intention.is_empty():
		_icon.text = ""
		_value.text = ""
		_clear_badges()
		_refresh_visibility()
		return

	if _intention.is_secret or _intention.primary_type == CombatIntention.Type.SECRET:
		_icon.text = "?"
		_value.text = ""
		_clear_badges()
		_refresh_visibility()
		return

	_icon.text = _intention.get_icon_glyph()
	match _intention.primary_type:
		CombatIntention.Type.ATTACK:
			_value.text = _intention.get_damage_text()
		CombatIntention.Type.DEFEND:
			_value.text = str(_intention.block_value) if _intention.block_value > 0 else ""
		CombatIntention.Type.HEAL:
			_value.text = str(_intention.heal_value) if _intention.heal_value > 0 else ""
		CombatIntention.Type.BUFF:
			_value.text = ""
		CombatIntention.Type.DEBUFF:
			if not _intention.applied_debuffs.is_empty():
				var d: Dictionary = _intention.applied_debuffs[0]
				var status_id := str(d.get("type", "debuff"))
				var stacks := int(d.get("stacks", 1))
				_value.text = "%s %d" % [status_id.capitalize(), stacks]
			else:
				_value.text = ""
		_:
			_value.text = ""

	_rebuild_badges()
	_refresh_visibility()


func _refresh_visibility() -> void:
	var has_content := (
		_intention != null
		and not _intention.is_empty()
		and not _hidden_for_enemy_turn
	)
	visible = has_content
	if has_content and _root:
		_root.pivot_offset = size * 0.5 if size.x > 0.0 else Vector2(40, 18)
		modulate.a = 1.0
		_root.scale = Vector2.ONE


func _clear_badges() -> void:
	if _badges == null:
		return
	for child in _badges.get_children():
		child.queue_free()


func _rebuild_badges() -> void:
	_clear_badges()
	if _badges == null or _intention == null or _intention.is_secret:
		return

	## Hybrid block badge when attack/heal also grants shield.
	if (
		_intention.block_value > 0
		and _intention.primary_type != CombatIntention.Type.DEFEND
	):
		_badges.add_child(_make_badge("🛡️ %d" % _intention.block_value, Color(0.55, 0.75, 1.0)))

	## Debuff badges for hybrid attack+status (primary already shows DEBUFF text).
	if _intention.primary_type != CombatIntention.Type.DEBUFF:
		for debuff in _intention.applied_debuffs:
			var status_id := str(debuff.get("type", ""))
			var stacks := int(debuff.get("stacks", 1))
			var glyph := _intention.get_debuff_glyph(status_id)
			_badges.add_child(_make_badge("%s %d" % [glyph, stacks], Color(0.85, 0.55, 1.0)))


func _make_badge(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	return label


func play_pop_in() -> void:
	## Scale pop: 0 → 1.2 → 1.0 with BACK ease (turn-start stagger).
	_transition_token += 1
	_kill_active_tween()
	if not visible:
		_refresh_visibility()
	if not visible:
		pop_finished.emit()
		return
	var target := _root if _root != null else self
	modulate.a = 1.0
	target.scale = Vector2.ZERO
	target.pivot_offset = target.size * 0.5
	_active_tween = create_tween()
	_active_tween.set_trans(Tween.TRANS_BACK)
	_active_tween.set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(target, "scale", Vector2(1.2, 1.2), POP_DURATION * 0.65)
	_active_tween.tween_property(target, "scale", Vector2.ONE, POP_DURATION * 0.35)
	await _active_tween.finished
	pop_finished.emit()


func play_reevaluate_transition(next_intention: CombatIntention) -> void:
	## Fade out → ??? thinking pulse → fade/pop in new intention.
	_transition_token += 1
	var token := _transition_token
	_kill_active_tween()

	visible = true
	var target := _root if _root != null else self
	target.scale = Vector2.ONE
	target.pivot_offset = target.size * 0.5 if target.size.x > 0.0 else Vector2(40, 18)
	modulate.a = 1.0

	## Step 1: fade out current intention.
	_active_tween = create_tween()
	_active_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_DURATION).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN)
	await _active_tween.finished
	if token != _transition_token or not is_instance_valid(self):
		return

	## Step 2: thinking phase with ??? pulse.
	_icon.text = "???"
	_value.text = ""
	_clear_badges()
	modulate.a = 1.0
	target.scale = Vector2.ONE
	_active_tween = create_tween()
	_active_tween.set_loops(2)
	_active_tween.tween_property(target, "scale", Vector2(1.15, 1.15), THINKING_DURATION * 0.25).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)
	_active_tween.tween_property(target, "scale", Vector2(0.92, 0.92), THINKING_DURATION * 0.25).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)
	await _active_tween.finished
	if token != _transition_token or not is_instance_valid(self):
		return

	## Step 3: apply new data and fade/pop in.
	_intention = next_intention
	_refresh()
	if _hidden_for_enemy_turn or _intention == null or _intention.is_empty():
		modulate.a = 1.0
		target.scale = Vector2.ONE
		pop_finished.emit()
		return

	visible = true
	modulate.a = 0.0
	target.scale = Vector2(0.6, 0.6)
	target.pivot_offset = target.size * 0.5
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	_active_tween.tween_property(self, "modulate:a", 1.0, FADE_IN_DURATION).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(target, "scale", Vector2.ONE, FADE_IN_DURATION).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	await _active_tween.finished
	if token != _transition_token or not is_instance_valid(self):
		return
	target.scale = Vector2.ONE
	modulate.a = 1.0
	pop_finished.emit()


func hide_instant() -> void:
	_transition_token += 1
	_kill_active_tween()
	visible = false
	modulate.a = 1.0
	var target := _root if _root != null else self
	target.scale = Vector2.ONE


func _kill_active_tween() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null
