class_name MapCanvas
extends Control

signal node_pressed(node_data: MapNodeData)

@export var node_scene: PackedScene
@export var dash_length: float = 6.0
@export var gap_length: float = 5.0
@export var curve_samples: int = 18
@export var curve_side_offset: float = 28.0

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
			var width := 1.5
			var is_forward := (
				node.state == MapNodeData.NodeState.VISITED
				and next.state == MapNodeData.NodeState.AVAILABLE
			)
			var is_traveled := (
				node.state == MapNodeData.NodeState.VISITED
				and next.state == MapNodeData.NodeState.VISITED
			)
			if is_forward:
				color = GamePalette.COLOR_MAP_PATH_ACTIVE
				width = 2.0
			elif is_traveled:
				color = GamePalette.COLOR_MAP_PATH_TRAVELED
				width = 1.5
			_draw_dashed_bezier(node.position, next.position, color, width, node.id, next.id)


func _draw_dashed_bezier(
	from: Vector2,
	to: Vector2,
	color: Color,
	width: float,
	from_id: String,
	to_id: String
) -> void:
	var control := _bezier_control_point(from, to, from_id, to_id)
	var points := _sample_quadratic_bezier(from, control, to, curve_samples)
	if points.size() < 2:
		return
	var draw_on := true
	var leftover := 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var seg := b - a
		var seg_len := seg.length()
		if seg_len <= 0.001:
			continue
		var dir := seg / seg_len
		var traveled := 0.0
		while traveled < seg_len:
			var budget := (dash_length if draw_on else gap_length) - leftover
			var step := minf(budget, seg_len - traveled)
			var p0 := a + dir * traveled
			var p1 := a + dir * (traveled + step)
			if draw_on:
				## Aliased pixel dashes — CRT terminal look.
				draw_line(p0, p1, color, width, false)
			traveled += step
			leftover = 0.0
			if is_equal_approx(traveled, seg_len):
				## Carry remainder into next polyline segment for continuous dashes.
				leftover = budget - step
				if leftover <= 0.001:
					draw_on = not draw_on
					leftover = 0.0
				break
			draw_on = not draw_on


func _bezier_control_point(from: Vector2, to: Vector2, from_id: String, to_id: String) -> Vector2:
	var mid := (from + to) * 0.5
	var delta := to - from
	if delta.length_squared() < 0.001:
		return mid
	var normal := Vector2(-delta.y, delta.x).normalized()
	## Deterministic left/right bend from ids so redraws stay stable.
	var side := 1.0 if int(from_id.hash() + to_id.hash()) % 2 == 0 else -1.0
	var amount := curve_side_offset * (0.75 + 0.35 * float((from_id.hash() % 5)) / 4.0)
	return mid + normal * side * amount


func _sample_quadratic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, samples: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := maxi(samples, 4)
	for i in count + 1:
		var t := float(i) / float(count)
		var u := 1.0 - t
		out.append(u * u * p0 + 2.0 * u * t * p1 + t * t * p2)
	return out
