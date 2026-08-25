extends Control
## Graph map UI wrapper around ScrollMapContainer.

signal node_chosen(node_id: String)

var map_manager: Node
var _cached_map_data: MapData
var _coords_label: Label

@onready var _scroll_map: ScrollMapContainer = %ScrollMap


func setup(p_map: Node) -> void:
	map_manager = p_map
	if not LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.connect(_on_language_changed)
	if not _scroll_map.node_pressed.is_connected(_on_node_pressed):
		_scroll_map.node_pressed.connect(_on_node_pressed)
	if map_manager != null and map_manager.has_signal("focus_layer_requested"):
		if not map_manager.focus_layer_requested.is_connected(_on_focus_layer_requested):
			map_manager.focus_layer_requested.connect(_on_focus_layer_requested)
	if map_manager != null and map_manager.has_signal("placeholder_requested"):
		if not map_manager.placeholder_requested.is_connected(_on_placeholder_requested):
			map_manager.placeholder_requested.connect(_on_placeholder_requested)
	if not _scroll_map.placeholder_continue_pressed.is_connected(_on_placeholder_continue):
		_scroll_map.placeholder_continue_pressed.connect(_on_placeholder_continue)
	_ensure_coords_panel()
	refresh()


func _process(_delta: float) -> void:
	_update_coords_panel()


func _ensure_coords_panel() -> void:
	if _coords_label != null and is_instance_valid(_coords_label):
		return
	var panel := PanelContainer.new()
	panel.name = "CoordsPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -220.0
	panel.offset_top = -36.0
	panel.offset_right = -12.0
	panel.offset_bottom = -12.0
	panel.add_theme_stylebox_override(
		"panel",
		GamePalette.make_panel_stylebox(
			GamePalette.PANEL_BG, GamePalette.MUTED_GREEN, 1, 0, 6.0, false
		)
	)
	_coords_label = Label.new()
	_coords_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coords_label.add_theme_font_size_override("font_size", 12)
	GamePalette.apply_label_system(_coords_label)
	_coords_label.text = "X: 00.00  Y: 00.00  Z: 00.00"
	panel.add_child(_coords_label)
	add_child(panel)


func _update_coords_panel() -> void:
	if _coords_label == null:
		return
	var mouse := get_local_mouse_position()
	var x := fmod(absf(mouse.x) * 0.07, 100.0)
	var y := fmod(absf(mouse.y) * 0.05, 100.0) * -1.0
	var z := fmod((absf(mouse.x) + absf(mouse.y)) * 0.02, 20.0)
	_coords_label.text = "X: %05.2f  Y: %06.2f  Z: %05.2f" % [x, y, z]


func _on_language_changed(_locale: String) -> void:
	refresh()


func refresh() -> void:
	if map_manager == null:
		return
	if map_manager.has_method("get_map_data"):
		_cached_map_data = map_manager.get_map_data() as MapData
	_scroll_map.set_map_data(_cached_map_data)


func set_map_data(data: MapData) -> void:
	_cached_map_data = data
	_scroll_map.set_map_data(_cached_map_data)


func _on_node_pressed(node_data: MapNodeData) -> void:
	if node_data == null:
		return
	node_chosen.emit(node_data.id)


func _on_focus_layer_requested(layer: int) -> void:
	_scroll_map.focus_layer(layer)


func _on_placeholder_requested(title: String, message: String) -> void:
	_scroll_map.show_placeholder(title, message)


func _on_placeholder_continue() -> void:
	if map_manager != null and map_manager.has_method("continue_placeholder_node"):
		map_manager.continue_placeholder_node()
