class_name MapNodeUI
extends Button

signal node_pressed(node_data: MapNodeData)

const ICON_COMBAT := preload("res://assets/icons/ui/map/map_combat.png")
const ICON_ELITE := preload("res://assets/icons/ui/map/map_elite.png")
const ICON_BOSS := preload("res://assets/icons/ui/map/map_boss.png")
const ICON_REPAIR := preload("res://assets/icons/ui/map/map_repair.png")
const ICON_SIZE := 28

var node_data: MapNodeData
var _pulse_tween: Tween


func bind_data(data: MapNodeData) -> void:
	node_data = data
	if node_data == null:
		return
	size = Vector2(56, 56)
	custom_minimum_size = size
	position = node_data.position - (size * 0.5)
	_apply_crt_chrome()
	_apply_type_icon(node_data.node_type)
	tooltip_text = _display_name()
	disabled = node_data.state == MapNodeData.NodeState.LOCKED
	_apply_state_visuals()
	scale = Vector2.ONE
	pivot_offset = size * 0.5
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_refresh_pulse()


func _ready() -> void:
	custom_minimum_size = Vector2(56, 56)
	size = custom_minimum_size
	pivot_offset = size * 0.5
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_crt_chrome()
	pressed.connect(_on_pressed)


func _apply_crt_chrome() -> void:
	## Flat square CRT bezel — no default Godot button chrome.
	var locked := make_style(GamePalette.PANEL_BG, GamePalette.MUTED_GREEN)
	var idle := make_style(GamePalette.PANEL_BG_ALT, GamePalette.MUTED_GREEN)
	var active := make_style(GamePalette.PANEL_BG_ALT, GamePalette.PHOSPHOR_BRIGHT, true)
	var visited := make_style(GamePalette.PANEL_BG, GamePalette.CRT_TEXT_MAIN)
	var hover := make_style(GamePalette.PANEL_BG_ALT, GamePalette.PHOSPHOR_ACTIVE, true)
	add_theme_stylebox_override("normal", idle)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", active)
	add_theme_stylebox_override("disabled", locked)
	add_theme_stylebox_override("focus", active)
	## Stash state styles on meta for _apply_state_visuals.
	set_meta("style_locked", locked)
	set_meta("style_visited", visited)
	set_meta("style_available", active)
	set_meta("style_idle", idle)
	add_theme_font_size_override("font_size", 22)
	add_theme_color_override("font_color", GamePalette.CRT_TEXT_MAIN)
	add_theme_color_override("font_hover_color", GamePalette.PHOSPHOR_ACTIVE)
	add_theme_color_override("font_pressed_color", GamePalette.PHOSPHOR_BRIGHT)
	add_theme_color_override("font_disabled_color", GamePalette.MUTED_GREEN)
	add_theme_color_override("icon_normal_color", GamePalette.CRT_TEXT_MAIN)
	add_theme_color_override("icon_hover_color", GamePalette.PHOSPHOR_ACTIVE)
	add_theme_color_override("icon_pressed_color", GamePalette.PHOSPHOR_BRIGHT)
	add_theme_color_override("icon_disabled_color", GamePalette.MUTED_GREEN)
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER


func make_style(bg: Color, border: Color, with_glow: bool = false) -> StyleBoxFlat:
	## Symmetric padding so glyphs/icons sit centered in the 56px square.
	return GamePalette.make_panel_stylebox(bg, border, 1, 0, 6.0, with_glow)


