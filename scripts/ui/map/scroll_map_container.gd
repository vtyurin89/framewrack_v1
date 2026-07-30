class_name ScrollMapContainer
extends Control

signal node_pressed(node_data: MapNodeData)
signal placeholder_continue_pressed

@export var scroll_damping: float = 0.2
@export var canvas_min_y: float = -1900.0
@export var canvas_max_y: float = 120.0

@onready var _map_canvas: MapCanvas = $MapCanvas
@onready var _placeholder_dialog: AcceptDialog = $PlaceholderDialog

var _dragging: bool = false
var _last_mouse_y: float = 0.0
var _target_y: float = 0.0


func _ready() -> void:
	clip_contents = true
	gui_input.connect(_on_gui_input)
	_map_canvas.node_pressed.connect(func(node: MapNodeData) -> void: node_pressed.emit(node))
	_placeholder_dialog.confirmed.connect(_on_placeholder_continue)
	resized.connect(_center_canvas_x)
	call_deferred("_center_canvas_x")


func set_map_data(data: MapData) -> void:
	_map_canvas.set_map_data(data)
	_center_canvas_x()
	_target_y = _map_canvas.position.y


func focus_layer(layer: int) -> void:
	## Bottom-up layout: higher layers sit higher on the canvas (smaller Y).
	var focus_y := MapGenerator.CANVAS_HEIGHT - MapGenerator.BOTTOM_PADDING - float(layer) * MapGenerator.Y_SPACING
	var target := size.y * 0.55 - focus_y
	_target_y = clampf(target, canvas_min_y, canvas_max_y)


func show_placeholder(title: String, message: String) -> void:
	_placeholder_dialog.title = title
	_placeholder_dialog.dialog_text = message
	_placeholder_dialog.ok_button_text = "Continue"
	_placeholder_dialog.popup_centered()


func _process(_delta: float) -> void:
	var current := _map_canvas.position.y
	var next := lerpf(current, _target_y, scroll_damping)
	_map_canvas.position.y = clampf(next, canvas_min_y, canvas_max_y)


func _center_canvas_x() -> void:
	if _map_canvas == null:
		return
	_map_canvas.position.x = (size.x - _map_canvas.size.x) * 0.5


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_dragging = mb.pressed
			_last_mouse_y = mb.position.y
	if event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var delta_y := mm.position.y - _last_mouse_y
		_last_mouse_y = mm.position.y
		_target_y = clampf(_target_y + delta_y, canvas_min_y, canvas_max_y)


func _on_placeholder_continue() -> void:
	placeholder_continue_pressed.emit()
