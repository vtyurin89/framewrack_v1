class_name ChestRewardUI
extends Control
## Map reward-site chest interaction (open / locked). Hosted in CombatUI LootStage.

signal continue_requested
signal loot_opened

const LOCK_SHAKE_PX := 10.0
const LOCK_SHAKE_DURATION := 0.08
const LOCK_FALL_DURATION := 0.55
const CHEST_FADE_DURATION := 0.35

const TEX_CHEST_CLOSED := preload("res://assets/sprites/ui/chest_closed.png")
const TEX_CHEST_OPEN := preload("res://assets/sprites/ui/chest_open.png")
const TEX_LOCK := preload("res://assets/sprites/ui/chest_lock.png")

var inventory: InventoryController
var _locked: bool = false
var _busy: bool = false
var _opened_for_loot: bool = false

var _chest_btn: TextureButton
var _lock_sprite: TextureRect
var _hint_label: Label
var _anim_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false
	if not LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.connect(_on_language_changed)


func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 16)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(column)

	var chest_host := Control.new()
	chest_host.custom_minimum_size = Vector2(220, 180)
	chest_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(chest_host)

	_chest_btn = TextureButton.new()
	_chest_btn.ignore_texture_size = true
	_chest_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_chest_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chest_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_chest_btn.pressed.connect(_on_chest_pressed)
	chest_host.add_child(_chest_btn)

	_lock_sprite = TextureRect.new()
	_lock_sprite.texture = TEX_LOCK
	_lock_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lock_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lock_sprite.custom_minimum_size = Vector2(72, 72)
	_lock_sprite.size = Vector2(72, 72)
	_lock_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_sprite.pivot_offset = Vector2(36, 36)
	chest_host.add_child(_lock_sprite)
	## Centered over the chest body.
	_lock_sprite.position = Vector2(74, 54)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(360, 0)
	_hint_label.add_theme_font_size_override("normal_font_size", 15)
	_hint_label.add_theme_color_override("font_color", Color(0.92, 0.72, 0.45, 1))
	_hint_label.visible = false
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_hint_label)


func open_session(p_inventory: InventoryController, locked: bool) -> void:
	inventory = p_inventory
	_locked = locked
	_busy = false
	_opened_for_loot = false
	_clear_hint()
	_apply_chest_visual()
	visible = true
	modulate.a = 1.0


func close_session() -> void:
	_kill_tween()
	visible = false
	_busy = false
	_opened_for_loot = false
	_clear_hint()


func is_active() -> bool:
	return visible and not _opened_for_loot


func _apply_chest_visual() -> void:
	if _chest_btn == null:
		return
	_chest_btn.texture_normal = TEX_CHEST_CLOSED if _locked else TEX_CHEST_OPEN
	_chest_btn.texture_pressed = _chest_btn.texture_normal
	_chest_btn.texture_hover = _chest_btn.texture_normal
	if _lock_sprite:
		_lock_sprite.visible = _locked
		_lock_sprite.modulate = Color.WHITE
		_lock_sprite.position = Vector2(74, 54)
		_lock_sprite.rotation = 0.0


func _on_chest_pressed() -> void:
	if _busy or _opened_for_loot or not visible:
		return
	if _locked:
		_try_unlock()
	else:
		_open_loot()


func _try_unlock() -> void:
	var has_pick := inventory != null and inventory.has_item("LOCKPICK")
	if not has_pick:
		_play_lock_deny()
		return

	_busy = true
	_clear_hint()
	inventory.consume_item_charge("LOCKPICK")
	_play_lock_fall_then_unlock()


func _play_lock_deny() -> void:
	_busy = true
	_show_hint(tr("KEY_CHEST_NEED_LOCKPICK"))
	_kill_tween()
	_anim_tween = create_tween()
	var base := _lock_sprite.position
	_anim_tween.tween_property(_lock_sprite, "position:x", base.x + LOCK_SHAKE_PX, LOCK_SHAKE_DURATION)
	_anim_tween.tween_property(_lock_sprite, "position:x", base.x - LOCK_SHAKE_PX, LOCK_SHAKE_DURATION)
	_anim_tween.tween_property(_lock_sprite, "position:x", base.x + LOCK_SHAKE_PX * 0.6, LOCK_SHAKE_DURATION)
	_anim_tween.tween_property(_lock_sprite, "position:x", base.x, LOCK_SHAKE_DURATION)
	_anim_tween.finished.connect(func() -> void:
		_busy = false
	, CONNECT_ONE_SHOT)


func _play_lock_fall_then_unlock() -> void:
	_kill_tween()
	_anim_tween = create_tween()
	_anim_tween.set_parallel(true)
	_anim_tween.tween_property(_lock_sprite, "position:y", _lock_sprite.position.y + 140.0, LOCK_FALL_DURATION).set_ease(Tween.EASE_IN)
	_anim_tween.tween_property(_lock_sprite, "modulate:a", 0.0, LOCK_FALL_DURATION)
	_anim_tween.tween_property(_lock_sprite, "rotation", 0.6, LOCK_FALL_DURATION)
	_anim_tween.set_parallel(false)
	_anim_tween.tween_callback(func() -> void:
		_locked = false
		_apply_chest_visual()
		_busy = false
	)


func _open_loot() -> void:
	if _opened_for_loot:
		return
	_busy = true
	_opened_for_loot = true
	_clear_hint()
	_kill_tween()
	_anim_tween = create_tween()
	_anim_tween.tween_property(self, "modulate:a", 0.0, CHEST_FADE_DURATION)
	_anim_tween.tween_callback(func() -> void:
		visible = false
		modulate.a = 1.0
		_busy = false
		loot_opened.emit()
	)


func _show_hint(text: String) -> void:
	if _hint_label == null:
		return
	_hint_label.text = text
	_hint_label.visible = not text.is_empty()


func _clear_hint() -> void:
	if _hint_label == null:
		return
	_hint_label.text = ""
	_hint_label.visible = false


func _kill_tween() -> void:
	if _anim_tween != null and is_instance_valid(_anim_tween):
		_anim_tween.kill()
	_anim_tween = null


func _on_language_changed(_locale: String = "") -> void:
	if _hint_label != null and _hint_label.visible and _locked:
		_show_hint(tr("KEY_CHEST_NEED_LOCKPICK"))
