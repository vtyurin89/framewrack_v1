class_name UiOverlayLayer
extends RefCounted
## Shared high CanvasLayer for modals / floating menus so they sit above
## gameplay chrome (target reticle, Body Grid grain, CRT scanlines).

const LAYER_NAME := "ModalOverlayLayer"
## Above OverlayLayer(5) and CrtOverlay(12); below damage popups(100).
const LAYER_INDEX := 40


static func get_or_create(from_node: Node) -> CanvasLayer:
	if from_node == null:
		return null
	var tree := from_node.get_tree()
	if tree == null:
		return null
	var root := tree.root
	var existing := root.get_node_or_null(LAYER_NAME) as CanvasLayer
	if existing != null:
		existing.layer = LAYER_INDEX
		return existing
	var layer := CanvasLayer.new()
	layer.name = LAYER_NAME
	layer.layer = LAYER_INDEX
	root.add_child(layer)
	return layer


static func mount(control: Control, from_node: Node = null) -> void:
	if control == null:
		return
	var anchor: Node = from_node if from_node != null else control
	var layer := get_or_create(anchor)
	if layer == null:
		return
	if control.get_parent() == layer:
		layer.move_child(control, layer.get_child_count() - 1)
		return
	if control.get_parent() != null:
		control.reparent(layer)
	else:
		layer.add_child(control)
	layer.move_child(control, layer.get_child_count() - 1)
