class_name EnemyCardUI
extends PanelContainer
## Compact combat enemy card: intention telegraph, portrait, selection, HP bar.

signal card_gui_input(event: InputEvent, enemy_index: int)
signal death_fade_finished(card: EnemyCardUI)
signal attack_impact

const SELECT_COLOR := Color("#A8F0A8") ## PHOSPHOR_BRIGHT (legacy; reticle is shared)
const BAR_HEIGHT := 20.0
const BAR_MIN_WIDTH := 170.0
const SPRITE_DIR := "res://assets/sprites/enemies/"
const HIT_FX_TEXTURE := preload("res://assets/sprites/fx/hit_slash.png")
const HIT_FX_DURATION := 0.35
## Local brackets disabled — CombatUI owns the shared TargetReticle.
const BRACKET_THICKNESS := 1.25
const BRACKET_SPAN := 0.22
const BRACKET_PAD := 3.0
const DEATH_FADE_DURATION := 0.45
const ATTACK_LUNGE_DURATION := 0.15
const ATTACK_RETURN_DURATION := 0.2
const ATTACK_LUNGE_SCALE := 1.25
const ATTACK_LUNGE_Y := 18.0
const FLEE_DURATION := 0.5
const FLEE_SLIDE_X := 300.0
const HEAL_FLASH_DURATION := 0.4
const HEAL_FLASH_COLOR := Color(1.15, 1.35, 1.15, 1.0)
const CAST_PULSE_DURATION := 0.28
const CAST_PULSE_SCALE := 1.08
const INTENTION_SCENE := preload("res://scenes/UI/enemy_intention_ui.tscn")
const STATUS_EFFECTS_SCENE := preload("res://scenes/UI/status_effects_ui.tscn")

var enemy_index: int = -1
var _enemy: EnemyInstance
var _is_selected: bool = false
var _is_dying: bool = false
var _has_fled: bool = false

@onready var _combat_text_host: Control = %CombatTextHost
@onready var _intention_host: Control = %IntentionHost
@onready var _placeholder: ColorRect = %Placeholder
@onready var _sprite_host: Control = %SpriteHost
@onready var _sprite: TextureRect = %Sprite
@onready var _hit_fx: TextureRect = %HitFx
@onready var _ghost_hp: GhostProgressBar = %GhostHPBar
@onready var _block_badge: EnemyBlockBadge = %BlockBadge
@onready var _selection_overlay: Control = %SelectionOverlay
@onready var _status_host: HBoxContainer = %StatusHost

var _intention_ui: EnemyIntentionUI
var _statuses_ui: StatusEffectsUI
var _hit_fx_tween: Tween
var _action_tween: Tween
var _heal_tween: Tween
var _filtered_texture_cache: Dictionary = {}
var _displayed_hp: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = false
	_apply_panel_style()
	_ensure_intention_ui()
	if _ghost_hp:
		_ghost_hp.bar_min_size = Vector2(BAR_MIN_WIDTH, BAR_HEIGHT)
		_ghost_hp.show_label = true
	if _sprite:
		_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _hit_fx:
		_hit_fx.texture = HIT_FX_TEXTURE
		_hit_fx.visible = false
		_hit_fx.modulate.a = 0.0
		_hit_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hit_fx.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_hit_fx.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_hit_fx.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _placeholder:
		_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _selection_overlay:
		_selection_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		## Brackets drawn by CombatUI TargetReticle (animated shared reticle).
	if _ghost_hp:
		_ghost_hp.segmented = false
		_ghost_hp.show_label = true
	gui_input.connect(_on_gui_input)


func setup(enemy: EnemyInstance, index: int, selected: bool) -> void:
	_enemy = enemy
	enemy_index = index
	_is_dying = false
	if not is_node_ready():
		await ready
	_ensure_intention_ui()
	_ensure_statuses_ui()
	if _ghost_hp:
		_ghost_hp.segmented = false
		_ghost_hp.show_label = true
		_ghost_hp.bar_min_size = Vector2(BAR_MIN_WIDTH, BAR_HEIGHT)
	_refresh_presentation(selected)
	if enemy != null:
		set_hp(enemy.current_hp, enemy.max_hp, false)
		set_block(enemy.current_block)
		set_intention(enemy.current_intention)
		if _statuses_ui:
			_statuses_ui.bind_controller(enemy.statuses)
	else:
		set_hp(0, 1, false)
		set_block(0)
		set_intention(null)
		if _statuses_ui:
			_statuses_ui.unbind()


