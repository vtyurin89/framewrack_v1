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
	tooltip_text = "%s (%s)" % [node_data.id, _type_label(node_data.node_type)]
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
			return Color(0.45, 0.45, 0.45, 1.0)
		MapNodeData.NodeState.VISITED:
			return Color(0.62, 0.62, 0.62, 1.0)
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


func _type_label(node_type: MapNodeData.MapNodeType) -> String:
	match node_type:
		MapNodeData.MapNodeType.MAIN_STORY:
			return "Main Story"
		MapNodeData.MapNodeType.COMBAT:
			return "Combat"
		MapNodeData.MapNodeType.EVENT:
			return "Event"
		MapNodeData.MapNodeType.REPAIR:
			return "Repair"
		MapNodeData.MapNodeType.SHOP:
			return "Shop"
		MapNodeData.MapNodeType.ELITE:
			return "Elite"
		MapNodeData.MapNodeType.BOSS:
			return "Boss"
		_:
			return "Unknown"
