class_name MapSidebar
extends PanelContainer
## Left map panel: act location header + node/path legend.

const ICON_COMBAT := preload("res://assets/icons/ui/map/map_combat.png")
const ICON_ELITE := preload("res://assets/icons/ui/map/map_elite.png")
const ICON_BOSS := preload("res://assets/icons/ui/map/map_boss.png")
const ICON_REPAIR := preload("res://assets/icons/ui/map/map_repair.png")
const LEGEND_ICON_BOX := 28

@onready var _location_label: Label = $SidebarVBox/LocationLabel
@onready var _legend_title: Label = $SidebarVBox/LegendPanel/LegendTitle
@onready var _legend_list: VBoxContainer = $SidebarVBox/LegendPanel/LegendList


func _ready() -> void:
	_apply_theme()
	_build_legend()
	if not LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.connect(_on_language_changed)


func set_act_location(text: String) -> void:
	if _location_label == null:
		return
	_location_label.text = text.strip_edges().to_upper()


func refresh_translations() -> void:
	_build_legend()


func _on_language_changed(_locale: String) -> void:
	_build_legend()


func _apply_theme() -> void:
	add_theme_stylebox_override(
		"panel",
		GamePalette.make_panel_stylebox(GamePalette.PANEL_BG, GamePalette.MUTED_GREEN, 1, 0, 10.0, false)
	)
	if _location_label != null:
		_location_label.add_theme_font_size_override("font_size", 20)
		_location_label.add_theme_color_override("font_color", GamePalette.PHOSPHOR_BRIGHT)
		_location_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		GamePalette.apply_phosphor_glow(_location_label, true)
	if _legend_title != null:
		_legend_title.text = tr("KEY_MAP_LEGEND")
		_legend_title.add_theme_font_size_override("font_size", 14)
		_legend_title.add_theme_color_override("font_color", GamePalette.CRT_TEXT_MAIN)


func _build_legend() -> void:
	if _legend_list == null:
		return
	for child in _legend_list.get_children():
		child.queue_free()
	if _legend_title != null:
		_legend_title.text = tr("KEY_MAP_LEGEND")

	var node_entries: Array[Dictionary] = [
		{"kind": "texture", "tex": ICON_COMBAT, "label": tr("KEY_TYPE_COMBAT")},
		{"kind": "texture", "tex": ICON_ELITE, "label": tr("KEY_TYPE_ELITE")},
		{"kind": "glyph", "glyph": "$", "label": tr("KEY_TYPE_SHOP")},
		{"kind": "glyph", "glyph": "?", "label": tr("KEY_TYPE_EVENT")},
		{"kind": "texture", "tex": ICON_BOSS, "label": tr("KEY_TYPE_BOSS")},
		{"kind": "texture", "tex": ICON_REPAIR, "label": tr("KEY_TYPE_REPAIR")},
	]
	for entry in node_entries:
		_legend_list.add_child(_make_node_row(entry))


func _make_node_row(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_make_icon_box(entry))
	var label := Label.new()
	label.text = str(entry.get("label", ""))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", GamePalette.CRT_TEXT_MAIN)
	row.add_child(label)
	return row


func _make_icon_box(entry: Dictionary) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(LEGEND_ICON_BOX + 8, LEGEND_ICON_BOX + 8)
	box.add_theme_stylebox_override(
		"panel",
		GamePalette.make_panel_stylebox(GamePalette.PANEL_BG_ALT, GamePalette.MUTED_GREEN, 1, 0, 4.0, false)
	)
	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(LEGEND_ICON_BOX, LEGEND_ICON_BOX)
	box.add_child(center)
	if entry.get("kind", "") == "texture":
		var icon := TextureRect.new()
		icon.texture = entry.get("tex") as Texture2D
		icon.custom_minimum_size = Vector2(LEGEND_ICON_BOX, LEGEND_ICON_BOX)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = GamePalette.CRT_TEXT_MAIN
		center.add_child(icon)
	else:
		var glyph := Label.new()
		glyph.text = str(entry.get("glyph", "?"))
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", 18)
		glyph.add_theme_color_override("font_color", GamePalette.CRT_TEXT_MAIN)
		center.add_child(glyph)
	return box
