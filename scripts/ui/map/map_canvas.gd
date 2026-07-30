class_name MapCanvas
extends Control

signal node_pressed(node_data: MapNodeData)

@export var node_scene: PackedScene

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
			var is_active := (
				node.state != MapNodeData.NodeState.LOCKED
				and next.state != MapNodeData.NodeState.LOCKED
			)
			var color := GamePalette.COLOR_MAP_PATH_LOCKED
			var width := 2.0
			if is_active:
				color = (
					GamePalette.COLOR_MAIN_STORY
					if node.node_type == MapNodeData.MapNodeType.MAIN_STORY
					else GamePalette.COLOR_MAP_PATH_ACTIVE
				)
				width = 3.0
			draw_line(node.position, next.position, color, width, true)
	for node: MapNodeData in map_data.get_all_nodes():
		var dot_color := Color(0.36, 0.36, 0.4, 1.0)
		if node.state == MapNodeData.NodeState.AVAILABLE:
			dot_color = GamePalette.COLOR_MAIN_STORY
		elif node.state == MapNodeData.NodeState.VISITED:
			dot_color = GamePalette.COLOR_MAP_PATH_ACTIVE
		draw_circle(node.position, 8.0, dot_color)
