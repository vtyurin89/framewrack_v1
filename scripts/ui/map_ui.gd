extends Control
## Node map UI — linear path of combat / repair / event / boss.

signal node_chosen(node_id: String)

var map_manager: Node

@onready var _path: HBoxContainer = %PathRow
@onready var _title: Label = %MapTitle


func setup(p_map: Node) -> void:
	map_manager = p_map
	refresh()


func refresh() -> void:
	for child in _path.get_children():
		child.queue_free()
	if map_manager == null:
		return
	_title.text = "SECTOR MAP — choose the next node"
	var available_ids: Dictionary = {}
	for n: Dictionary in map_manager.get_available_nodes():
		available_ids[n["id"]] = true

	for n: Dictionary in map_manager.get_all_nodes():
		var id: String = n["id"]
		var btn := Button.new()
		var type_name := _type_label(n["type"])
		btn.text = "%s\n%s" % [n["label"], type_name]
		btn.custom_minimum_size = Vector2(140, 72)
		btn.disabled = not available_ids.has(id)
		if map_manager.completed.has(id):
			btn.disabled = true
			btn.modulate = Color(0.45, 0.45, 0.45)
			btn.text += "\n[DONE]"
		btn.pressed.connect(_on_node.bind(id))
		_path.add_child(btn)

		var arrow := Label.new()
		arrow.text = " → "
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_path.add_child(arrow)

	# Remove trailing arrow
	if _path.get_child_count() > 0:
		var last := _path.get_child(_path.get_child_count() - 1)
		last.queue_free()


func _on_node(node_id: String) -> void:
	node_chosen.emit(node_id)


func _type_label(t: int) -> String:
	match t:
		0:
			return "COMBAT"
		1:
			return "REPAIR"
		2:
			return "EVENT"
		3:
			return "BOSS"
		_:
			return "?"
