extends Control
## Combat HUD: enemies (click to select), AP/HP/Block, log, End Turn.
## Item activation happens via inventory clicks (Backpack Hero model).

signal end_turn_pressed
signal target_selected(index: int)
signal continue_pressed

const ENEMY_INSPECT_SCENE := preload("res://scenes/UI/enemy_inspect_ui.tscn")

var combat: Node  # CombatManager
var inventory: InventoryController
var _enemy_inspect: EnemyInspectUI
var _enemy_context_menu: EnemyContextMenuUI

@onready var _enemy_row: HBoxContainer = %EnemyRow
@onready var _hp_label: Label = %HPLabel
@onready var _ap_label: Label = %APLabel
@onready var _block_label: Label = %BlockLabel
@onready var _turn_label: Label = %TurnLabel
@onready var _log: RichTextLabel = %CombatLog
@onready var _end_turn_btn: Button = %EndTurnButton
@onready var _continue_btn: Button = %ContinueButton
@onready var _hint_label: Label = %CombatHint


func _ready() -> void:
	_end_turn_btn.pressed.connect(func() -> void: end_turn_pressed.emit())
	_continue_btn.pressed.connect(func() -> void: continue_pressed.emit())
	_continue_btn.visible = false
	EventBus.ap_changed.connect(_on_ap_changed)
	EventBus.player_hp_changed.connect(_on_hp_changed)
	EventBus.block_changed.connect(_on_block_changed)
	EventBus.combat_log_message.connect(_on_log)
	EventBus.enemy_hp_changed.connect(_on_enemy_hp)
	EventBus.enemy_selected.connect(_on_enemy_selected)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.enemy_combat_text.connect(_on_enemy_combat_text)
	LocalizationManager.language_changed.connect(_on_language_changed)
	_apply_static_locale()


func setup(p_combat: Node, p_inventory: InventoryController) -> void:
	combat = p_combat
	inventory = p_inventory
	_log.clear()
	_continue_btn.visible = false
	_end_turn_btn.disabled = false
	_apply_static_locale()
	_on_hp_changed(inventory.current_hp, inventory.max_hp)
	_rebuild_enemies()


func _on_language_changed(_locale: String) -> void:
	_apply_static_locale()
	if inventory:
		_on_hp_changed(inventory.current_hp, inventory.max_hp)
	if combat:
		_on_ap_changed(combat.current_ap, combat.max_ap)
		_on_block_changed(combat.current_block)
		_rebuild_enemies()
		if combat.state == combat.CombatState.PLAYER_TURN:
			_turn_label.text = tr("KEY_PLAYER_TURN")
		elif combat.state == combat.CombatState.ENEMY_TURN:
			_turn_label.text = tr("KEY_ENEMY_TURN")
		elif combat.state == combat.CombatState.VICTORY:
			_turn_label.text = tr("KEY_VICTORY")
			_continue_btn.text = tr("KEY_CONTINUE")
		elif combat.state == combat.CombatState.DEFEAT:
			_turn_label.text = tr("KEY_FRAME_FAILURE")
			_continue_btn.text = tr("KEY_RETURN_TO_MAP")


func _apply_static_locale() -> void:
	_end_turn_btn.text = tr("KEY_END_TURN")
	if _hint_label:
		_hint_label.text = tr("KEY_COMBAT_CLICK_HINT")


func _ensure_enemy_inspect() -> void:
	if _enemy_inspect != null and is_instance_valid(_enemy_inspect):
		return
	_enemy_inspect = ENEMY_INSPECT_SCENE.instantiate() as EnemyInspectUI
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	host.add_child(_enemy_inspect)


func _rebuild_enemies() -> void:
	for child in _enemy_row.get_children():
		child.queue_free()
	if combat == null:
		return
	for i in combat.enemies.size():
		var enemy: EnemyInstance = combat.enemies[i]
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.gui_input.connect(_on_enemy_panel_input.bind(i))
		_style_enemy_panel(panel, i, enemy.is_selected)

		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var float_host := Control.new()
		float_host.name = "CombatTextHost"
		float_host.custom_minimum_size = Vector2(0, 22)
		float_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		float_host.clip_contents = false
		var name_l := Label.new()
		name_l.text = enemy.get_localized_name()
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sprite := ColorRect.new()
		sprite.custom_minimum_size = Vector2(80, 100)
		if enemy.data != null:
			sprite.color = enemy.data.placeholder_color
		else:
			sprite.color = Color(0.82, 0.82, 0.85)
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hp_l := Label.new()
		hp_l.name = "HP"
		hp_l.text = tr("KEY_HP_FMT") % [tr("KEY_HP"), enemy.current_hp, enemy.max_hp]
		hp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var marker := Label.new()
		marker.name = "SelectMarker"
		marker.text = "▼" if enemy.is_selected else ""
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.add_theme_color_override("font_color", Color(0.95, 0.85, 0.35))
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE

		v.add_child(marker)
		v.add_child(float_host)
		v.add_child(name_l)
		v.add_child(sprite)
		v.add_child(hp_l)
		panel.clip_contents = false
		panel.add_child(v)
		_enemy_row.add_child(panel)
		if not enemy.is_alive():
			panel.modulate = Color(0.3, 0.3, 0.3, 0.6)
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _style_enemy_panel(panel: PanelContainer, _index: int, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12)
	style.set_border_width_all(3 if selected else 2)
	style.border_color = Color(0.95, 0.8, 0.25) if selected else Color(0.45, 0.45, 0.5)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)