func is_dying() -> bool:
	return _is_dying


func is_selected_target() -> bool:
	return _is_selected


func get_enemy() -> EnemyInstance:
	return _enemy


func get_combat_text_host() -> Control:
	return _combat_text_host if _combat_text_host != null else self


func set_selected(selected: bool) -> void:
	_is_selected = selected and not _is_dying
	## Shared TargetReticle in CombatUI handles bracket visuals.


func set_hp(current: int, maximum: int, animate: bool = true) -> void:
	if _is_dying:
		return
	var max_hp := maxi(maximum, 1)
	var cur := clampi(current, 0, max_hp)
	## Only animate the HP bar when HP actually changes (block-only hits skip the drain).
	var should_animate := animate and cur != _displayed_hp and _displayed_hp >= 0
	_displayed_hp = cur
	if _ghost_hp:
		if should_animate:
			_ghost_hp.set_hp_animated(cur, max_hp)
		else:
			_ghost_hp.snap_hp(cur, max_hp)
	if cur <= 0:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		if not (_heal_tween != null and _heal_tween.is_valid()):
			modulate = Color.WHITE
		mouse_filter = Control.MOUSE_FILTER_STOP


func set_block(amount: int) -> void:
	if _block_badge == null:
		return
	_block_badge.set_block(amount)

func play_heal_effect(amount: int) -> void:
	## Green flash + floating +N for heals / mass repair.
	if _is_dying or _has_fled:
		return
	if _heal_tween != null and _heal_tween.is_valid():
		_heal_tween.kill()
	modulate = HEAL_FLASH_COLOR
	_heal_tween = create_tween()
	_heal_tween.tween_property(self, "modulate", Color.WHITE, HEAL_FLASH_DURATION).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_OUT)
	_spawn_heal_float(amount)


func play_cast_animation() -> void:
	## Soft support cast pulse (mass heal / buff wind-up).
	if _is_dying or _has_fled:
		return
	var visual := _get_attack_visual()
	if visual == null:
		return
	if _action_tween != null and _action_tween.is_valid():
		_action_tween.kill()
	var start_scale := visual.scale
	visual.pivot_offset = visual.size * 0.5
	visual.scale = Vector2.ONE
	_action_tween = create_tween()
	_action_tween.tween_property(
		visual, "scale", Vector2(CAST_PULSE_SCALE, CAST_PULSE_SCALE), CAST_PULSE_DURATION * 0.45
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_action_tween.tween_property(visual, "scale", Vector2.ONE, CAST_PULSE_DURATION * 0.55).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)
	await _action_tween.finished
	if is_instance_valid(visual):
		visual.scale = start_scale


func _spawn_heal_float(amount: int) -> void:
	var host := get_combat_text_host()
	if host == null:
		host = self
	var label := Label.new()
	label.text = "+%d" % maxi(amount, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 90
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", GamePalette.PHOSPHOR_ACTIVE)
	label.add_theme_color_override("font_outline_color", GamePalette.BACKGROUND_DARK)
	label.add_theme_constant_override("outline_size", 4)
	host.add_child(label)
	await get_tree().process_frame
	if not is_instance_valid(label):
		return
	var host_w := maxf(host.size.x, 80.0)
	var label_w := label.get_minimum_size().x
	label.position = Vector2((host_w - label_w) * 0.5, host.size.y * 0.35)
	var start_y := label.position.y
	var tween := host.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", start_y - 42.0, 0.85).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_OUT
	)
	tween.tween_property(label, "modulate:a", 0.0, 0.85).set_delay(0.2)
	tween.chain().tween_callback(label.queue_free)


func set_intention(intention: CombatIntention, animate_transition: bool = false) -> void:
	_ensure_intention_ui()
	if _intention_ui == null:
		return
	if intention == null:
		_intention_ui.clear_intention()
	else:
		_intention_ui.set_intention(intention, animate_transition)


func set_intentions_hidden(hidden: bool) -> void:
	_ensure_intention_ui()
	if _intention_ui:
		_intention_ui.set_enemy_turn_hidden(hidden)


func play_intention_pop() -> void:
	_ensure_intention_ui()
	if _intention_ui:
		await _intention_ui.play_pop_in()


