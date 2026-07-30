extends Control
## Node map UI - linear path of main story / combat / repair / event / boss.

signal node_chosen(node_id: String)

var map_manager: Node

@onready var _path: HBoxContainer = %PathRow
@onready var _title: Label = %MapTitle


func setup(p_map: Node) -> void:
	map_manager = p_map
	if not LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.connect(_on_language_changed)
	refresh()


func _on_language_changed(_locale: String) -> void:
	refresh()


func refresh() -> void:
	for child in _path.get_children():
		child.queue_free()
	if map_manager == null:
		return
	_title.text = tr("KEY_SECTOR_MAP")
	var available_ids: Dictionary = {}
	for n: Dictionary in map_manager.get_available_nodes():
		available_ids[n["id"]] = true

	for n: Dictionary in map_manager.get_all_nodes():
		var id: String = n["id"]
		var btn := Button.new()
		var type_name := _type_label(n["type"])
		var label := _node_label(n)
		btn.text = "%s\n%s" % [label, type_name]
		btn.custom_minimum_size = Vector2(140, 72)
		btn.disabled = not available_ids.has(id)
		if map_manager.completed.has(id):
			btn.disabled = true
			btn.modulate = Color(0.45, 0.45, 0.45)
			btn.text += "\n%s" % tr("KEY_DONE")
		btn.pressed.connect(_on_node.bind(id))
		_path.add_child(btn)

		var arrow := Label.new()
		arrow.text = " > "
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_path.add_child(arrow)

	if _path.get_child_count() > 0:
		var last := _path.get_child(_path.get_child_count() - 1)
		last.queue_free()


func _node_label(n: Dictionary) -> String:
	var key: String = str(n.get("label_key", ""))
	if not key.is_empty():
		return tr(key)
	return str(n.get("label", "?"))


func _on_node(node_id: String) -> void:
	node_chosen.emit(node_id)


func _type_label(t: int) -> String:
	match t:
		MapManager.NodeType.COMBAT:
			return tr("KEY_TYPE_COMBAT")
		MapManager.NodeType.REPAIR:
			return tr("KEY_TYPE_REPAIR")
		MapManager.NodeType.EVENT:
			return tr("KEY_TYPE_EVENT")
		MapManager.NodeType.BOSS:
			return tr("KEY_TYPE_BOSS")
		MapManager.NodeType.MAIN_STORY:
			return tr("KEY_TYPE_MAIN_STORY")
		_:
			return "?"