class_name EnemyCardUI
extends PanelContainer
## Compact combat enemy card: intention telegraph, portrait, selection, HP bar.

signal card_gui_input(event: InputEvent, enemy_index: int)
signal death_fade_finished(card: EnemyCardUI)

const FILL_COLOR := Color("#8b263e")
const BG_COLOR := Color("#121212")
const TEXT_COLOR := Color("#ffffff")
const SELECT_COLOR := Color(0.95, 0.8, 0.25)
const BAR_HEIGHT := 20.0
const BAR_MIN_WIDTH := 170.0
const SPRITE_DIR := "res://assets/sprites/enemies/"
const BRACKET_THICKNESS := 2.5
const BRACKET_SPAN := 0.5
const BRACKET_PAD := 8.0
const DEATH_FADE_DURATION := 0.45
const INTENTION_SCENE := preload("res://scenes/UI/enemy_intention_ui.tscn")

var enemy_index: int = -1
var _enemy: EnemyInstance
var _is_selected: bool = false
var _is_dying: bool = false

@onready var _combat_text_host: Control = %CombatTextHost
@onready var _intention_host: Control = %IntentionHost
@onready var _placeholder: ColorRect = %Placeholder
@onready var _sprite: TextureRect = %Sprite
@onready var _hp_bar: ProgressBar = %HPBar
@onready var _hp_label: Label = %HPLabel
@onready var _selection_overlay: Control = %SelectionOverlay

var _intention_ui: EnemyIntentionUI


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = false
	_apply_panel_style()
	_apply_hp_bar_styles()
	_ensure_intention_ui()
	if _hp_label:
		_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hp_label.add_theme_color_override("font_color", TEXT_COLOR)
		_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _sprite:
		_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if _placeholder:
		_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _selection_overlay:
		_selection_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_selection_overlay.draw.connect(_draw_selection_brackets)
	gui_input.connect(_on_gui_input)


func setup(enemy: EnemyInstance, index: int, selected: bool) -> void:
	_enemy = enemy
	enemy_index = index
	_is_dying = false
	if not is_node_ready():
		await ready
	_ensure_intention_ui()
	_refresh_presentation(selected)
	if enemy != null:
		set_hp(enemy.current_hp, enemy.max_hp)
		set_intention(enemy.current_intention)
	else:
		set_hp(0, 1)
		set_intention(null)


func get_enemy() -> EnemyInstance:
	return _enemy


func get_combat_text_host() -> Control:
	return _combat_text_host if _combat_text_host != null else self


func set_selected(selected: bool) -> void:
	_is_selected = selected and not _is_dying
	if _selection_overlay:
		_selection_overlay.queue_redraw()


func set_hp(current: int, maximum: int) -> void:
	if _is_dying:
		return
	var max_hp := maxi(maximum, 1)
	var cur := clampi(current, 0, max_hp)
	if _hp_bar:
		_hp_bar.max_value = max_hp
		_hp_bar.value = cur
		_hp_bar.show_percentage = false
	if _hp_label:
		_hp_label.text = "%d/%d" % [cur, max_hp]
	if cur <= 0:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		modulate = Color.WHITE
		mouse_filter = Control.MOUSE_FILTER_STOP


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
	death_fade_finished.emit(self)
	queue_free()


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


func _refresh_presentation(selected: bool) -> void:
	set_selected(selected)
	_apply_enemy_sprite()


func _draw_selection_brackets() -> void:
	if not _is_selected or _selection_overlay == null:
		return
	var w := _selection_overlay.size.x
	var h := _selection_overlay.size.y
	if w <= 0.0 or h <= 0.0:
		return
	var left := -BRACKET_PAD
	var top := -BRACKET_PAD
	var right := w + BRACKET_PAD
	var bottom := h + BRACKET_PAD
	var arm := w * BRACKET_SPAN
	var t := BRACKET_THICKNESS
	_selection_overlay.draw_line(Vector2(left, top), Vector2(left + arm, top), SELECT_COLOR, t, true)
	_selection_overlay.draw_line(Vector2(left, top), Vector2(left, top + arm), SELECT_COLOR, t, true)
	_selection_overlay.draw_line(Vector2(right - arm, bottom), Vector2(right, bottom), SELECT_COLOR, t, true)
	_selection_overlay.draw_line(Vector2(right, bottom - arm), Vector2(right, bottom), SELECT_COLOR, t, true)


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
		candidates.append("%s%s.png" % [SPRITE_DIR, enemy_id])
	for path in candidates:
		if ResourceLoader.exists(path):
			var loaded: Resource = load(path)
			if loaded is Texture2D:
				return loaded as Texture2D
	return null


func _apply_panel_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_border_width_all(0)
	style.set_content_margin_all(4)
	add_theme_stylebox_override("panel", style)


func _apply_hp_bar_styles() -> void:
	if _hp_bar == null:
		return
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(BAR_MIN_WIDTH, BAR_HEIGHT)
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var fill := StyleBoxFlat.new()
	fill.bg_color = FILL_COLOR
	fill.set_corner_radius_all(2)
	fill.set_content_margin_all(0)

	var bg := StyleBoxFlat.new()
	bg.bg_color = BG_COLOR
	bg.set_corner_radius_all(2)
	bg.set_content_margin_all(0)

	_hp_bar.add_theme_stylebox_override("fill", fill)
	_hp_bar.add_theme_stylebox_override("background", bg)


func _on_gui_input(event: InputEvent) -> void:
	if _is_dying:
		return
	card_gui_input.emit(event, enemy_index)
