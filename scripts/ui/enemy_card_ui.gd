class_name EnemyCardUI
extends PanelContainer
## Compact combat enemy card: portrait, corner-bracket selection, and styled HP bar.

signal card_gui_input(event: InputEvent, enemy_index: int)

const FILL_COLOR := Color("#8b263e")
const BG_COLOR := Color("#121212")
const TEXT_COLOR := Color("#ffffff")
const SELECT_COLOR := Color(0.95, 0.8, 0.25)
const BAR_HEIGHT := 18.0
const BAR_MIN_WIDTH := 80.0
const SPRITE_DIR := "res://assets/sprites/enemies/"
const BRACKET_THICKNESS := 2.5
## Both arms share the same length (~half card width).
const BRACKET_SPAN := 0.5
## Gap between brackets and card content (drawn outside the content rect).
const BRACKET_PAD := 8.0

var enemy_index: int = -1
var _enemy: EnemyInstance
var _is_selected: bool = false

@onready var _combat_text_host: Control = %CombatTextHost
@onready var _placeholder: ColorRect = %Placeholder
@onready var _sprite: TextureRect = %Sprite
@onready var _hp_bar: ProgressBar = %HPBar
@onready var _hp_label: Label = %HPLabel
@onready var _selection_overlay: Control = %SelectionOverlay


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = false
	_apply_panel_style()
	_apply_hp_bar_styles()
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
	if not is_node_ready():
		await ready
	_refresh_presentation(selected)
	if enemy != null:
		set_hp(enemy.current_hp, enemy.max_hp)
	else:
		set_hp(0, 1)


func get_combat_text_host() -> Control:
	return _combat_text_host if _combat_text_host != null else self


func set_selected(selected: bool) -> void:
	_is_selected = selected
	if _selection_overlay:
		_selection_overlay.queue_redraw()


func set_hp(current: int, maximum: int) -> void:
	var max_hp := maxi(maximum, 1)
	var cur := clampi(current, 0, max_hp)
	if _hp_bar:
		_hp_bar.max_value = max_hp
		_hp_bar.value = cur
		_hp_bar.show_percentage = false
	if _hp_label:
		## Numbers only — no "HP" / "ОЗ" prefix.
		_hp_label.text = "%d/%d" % [cur, max_hp]
	if cur <= 0:
		modulate = Color(0.3, 0.3, 0.3, 0.6)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		modulate = Color.WHITE
		mouse_filter = Control.MOUSE_FILTER_STOP


func _refresh_presentation(selected: bool) -> void:
	set_selected(selected)
	_apply_enemy_sprite()


func _draw_selection_brackets() -> void:
	## Drawn on SelectionOverlay (above children) so brackets sit on top of the sprite.
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
	## Equal arm length on both axes (based on content width).
	var arm := w * BRACKET_SPAN
	var t := BRACKET_THICKNESS
	## Top-left bracket
	_selection_overlay.draw_line(Vector2(left, top), Vector2(left + arm, top), SELECT_COLOR, t, true)
	_selection_overlay.draw_line(Vector2(left, top), Vector2(left, top + arm), SELECT_COLOR, t, true)
	## Bottom-right bracket
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
	## Prefer CSV sprite_path, then default assets/sprites/enemies/{id}.png.
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
	## Transparent / seamless with the combat screen — no border box.
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
	card_gui_input.emit(event, enemy_index)