func _apply_state_visuals() -> void:
	if node_data == null:
		return
	var style: StyleBoxFlat = get_meta("style_idle") as StyleBoxFlat
	var font_col := GamePalette.CRT_TEXT_MAIN
	var glow := false
	match node_data.state:
		MapNodeData.NodeState.LOCKED:
			style = get_meta("style_locked") as StyleBoxFlat
			font_col = GamePalette.MUTED_GREEN
		MapNodeData.NodeState.VISITED:
			style = get_meta("style_visited") as StyleBoxFlat
			font_col = GamePalette.CRT_TEXT_MAIN
		MapNodeData.NodeState.AVAILABLE:
			style = get_meta("style_available") as StyleBoxFlat
			font_col = GamePalette.PHOSPHOR_BRIGHT
			glow = true
		_:
			pass
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("disabled", get_meta("style_locked") as StyleBoxFlat)
	add_theme_color_override("font_color", font_col)
	add_theme_color_override("font_disabled_color", GamePalette.MUTED_GREEN)
	add_theme_color_override("icon_normal_color", font_col)
	add_theme_color_override("icon_disabled_color", GamePalette.MUTED_GREEN)
	## Elite skull stays a brighter phosphor wash even when locked/idle.
	if node_data.node_type == MapNodeData.MapNodeType.ELITE:
		var elite_col := (
			GamePalette.PHOSPHOR_BRIGHT
			if node_data.state != MapNodeData.NodeState.LOCKED
			else GamePalette.MUTED_GREEN
		)
		add_theme_color_override("icon_normal_color", elite_col)
		add_theme_color_override("icon_hover_color", GamePalette.PHOSPHOR_BRIGHT)
	GamePalette.apply_phosphor_glow(self, glow)
	modulate = Color.WHITE


func _refresh_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
		_pulse_tween = null
	scale = Vector2.ONE
	if node_data == null or node_data.state != MapNodeData.NodeState.AVAILABLE:
		return
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(self, "scale", Vector2(1.06, 1.06), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_pressed() -> void:
	if node_data == null:
		return
	node_pressed.emit(node_data)


func _apply_type_icon(node_type: MapNodeData.MapNodeType) -> void:
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	var tex := _texture_for_type(node_type)
	if tex != null:
		text = ""
		icon = tex
		expand_icon = true
		add_theme_constant_override("icon_max_width", ICON_SIZE)
	else:
		icon = null
		expand_icon = false
		text = _glyph_for_type(node_type)


func _texture_for_type(node_type: MapNodeData.MapNodeType) -> Texture2D:
	match node_type:
		MapNodeData.MapNodeType.COMBAT:
			return ICON_COMBAT
		MapNodeData.MapNodeType.ELITE:
			return ICON_ELITE
		MapNodeData.MapNodeType.BOSS:
			return ICON_BOSS
		MapNodeData.MapNodeType.REPAIR:
			return ICON_REPAIR
		_:
			return null


func _glyph_for_type(node_type: MapNodeData.MapNodeType) -> String:
	match node_type:
		MapNodeData.MapNodeType.INTRO:
			return "+"
		MapNodeData.MapNodeType.MAIN_STORY:
			return "#"
		MapNodeData.MapNodeType.EVENT:
			return "?"
		MapNodeData.MapNodeType.SHOP:
			return "$"
		MapNodeData.MapNodeType.STAIRS:
			return "^"
		MapNodeData.MapNodeType.REWARD:
			return "*"
		_:
			return "·"


func _display_name() -> String:
	if node_data != null and node_data.encounter_data != null:
		var title := node_data.encounter_data.get_display_title().strip_edges()
		## Prefer a real encounter title over a technical id like "act1_l1_n1".
		if not title.is_empty() and title != node_data.id and not title.begins_with("act"):
			return title
	return _type_label(node_data.node_type if node_data != null else MapNodeData.MapNodeType.COMBAT)


func _type_label(node_type: MapNodeData.MapNodeType) -> String:
	match node_type:
		MapNodeData.MapNodeType.INTRO:
			return tr("KEY_TYPE_INTRO")
		MapNodeData.MapNodeType.MAIN_STORY:
			return tr("KEY_TYPE_MAIN_STORY")
		MapNodeData.MapNodeType.COMBAT:
			return tr("KEY_TYPE_COMBAT")
		MapNodeData.MapNodeType.EVENT:
			return tr("KEY_TYPE_EVENT")
		MapNodeData.MapNodeType.REPAIR:
			return tr("KEY_TYPE_REPAIR")
		MapNodeData.MapNodeType.SHOP:
			return tr("KEY_TYPE_SHOP")
		MapNodeData.MapNodeType.ELITE:
			return tr("KEY_TYPE_ELITE")
		MapNodeData.MapNodeType.BOSS:
			return tr("KEY_TYPE_BOSS")
		MapNodeData.MapNodeType.STAIRS:
			return tr("KEY_TYPE_STAIRS")
		MapNodeData.MapNodeType.REWARD:
			return tr("KEY_TYPE_REWARD")
		_:
			return "?"
