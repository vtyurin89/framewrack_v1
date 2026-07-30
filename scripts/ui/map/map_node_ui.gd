class_name MapNodeUI
extends Button

signal node_pressed(node_data: MapNodeData)

var node_data: MapNodeData
var _pulse_t: float = 0.0


func bind_data(data: MapNodeData) -> void:
	node_data = data
	if node_data == null:
		return
	size = Vector2(56, 56)
	position = node_data.position - (custom_minimum_size * 0.5)
	text = _icon_for_type(node_data.node_type)
	tooltip_text = _display_name()
	disabled = node_data.state == MapNodeData.NodeState.LOCKED
	modulate = _state_color(node_data.state)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _ready() -> void:
	custom_minimum_size = Vector2(56, 56)
	size = custom_minimum_size
	pressed.connect(_on_pressed)


func _process(delta: float) -> void:
	if node_data == null:
		return
	if node_data.state == MapNodeData.NodeState.AVAILABLE:
		_pulse_t += delta * 3.5
		var pulse := 0.88 + 0.12 * sin(_pulse_t)
		self_modulate.a = pulse
	else:
		self_modulate.a = 1.0


func _on_pressed() -> void:
	if node_data == null:
		return
	node_pressed.emit(node_data)


func _state_color(state: MapNodeData.NodeState) -> Color:
	match state:
		MapNodeData.NodeState.LOCKED:
			return Color(0.4, 0.4, 0.42, 1.0)
		MapNodeData.NodeState.VISITED:
			## Dimmed / inactive — already cleared, no longer selectable.
			return Color(0.55, 0.55, 0.58, 0.85)
		_:
			return GamePalette.COLOR_MAIN_STORY


func _icon_for_type(node_type: MapNodeData.MapNodeType) -> String:
	match node_type:
		MapNodeData.MapNodeType.MAIN_STORY:
			return "📖"
		MapNodeData.MapNodeType.COMBAT:
			return "⚔"
		MapNodeData.MapNodeType.EVENT:
			return "?"
		MapNodeData.MapNodeType.REPAIR:
			return "🔧"
		MapNodeData.MapNodeType.SHOP:
			return "$"
		MapNodeData.MapNodeType.ELITE:
			return "☠"
		MapNodeData.MapNodeType.BOSS:
			return "👑"
		_:
			return "•"


func _display_name() -> String:
	if node_data != null and node_data.encounter_data != null:
		var title := node_data.encounter_data.get_display_title().strip_edges()
		## Prefer a real encounter title over a technical id like "act1_l1_n1".
		if not title.is_empty() and title != node_data.id and not title.begins_with("act"):
			return title
	return _type_label(node_data.node_type if node_data != null else MapNodeData.MapNodeType.COMBAT)


func _type_label(node_type: MapNodeData.MapNodeType) -> String:
	match node_type:
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
		_:
			return "?"
