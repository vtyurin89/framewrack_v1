extends Node
## FIFO queue for floating combat damage / miss / status popups.

const DAMAGE_NUMBER_SCENE := preload("res://scenes/UI/damage_number.tscn")
const POPUP_GAP := 0.12

var _queue: Array[Dictionary] = []
var _processing: bool = false
var _player_anchor: Control
var _enemy_resolver: Callable = Callable()
var _layer: CanvasLayer


func _ready() -> void:
	_ensure_layer()


func _ensure_layer() -> void:
	if _layer != null and is_instance_valid(_layer):
		return
	_layer = CanvasLayer.new()
	_layer.name = "DamagePopUpLayer"
	_layer.layer = 100
	add_child(_layer)


func set_player_anchor(anchor: Control) -> void:
	_player_anchor = anchor


func set_enemy_resolver(resolver: Callable) -> void:
	## resolver(enemy_index: int) -> Control
	_enemy_resolver = resolver


func clear_queue() -> void:
	_queue.clear()


func queue_damage_event(
	target_node: Node,
	amount: int,
	damage_type: String = "physical",
	is_crit: bool = false,
	is_miss: bool = false
) -> void:
	if target_node == null or not is_instance_valid(target_node):
		return
	_queue.append(
		{
			"node": target_node,
			"amount": amount,
			"type": damage_type,
			"crit": is_crit,
			"miss": is_miss,
		}
	)
	if not _processing:
		_process_queue()


func queue_enemy_damage(
	enemy_index: int,
	amount: int,
	damage_type: String = "physical",
	is_crit: bool = false,
	is_miss: bool = false
) -> void:
	var target: Control = null
	if _enemy_resolver.is_valid():
		target = _enemy_resolver.call(enemy_index) as Control
	if target == null:
		push_warning("DamagePopUpManager: no enemy target for index %d" % enemy_index)
		return
	queue_damage_event(target, amount, damage_type, is_crit, is_miss)


func queue_player_damage(
	_amount: int,
	_damage_type: String = "physical",
	_is_crit: bool = false,
	_is_miss: bool = false
) -> void:
	## TEMP stub: player floating numbers are disabled for now.
	## Re-enable by restoring queue_damage_event(_player_anchor, ...) below.
	return


func _process_queue() -> void:
	_processing = true
	while not _queue.is_empty():
		var event: Dictionary = _queue.pop_front()
		var node: Node = event.get("node") as Node
		if node != null and is_instance_valid(node):
			_spawn_popup(
				node,
				int(event.get("amount", 0)),
				str(event.get("type", "physical")),
				bool(event.get("crit", false)),
				bool(event.get("miss", false))
			)
		if not _queue.is_empty():
			await get_tree().create_timer(POPUP_GAP).timeout
	_processing = false


func _spawn_popup(
	target: Node,
	amount: int,
	damage_type: String,
	is_crit: bool,
	is_miss: bool
) -> void:
	_ensure_layer()
	var popup: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate() as DamageNumber
	_layer.add_child(popup)
	## Let DamageNumber place itself from the card rect — avoid pre-setting
	## global_position here (that caused a one-frame sideways/vertical jump).
	var rect := _resolve_target_rect(target)
	popup.setup(amount, damage_type, is_crit, is_miss, rect)


func _resolve_target_rect(target: Node) -> Rect2:
	if target is Control:
		var ctrl := target as Control
		var rect := ctrl.get_global_rect()
		if rect.size.x < 8.0 or rect.size.y < 8.0:
			var parent_ctrl := ctrl.get_parent() as Control
			if parent_ctrl != null:
				rect = parent_ctrl.get_global_rect()
		return rect
	if target is Node2D:
		var p := (target as Node2D).global_position
		return Rect2(p - Vector2(40, 40), Vector2(80, 80))
	return Rect2()


func _resolve_origin(target: Node) -> Vector2:
	return _resolve_target_rect(target).get_center()
