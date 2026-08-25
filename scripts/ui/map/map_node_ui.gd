class_name MapNodeUI
extends Button

signal node_pressed(node_data: MapNodeData)

var node_data: MapNodeData
var _pulse_tween: Tween


func bind_data(data: MapNodeData) -> void:
	node_data = data
	if node_data == null:
		return
	size = Vector2(56, 56)
	custom_minimum_size = size
	position = node_data.position - (size * 0.5)
	text = _icon_for_type(node_data.node_type)
	tooltip_text = _display_name()
	disabled = node_data.state == MapNodeData.NodeState.LOCKED
	modulate = _state_color(node_data.state)
	scale = Vector2.ONE
	pivot_offset = size * 0.5
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_refresh_pulse()


func _ready() -> void:
	custom_minimum_size = Vector2(56, 56)
	size = custom_minimum_size
	pivot_offset = size * 0.5
	pressed.connect(_on_pressed)


func _refresh_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
		_pulse_tween = null
	scale = Vector2.ONE
	if node_data == null or node_data.state != MapNodeData.NodeState.AVAILABLE:
		return
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_pressed() -> void:
	if node_data == null:
		return
	node_pressed.emit(node_data)


func _state_color(state: MapNodeData.NodeState) -> Color:
	match state:
		MapNodeData.NodeState.LOCKED:
			return GamePalette.COLOR_MISS
		MapNodeData.NodeState.VISITED:
			return GamePalette.COLOR_MAP_NODE_VISITED
		_:
			return GamePalette.COLOR_MAP_NODE_AVAILABLE


func _icon_for_type(node_type: MapNodeData.MapNodeType) -> String:
	match node_type:
		MapNodeData.MapNodeType.INTRO:
			return "✦"
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
		MapNodeData.MapNodeType.STAIRS:
			return "⬆"
		MapNodeData.MapNodeType.REWARD:
			return "📦"
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