func _on_enemy_panel_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _enemy_context_menu and _enemy_context_menu.is_open():
				_enemy_context_menu.close()
			target_selected.emit(index)
			_on_log(tr("KEY_LOG_TARGETING") % (index + 1))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_open_enemy_context_menu(index, event.global_position)


func _open_enemy_context_menu(index: int, global_pos: Vector2) -> void:
	if combat == null or index < 0 or index >= combat.enemies.size():
		return
	var enemy: EnemyInstance = combat.enemies[index]
	if enemy == null or not enemy.is_alive():
		return
	_ensure_enemy_context_menu()
	if _enemy_context_menu:
		_enemy_context_menu.open_for_enemy(enemy, global_pos)


func _ensure_enemy_context_menu() -> void:
	if _enemy_context_menu != null and is_instance_valid(_enemy_context_menu):
		return
	_enemy_context_menu = EnemyContextMenuUI.new()
	_enemy_context_menu.name = "EnemyContextMenuUI"
	_enemy_context_menu.inspect_pressed.connect(_on_enemy_context_inspect_pressed)
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	host.add_child(_enemy_context_menu)


func _on_enemy_context_inspect_pressed(enemy: EnemyInstance) -> void:
	if enemy == null:
		return
	_ensure_enemy_inspect()
	if _enemy_inspect:
		_enemy_inspect.open_enemy(enemy)


func _open_enemy_inspect(index: int) -> void:
	## Kept for callers that already have an enemy index.
	if combat == null or index < 0 or index >= combat.enemies.size():
		return
	_on_enemy_context_inspect_pressed(combat.enemies[index])


func _on_enemy_selected(index: int) -> void:
	if combat == null:
		return
	for i in _enemy_row.get_child_count():
		var panel: PanelContainer = _enemy_row.get_child(i) as PanelContainer
		if panel == null:
			continue
		var selected := i == index
		_style_enemy_panel(panel, i, selected)
		var marker: Label = panel.find_child("SelectMarker", true, false) as Label
		if marker:
			marker.text = "▼" if selected else ""


func _on_ap_changed(current: int, maximum: int) -> void:
	_ap_label.text = tr("KEY_AP_FMT") % [tr("KEY_AP"), current, maximum]


func _on_hp_changed(current: int, maximum: int) -> void:
	_hp_label.text = tr("KEY_FRAME_HP_FMT") % [tr("KEY_FRAME_HP"), current, maximum]


func _on_block_changed(amount: int) -> void:
	_block_label.text = tr("KEY_BLOCK_FMT") % [tr("KEY_BLOCK"), amount]


func _on_turn_started(is_player: bool) -> void:
	_turn_label.text = tr("KEY_PLAYER_TURN") if is_player else tr("KEY_ENEMY_TURN")
	_end_turn_btn.disabled = not is_player
	_rebuild_enemies()


func _on_enemy_hp(index: int, current: int, maximum: int) -> void:
	if index < 0 or index >= _enemy_row.get_child_count():
		return
	var panel: Node = _enemy_row.get_child(index)
	var hp_l: Label = panel.find_child("HP", true, false) as Label
	if hp_l:
		hp_l.text = tr("KEY_HP_FMT") % [tr("KEY_HP"), current, maximum]
	if current <= 0:
		panel.modulate = Color(0.3, 0.3, 0.3, 0.6)
		(panel as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_log(text: String) -> void:
	_log.append_text(text + "\n")


func _on_combat_ended(victory: bool) -> void:
	if _enemy_context_menu and _enemy_context_menu.is_open():
		_enemy_context_menu.close()
	_end_turn_btn.disabled = true
	_continue_btn.visible = true
	_continue_btn.text = tr("KEY_CONTINUE") if victory else tr("KEY_RETURN_TO_MAP")
	_turn_label.text = tr("KEY_VICTORY") if victory else tr("KEY_FRAME_FAILURE")


func _on_enemy_combat_text(enemy_index: int, text: String, kind: String) -> void:
	if text.is_empty() or enemy_index < 0 or enemy_index >= _enemy_row.get_child_count():
		return
	var panel: Control = _enemy_row.get_child(enemy_index) as Control
	if panel == null:
		return
	var host: Control = panel.find_child("CombatTextHost", true, false) as Control
	if host == null:
		host = panel
	_spawn_floating_combat_text(host, text, kind)


func _spawn_floating_combat_text(host: Control, text: String, kind: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 80
	label.add_theme_font_size_override("font_size", 15 if kind == "crit" else 14)
	match kind:
		"crit":
			label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		"pre_action":
			label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
		"multi_hit":
			label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
		_:
			label.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	host.add_child(label)
	await get_tree().process_frame
	if not is_instance_valid(label):
		return
	var host_w := maxf(host.size.x, 80.0)
	var label_w := label.get_minimum_size().x
	label.position = Vector2((host_w - label_w) * 0.5, -4.0)
	var start_y := label.position.y
	var tween := host.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", start_y - 36.0, 0.85).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_OUT
	)
	tween.tween_property(label, "modulate:a", 0.0, 0.85).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)
