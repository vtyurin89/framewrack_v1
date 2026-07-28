class_name EnemyCardUI
extends PanelContainer
## Compact combat enemy card: portrait, selection marker, and styled HP bar.

signal card_gui_input(event: InputEvent, enemy_index: int)

const FILL_COLOR := Color("#8b263e")
const BG_COLOR := Color("#121212")
const TEXT_COLOR := Color("#ffffff")
const BAR_HEIGHT := 18.0
const BAR_MIN_WIDTH := 80.0

var enemy_index: int = -1
var _enemy: EnemyInstance

@onready var _select_marker: Label = %SelectMarker
@onready var _combat_text_host: Control = %CombatTextHost
@onready var _name_label: Label = %NameLabel
@onready var _sprite: ColorRect = %Sprite
@onready var _hp_bar: ProgressBar = %HPBar
@onready var _hp_label: Label = %HPLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = false
	_apply_hp_bar_styles()
	if _hp_label:
		_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hp_label.add_theme_color_override("font_color", TEXT_COLOR)
		_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
	_style_panel(selected)
	if _select_marker:
		_select_marker.text = "▼" if selected else ""


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
	_style_panel(selected)
	if _select_marker:
		_select_marker.text = "▼" if selected else ""
	if _name_label and _enemy != null:
		_name_label.text = _enemy.get_localized_name()
	if _sprite:
		if _enemy != null and _enemy.data != null:
			_sprite.color = _enemy.data.placeholder_color
		else:
			_sprite.color = Color(0.82, 0.82, 0.85)


func _style_panel(selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12)
	style.set_border_width_all(3 if selected else 2)
	style.border_color = Color(0.95, 0.8, 0.25) if selected else Color(0.45, 0.45, 0.5)
	style.set_content_margin_all(10)
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
