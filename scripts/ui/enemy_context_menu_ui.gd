class_name EnemyContextMenuUI
extends PanelContainer
## Floating RMB context menu for a combat enemy (Inspect entry point).

signal inspect_pressed(enemy: EnemyInstance)
signal closed

const MENU_MIN_WIDTH := 160.0

var _enemy: EnemyInstance
var _inspect_btn: Button
var _open: bool = false


func _ready() -> void:
	top_level = true
	z_index = 130
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_style()
	_build()
	set_process_unhandled_input(false)
	if not LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.connect(_on_language_changed)


func is_open() -> bool:
	return _open


func open_for_enemy(enemy: EnemyInstance, global_pos: Vector2) -> void:
	if enemy == null or not enemy.is_alive():
		close()
		return
	var tree := UiOverlayLayer.get_scene_tree(self)
	UiOverlayLayer.mount(self, tree.current_scene if tree != null else null)
	_enemy = enemy
	_refresh_labels()
	visible = true
	_open = true
	set_process_unhandled_input(true)
	global_position = global_pos
	tree = UiOverlayLayer.get_scene_tree(self)
	if tree != null:
		await tree.process_frame
	if not is_instance_valid(self) or not _open:
		return
	_clamp_to_viewport()


func close() -> void:
	if not _open and not visible:
		return
	_open = false
	_enemy = null
	visible = false
	set_process_unhandled_input(false)
	closed.emit()


func _on_language_changed(_locale: String) -> void:
	_refresh_labels()


func _refresh_labels() -> void:
	if _inspect_btn:
		_inspect_btn.text = tr("KEY_INSPECT")


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		## Close when clicking outside the menu.
		if not get_global_rect().has_point(event.global_position):
			close()
			get_viewport().set_input_as_handled()


func _build() -> void:
	for child in get_children():
		child.queue_free()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	_inspect_btn = Button.new()
	_inspect_btn.custom_minimum_size = Vector2(MENU_MIN_WIDTH, 28)
	_inspect_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_inspect_btn.pressed.connect(_on_inspect_pressed)
	_inspect_btn.text = tr("KEY_INSPECT")
	vbox.add_child(_inspect_btn)


func _on_inspect_pressed() -> void:
	var selected: EnemyInstance = _enemy
	close()
	if selected != null:
		inspect_pressed.emit(selected)


func _apply_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.11, 0.98)
	style.set_border_width_all(1)
	style.border_color = Color(0.4, 0.4, 0.45)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(2)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 6
	add_theme_stylebox_override("panel", style)


func _clamp_to_viewport() -> void:
	var vp := get_viewport().get_visible_rect().size
	var tip_size := size
	if tip_size.x < 1.0 or tip_size.y < 1.0:
		tip_size = get_combined_minimum_size()
	var pos := global_position
	pos.x = clampf(pos.x, 0.0, maxf(0.0, vp.x - tip_size.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, vp.y - tip_size.y))
	global_position = pos
