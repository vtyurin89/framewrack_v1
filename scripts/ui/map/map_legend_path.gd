class_name MapLegendPath
extends Control
## Small dashed line sample for the map sidebar legend.

@export var line_color: Color = GamePalette.COLOR_MAP_PATH_ACTIVE
@export var line_width: float = 2.0
@export var dash_length: float = 6.0
@export var gap_length: float = 5.0


func _ready() -> void:
	custom_minimum_size = Vector2(36, 20)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var y := size.y * 0.5
	var x := 0.0
	var draw_on := true
	while x < size.x:
		var seg_len := dash_length if draw_on else gap_length
		var x1 := minf(x + seg_len, size.x)
		if draw_on:
			draw_line(Vector2(x, y), Vector2(x1, y), line_color, line_width, false)
		x = x1
		draw_on = not draw_on
