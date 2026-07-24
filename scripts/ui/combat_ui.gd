extends Control
## Combat HUD: enemies, AP/HP/Block, activatable modules, log, end turn.

signal end_turn_pressed
signal activate_item_requested(placed: PlacedItem)
signal target_selected(index: int)
signal continue_pressed

var combat: Node  # CombatManager
var inventory: InventoryController

@onready var _enemy_row: HBoxContainer = %EnemyRow
@onready var _hp_label: Label = %HPLabel
@onready var _ap_label: Label = %APLabel
@onready var _block_label: Label = %BlockLabel
@onready var _turn_label: Label = %TurnLabel
@onready var _action_list: VBoxContainer = %ActionList
@onready var _log: RichTextLabel = %CombatLog
@onready var _end_turn_btn: Button = %EndTurnButton
@onready var _continue_btn: Button = %ContinueButton
@onready var _actions_title: Label = $VBox/Mid/ActionsPanel/ActionsTitle


func _ready() -> void:
	_end_turn_btn.pressed.connect(func() -> void: end_turn_pressed.emit())
	_continue_btn.pressed.connect(func() -> void: continue_pressed.emit())
	_continue_btn.visible = false
	EventBus.ap_changed.connect(_on_ap_changed)
	EventBus.player_hp_changed.connect(_on_hp_changed)
	EventBus.block_changed.connect(_on_block_changed)
	EventBus.combat_log_message.connect(_on_log)
	EventBus.enemy_hp_changed.connect(_on_enemy_hp)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.inventory_changed.connect(_rebuild_actions)
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
	_rebuild_actions()


func _on_language_changed(_locale: String) -> void:
	_apply_static_locale()
	if inventory:
		_on_hp_changed(inventory.current_hp, inventory.max_hp)
	if combat:
		_on_ap_changed(combat.current_ap, combat.max_ap)
		_on_block_changed(combat.current_block)
		_rebuild_enemies()
		_rebuild_actions()
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
	if _actions_title:
		_actions_title.text = tr("KEY_MODULES")


func _rebuild_enemies() -> void:
	for child in _enemy_row.get_children():
		child.queue_free()
	if combat == null:
		return
	for i in combat.enemies.size():
		var entry: Dictionary = combat.enemies[i]
		var data: EnemyData = entry["data"]
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.12, 0.12)
		style.set_border_width_all(2)
		style.border_color = data.placeholder_color
		style.set_content_margin_all(10)
		panel.add_theme_stylebox_override("panel", style)

		var v := VBoxContainer.new()
		var name_l := Label.new()
		name_l.text = data.get_localized_name()
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var sprite := ColorRect.new()
		sprite.custom_minimum_size = Vector2(80, 100)
		sprite.color = data.placeholder_color
		var hp_l := Label.new()
		hp_l.name = "HP"
		hp_l.text = tr("KEY_HP_FMT") % [tr("KEY_HP"), int(entry["hp"]), data.max_hp]
		hp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		var target_btn := Button.new()
		target_btn.text = tr("KEY_TARGET")
		target_btn.pressed.connect(_on_target.bind(i))

		v.add_child(name_l)
		v.add_child(sprite)
		v.add_child(hp_l)
		v.add_child(target_btn)
		panel.add_child(v)
		_enemy_row.add_child(panel)


func _rebuild_actions() -> void:
	for child in _action_list.get_children():
		child.queue_free()
	if inventory == null:
		return
	for placed: PlacedItem in inventory.grid.get_functional_items():
		if placed.data.ap_cost <= 0:
			continue
		var btn := Button.new()
		var tag := tr("KEY_ATK") if placed.data.is_weapon() else tr("KEY_BLK")
		btn.text = tr("KEY_ACTION_ITEM_FMT") % [
			tag,
			placed.data.get_localized_name(),
			placed.data.ap_cost,
			tr("KEY_AP"),
		]
		btn.pressed.connect(_on_activate.bind(placed))
		_action_list.add_child(btn)

	for placed: PlacedItem in inventory.grid.get_functional_items():
		if placed.data.ap_cost > 0:
			continue
		var info := Label.new()
		info.text = tr("KEY_PASSIVE_FMT") % [tr("KEY_PASSIVE"), placed.data.get_localized_name()]
		info.modulate = Color(0.7, 0.7, 0.7)
		_action_list.add_child(info)


func _on_activate(placed: PlacedItem) -> void:
	activate_item_requested.emit(placed)


func _on_target(index: int) -> void:
	target_selected.emit(index)
	_on_log(tr("KEY_LOG_TARGETING") % (index + 1))


func _on_ap_changed(current: int, maximum: int) -> void:
	_ap_label.text = tr("KEY_AP_FMT") % [tr("KEY_AP"), current, maximum]


func _on_hp_changed(current: int, maximum: int) -> void:
	_hp_label.text = tr("KEY_FRAME_HP_FMT") % [tr("KEY_FRAME_HP"), current, maximum]


func _on_block_changed(amount: int) -> void:
	_block_label.text = tr("KEY_BLOCK_FMT") % [tr("KEY_BLOCK"), amount]


func _on_turn_started(is_player: bool) -> void:
	_turn_label.text = tr("KEY_PLAYER_TURN") if is_player else tr("KEY_ENEMY_TURN")
	_end_turn_btn.disabled = not is_player
	_rebuild_actions()


func _on_enemy_hp(index: int, current: int, maximum: int) -> void:
	if index < 0 or index >= _enemy_row.get_child_count():
		return
	var panel: Node = _enemy_row.get_child(index)
	var hp_l: Label = panel.find_child("HP", true, false) as Label
	if hp_l:
		hp_l.text = tr("KEY_HP_FMT") % [tr("KEY_HP"), current, maximum]
	if current <= 0:
		panel.modulate = Color(0.3, 0.3, 0.3, 0.6)


func _on_log(text: String) -> void:
	_log.append_text(text + "\n")


func _on_combat_ended(victory: bool) -> void:
	_end_turn_btn.disabled = true
	_continue_btn.visible = true
	_continue_btn.text = tr("KEY_CONTINUE") if victory else tr("KEY_RETURN_TO_MAP")
	_turn_label.text = tr("KEY_VICTORY") if victory else tr("KEY_FRAME_FAILURE")
