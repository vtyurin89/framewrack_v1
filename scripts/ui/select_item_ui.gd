class_name SelectItemUI
extends Control
## Stubbed item-choice overlay for dialog / post-combat rewards.

signal item_selected(item: ItemData)
signal closed

@onready var _title_label: Label = %TitleLabel
@onready var _placeholder_label: Label = %PlaceholderLabel
@onready var _confirm_button: Button = %ConfirmButton
@onready var _panel: PanelContainer = %Panel

var _item_pool: Array = []
var _is_open: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _confirm_button and not _confirm_button.pressed.is_connected(_on_confirm_pressed):
		_confirm_button.pressed.connect(_on_confirm_pressed)


func is_open() -> bool:
	return _is_open


func open_item_selection(item_pool: Array, title: String = "Выберите награду") -> void:
	_item_pool = item_pool.duplicate()
	if _title_label:
		_title_label.text = title if not title.is_empty() else "Выберите награду"
	if _placeholder_label:
		var count := _item_pool.size()
		_placeholder_label.text = (
			"TODO: Implement Item Choice Cards\n(pool size: %d)" % count
		)
	visible = true
	_is_open = true
	move_to_front()


func close() -> void:
	_is_open = false
	visible = false
	closed.emit()


func _on_confirm_pressed() -> void:
	_on_item_selected(_pick_default_item())


func _on_item_selected(selected_item: ItemData) -> void:
	item_selected.emit(selected_item)
	close()


func _pick_default_item() -> ItemData:
	## Stub: resolve the first valid pool entry, or a safe fallback weapon.
	for entry in _item_pool:
		if entry is ItemData:
			return (entry as ItemData).duplicate(true) as ItemData
		var id := str(entry).strip_edges()
		if id.is_empty() or ItemDatabase == null:
			continue
		var created := ItemDatabase.create_instance(id)
		if created != null:
			return created
	if ItemDatabase != null:
		var fallback := ItemDatabase.create_instance("SURGICAL_SAW")
		if fallback != null:
			return fallback
		fallback = ItemDatabase.create_instance("SCRAP_PIPE")
		if fallback != null:
			return fallback
	return null