func play_attack_animation() -> void:
	## First-person lunge: only the portrait scales/shifts, card chrome stays put.
	if _is_dying or _has_fled:
		return
	var visual := _get_attack_visual()
	if visual == null:
		attack_impact.emit()
		return
	if _action_tween != null and _action_tween.is_valid():
		_action_tween.kill()

	if _sprite_host:
		_sprite_host.clip_contents = false
	var start_scale := visual.scale
	var start_off_top := visual.offset_top
	var start_off_bottom := visual.offset_bottom
	visual.pivot_offset = visual.size * 0.5
	visual.scale = Vector2.ONE
	visual.z_index = 8

	_action_tween = create_tween()
	## Step 1: lunge forward (scale up + nudge toward camera).
	_action_tween.set_parallel(true)
	_action_tween.tween_property(visual, "scale", Vector2(ATTACK_LUNGE_SCALE, ATTACK_LUNGE_SCALE), ATTACK_LUNGE_DURATION).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)
	_action_tween.tween_property(visual, "offset_top", start_off_top + ATTACK_LUNGE_Y, ATTACK_LUNGE_DURATION).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)
	_action_tween.tween_property(visual, "offset_bottom", start_off_bottom + ATTACK_LUNGE_Y, ATTACK_LUNGE_DURATION).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)
	## Step 2: impact cue at peak.
	_action_tween.chain().tween_callback(func() -> void: attack_impact.emit())
	## Step 3: return to rest pose.
	_action_tween.set_parallel(true)
	_action_tween.tween_property(visual, "scale", Vector2.ONE, ATTACK_RETURN_DURATION).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_IN_OUT)
	_action_tween.tween_property(visual, "offset_top", start_off_top, ATTACK_RETURN_DURATION).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_IN_OUT)
	_action_tween.tween_property(visual, "offset_bottom", start_off_bottom, ATTACK_RETURN_DURATION).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_IN_OUT)
	await _action_tween.finished

	if not is_instance_valid(self) or not is_instance_valid(visual):
		return
	visual.scale = start_scale
	visual.offset_top = start_off_top
	visual.offset_bottom = start_off_bottom
	visual.z_index = 0


func _get_attack_visual() -> Control:
	if _sprite != null and _sprite.visible and _sprite.texture != null:
		return _sprite
	if _placeholder != null and _placeholder.visible:
		return _placeholder
	return _sprite


func play_flee_animation() -> void:
	## Slide off-screen to the right while fading out.
	if _has_fled or _is_dying:
		return
	_has_fled = true
	_is_dying = true
	_is_selected = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _selection_overlay:
		_selection_overlay.queue_redraw()
	if _intention_ui:
		_intention_ui.hide_instant()
	if _action_tween != null and _action_tween.is_valid():
		_action_tween.kill()

	var start_global := global_position
	var start_size := size
	top_level = true
	global_position = start_global
	size = start_size
	_action_tween = create_tween().set_parallel(true)
	_action_tween.tween_property(
		self, "global_position:x", start_global.x + FLEE_SLIDE_X, FLEE_DURATION
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_action_tween.tween_property(self, "modulate:a", 0.0, FLEE_DURATION).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN)
	await _action_tween.finished
	if is_instance_valid(self):
		## Keep empty slot so remaining cards do not recenter.
		top_level = false
		modulate.a = 0.0
		if get_parent() is Container:
			(get_parent() as Container).queue_sort()


func play_hit_fx(is_crit: bool = false) -> void:
	## Brief slash overlay when this enemy is struck.
	if _is_dying or _hit_fx == null:
		return
	if _hit_fx_tween != null and _hit_fx_tween.is_valid():
		_hit_fx_tween.kill()
	_hit_fx.texture = HIT_FX_TEXTURE
	_hit_fx.visible = true
	var sz := _hit_fx.size
	if sz.x < 1.0 or sz.y < 1.0:
		sz = Vector2(170, 190)
	_hit_fx.pivot_offset = sz * 0.5
	_hit_fx.scale = Vector2(0.9, 0.9)
	_hit_fx.modulate = Color(1.0, 0.82, 0.4, 1.0) if is_crit else Color(1, 1, 1, 1)
	_hit_fx_tween = create_tween()
	_hit_fx_tween.set_parallel(true)
	_hit_fx_tween.tween_property(_hit_fx, "scale", Vector2(1.12, 1.12), HIT_FX_DURATION * 0.4).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)
	_hit_fx_tween.tween_property(_hit_fx, "modulate:a", 0.0, HIT_FX_DURATION).set_delay(
		HIT_FX_DURATION * 0.15
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_hit_fx_tween.chain().tween_callback(func() -> void:
		if is_instance_valid(_hit_fx):
			_hit_fx.visible = false
			_hit_fx.scale = Vector2.ONE
	)


func play_intention_reevaluate(intention: CombatIntention) -> void:
	_ensure_intention_ui()
	if _intention_ui == null:
		return
	if intention == null:
		_intention_ui.clear_intention()
		return
	## Thinking transition only when swapping an already-visible intention.
	if _intention_ui.visible:
		await _intention_ui.play_reevaluate_transition(intention)
	else:
		_intention_ui.set_intention(intention, false)
		await _intention_ui.play_pop_in()


func play_death_fade() -> void:
	if _has_fled:
		## Flee already hid the card; still notify so the corpse can be purged.
		death_fade_finished.emit(self)
		return
	if _is_dying:
		return
	_is_dying = true
	_is_selected = false
	if _selection_overlay:
		_selection_overlay.queue_redraw()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _intention_ui:
		_intention_ui.hide_instant()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, DEATH_FADE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN
	)
	await tween.finished
	## Keep the card node as an empty slot so remaining cards do not shift in the centered row.
	death_fade_finished.emit(self)


