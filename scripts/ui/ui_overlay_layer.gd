class_name UiOverlayLayer
extends RefCounted
## Shared high CanvasLayer for modals / floating menus so they sit above
## gameplay chrome (target reticle, Body Grid grain, CRT scanlines).

const LAYER_NAME := "ModalOverlayLayer"
## Above OverlayLayer(5) and CrtOverlay(12); below damage popups(100).
const LAYER_INDEX := 40


static func get_scene_tree(from_node: Node = null) -> SceneTree:
	if from_node != null:
		var tree := from_node.get_tree()
		if tree != null:
			return tree
	return Engine.get_main_loop() as SceneTree


static func get_or_create(from_node: Node = null) -> CanvasLayer:
	var tree := get_scene_tree(from_node)
	if tree == null:
		return null
	## Prefer the running scene (Main) over Window root — Controls size reliably there.
	var host: Node = tree.current_scene
	if host == null:
		host = from_node if from_node != null and from_node.is_inside_tree() else tree.root
	if host == null:
		return null
	var existing := host.get_node_or_null(LAYER_NAME) as CanvasLayer
	if existing != null:
		existing.layer = LAYER_INDEX
		return existing
	## Also recover a layer previously parented under the Window root.
	var root_existing := tree.root.get_node_or_null(LAYER_NAME) as CanvasLayer
	if root_existing != null:
		if root_existing.get_parent() != host:
			root_existing.reparent(host)
		root_existing.layer = LAYER_INDEX
		return root_existing
	var layer := CanvasLayer.new()
	layer.name = LAYER_NAME
	layer.layer = LAYER_INDEX
	host.add_child(layer)
	return layer


static func mount(control: Control, from_node: Node = null) -> void:
	if control == null:
		return
	var anchor: Node = from_node if from_node != null else control
	var layer := get_or_create(anchor)
	if layer == null:
		## Last resort: keep the control in the calling node's tree so get_tree() works.
		if from_node != null and from_node.is_inside_tree() and control.get_parent() != from_node:
			if control.get_parent() != null:
				control.reparent(from_node)
			else:
				from_node.add_child(control)
		return
	if control.get_parent() == layer:
		layer.move_child(control, layer.get_child_count() - 1)
		return
	if control.get_parent() != null:
		control.reparent(layer)
	else:
		layer.add_child(control)
	layer.move_child(control, layer.get_child_count() - 1)


static func fit_fullscreen(control: Control) -> void:
	## CanvasLayer is not a Control parent — disable anchors and pin to viewport pixels.
	if control == null:
		return
	var tree := get_scene_tree(control)
	var vp_size := Vector2.ZERO
	if control.get_viewport() != null:
		vp_size = control.get_viewport().get_visible_rect().size
	elif tree != null:
		vp_size = tree.root.get_visible_rect().size
	if vp_size.x < 1.0 or vp_size.y < 1.0:
		return
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
	control.position = Vector2.ZERO
	control.size = vp_size
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	control.process_mode = Node.PROCESS_MODE_ALWAYS
	if not (control.get_parent() is CanvasLayer):
		control.z_index = 200
		control.top_level = true
