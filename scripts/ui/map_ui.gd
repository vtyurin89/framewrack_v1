extends Control
## Graph map UI wrapper around ScrollMapContainer.

signal node_chosen(node_id: String)

var map_manager: Node
var _cached_map_data: MapData

@onready var _sidebar: MapSidebar = %Sidebar
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
	refresh()


func _on_language_changed(_locale: String) -> void:
	refresh()


func refresh() -> void:
	if map_manager == null:
		return
	if map_manager.has_method("get_map_data"):
		_cached_map_data = map_manager.get_map_data() as MapData
	_scroll_map.set_map_data(_cached_map_data)
	_update_sidebar()


func set_map_data(data: MapData) -> void:
	_cached_map_data = data
	_scroll_map.set_map_data(_cached_map_data)


func _update_sidebar() -> void:
	if _sidebar == null:
		return
	var act: ActData = map_manager.get("current_act") as ActData if map_manager != null else null
	if act != null:
		_sidebar.set_act_location(act.get_localized_location())
	_sidebar.refresh_translations()


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
