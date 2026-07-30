class_name MapCanvas
extends Control

signal node_pressed(node_data: MapNodeData)

@export var node_scene: PackedScene
@export var dash_length: float = 10.0
@export var gap_length: float = 8.0

var map_data: MapData


func set_map_data(data: MapData) -> void:
	map_data = data
	_rebuild_nodes()
	queue_redraw()


func _rebuild_nodes() -> void:
	for child in get_children():
		child.queue_free()
	if map_data == null:
		return
	var scene := node_scene
	if scene == null:
		scene = preload("res://scenes/UI/map/map_node_ui.tscn")
	for node: MapNodeData in map_data.get_all_nodes():
		var ui := scene.instantiate() as MapNodeUI
		add_child(ui)
		ui.bind_data(node)
		ui.node_pressed.connect(func(selected: MapNodeData) -> void: node_pressed.emit(selected))


func _draw() -> void:
	if map_data == null:
		return
	for node: MapNodeData in map_data.get_all_nodes():
		for next_id in node.next_nodes:
			var next := map_data.get_node(next_id)
			if next == null:
				continue
			var color := GamePalette.COLOR_MAP_PATH_LOCKED
			var width := 2.0
			## Forward edges from current visited node to AVAILABLE choices.
			var is_forward := (
				node.state == MapNodeData.NodeState.VISITED
				and next.state == MapNodeData.NodeState.AVAILABLE
			)
			## Past path (already taken) stays muted.
			var is_traveled := (
				node.state == MapNodeData.NodeState.VISITED
				and next.state == MapNodeData.NodeState.VISITED
			)
			if is_forward:
				color = GamePalette.COLOR_MAP_PATH_ACTIVE
				width = 2.5
			elif is_traveled:
				color = Color(
					GamePalette.COLOR_MAP_PATH_LOCKED.r,
					GamePalette.COLOR_MAP_PATH_LOCKED.g,
					GamePalette.COLOR_MAP_PATH_LOCKED.b,
					0.55
				)
			_draw_dashed_line(node.position, next.position, color, width)
	for node: MapNodeData in map_data.get_all_nodes():
		var dot_color := Color(0.36, 0.36, 0.4, 1.0)
		if node.state == MapNodeData.NodeState.AVAILABLE:
			dot_color = GamePalette.COLOR_MAIN_STORY
		elif node.state == MapNodeData.NodeState.VISITED:
			dot_color = Color(0.5, 0.5, 0.52, 1.0)
		draw_circle(node.position, 8.0, dot_color)


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var delta := to - from
	var length := delta.length()
	if length <= 0.001:
		return
	var direction := delta / length
	var step := maxf(dash_length + gap_length, 0.001)
	var drawn := 0.0
	while drawn < length:
		var seg_start := from + direction * drawn
		var seg_end := from + direction * minf(drawn + dash_length, length)
		draw_line(seg_start, seg_end, color, width, true)
		drawn += step