func _ensure_intention_ui() -> void:
	if _intention_ui != null and is_instance_valid(_intention_ui):
		return
	if _intention_host == null:
		return
	for child in _intention_host.get_children():
		if child is EnemyIntentionUI:
			_intention_ui = child
			return
	_intention_ui = INTENTION_SCENE.instantiate() as EnemyIntentionUI
	_intention_host.add_child(_intention_ui)
	_intention_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_intention_ui.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ensure_statuses_ui() -> void:
	if _statuses_ui != null and is_instance_valid(_statuses_ui):
		return
	if _status_host == null:
		return
	for child in _status_host.get_children():
		if child is StatusEffectsUI:
			_statuses_ui = child
			return
	_statuses_ui = STATUS_EFFECTS_SCENE.instantiate() as StatusEffectsUI
	_status_host.add_child(_statuses_ui)


func _refresh_presentation(selected: bool) -> void:
	set_selected(selected)
	_apply_enemy_sprite()


func _draw_selection_brackets() -> void:
	## Deprecated: shared TargetReticle draws selection corners.
	pass


func _apply_enemy_sprite() -> void:
	var tex := _resolve_enemy_texture()
	if _sprite:
		_sprite.texture = tex
		_sprite.visible = tex != null
	if _placeholder:
		if tex != null:
			_placeholder.visible = false
		else:
			_placeholder.visible = true
			if _enemy != null and _enemy.data != null:
				_placeholder.color = _enemy.data.placeholder_color
			else:
				_placeholder.color = Color(0.82, 0.82, 0.85)


func _resolve_enemy_texture() -> Texture2D:
	if _enemy == null or _enemy.data == null:
		return null
	var candidates: Array[String] = []
	var csv_path := _enemy.data.sprite_path.strip_edges()
	if not csv_path.is_empty():
		candidates.append(csv_path)
	var enemy_id := _enemy.data.id.strip_edges()
	if not enemy_id.is_empty():
		var faction := _enemy.data.get_faction()
		if not faction.is_empty():
			candidates.append("%s%s/%s.png" % [SPRITE_DIR, faction, enemy_id])
		## Legacy flat path (pre-faction folders).
		candidates.append("%s%s.png" % [SPRITE_DIR, enemy_id])
	for path in candidates:
		if ResourceLoader.exists(path):
			var filtered := _load_texture_with_mipmaps(path)
			if filtered != null:
				return filtered
	return null


func _load_texture_with_mipmaps(path: String) -> Texture2D:
	if _filtered_texture_cache.has(path):
		return _filtered_texture_cache[path] as Texture2D
	var loaded: Resource = load(path)
	if loaded == null or not (loaded is Texture2D):
		return null
	var tex := loaded as Texture2D
	var image := tex.get_image()
	if image == null:
		_filtered_texture_cache[path] = tex
		return tex
	if not image.has_mipmaps():
		image.generate_mipmaps()
	var filtered := ImageTexture.create_from_image(image)
	_filtered_texture_cache[path] = filtered
	return filtered


func _apply_panel_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_border_width_all(0)
	style.set_content_margin_all(4)
	add_theme_stylebox_override("panel", style)


func _on_gui_input(event: InputEvent) -> void:
	if _is_dying:
		return
	card_gui_input.emit(event, enemy_index)
