class_name RestSiteUI
extends Control
## Rest / repair-bench encounter UI.
## Layout inspired by StS rest sites; visuals match Framewrack combat chrome.

signal continue_pressed

const FADE_IN_DURATION := 0.35
const FADE_OUT_DURATION := 0.25
const HEAL_FRACTION := 0.3

@onready var _prompt_label: Label = %PromptLabel
@onready var _hover_label: Label = %HoverLabel
@onready var _options_row: HBoxContainer = %OptionsRow
@onready var _heal_button: Button = %HealButton
@onready var _extract_button: Button = %ExtractButton
@onready var _heal_caption: Label = %HealCaption
@onready var _extract_caption: Label = %ExtractCaption
@onready var _continue_btn: Button = %ContinueButton
@onready var _result_label: Label = %ResultLabel

var _inventory: InventoryController
var _encounter_manager: EncounterManager
var _choice_made: bool = false
var _fade_tween: Tween


func _ready() -> void:
	visible = false
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_style_option_button(_heal_button)
	_style_option_button(_extract_button)
	_style_continue_button()
	if _heal_button:
		_heal_button.pressed.connect(_on_heal_pressed)
		_heal_button.mouse_entered.connect(_on_heal_hover)
		_heal_button.mouse_exited.connect(_on_option_unhover)
	if _extract_button:
		_extract_button.pressed.connect(_on_extract_pressed)
		_extract_button.mouse_entered.connect(_on_extract_hover)
		_extract_button.mouse_exited.connect(_on_option_unhover)
	if _continue_btn:
		_continue_btn.pressed.connect(_on_continue_pressed)
	if not LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.connect(_on_language_changed)
	_clear_hint_slot()
	_apply_static_texts()


func _style_option_button(btn: Button) -> void:
	if btn == null:
		return
	btn.flat = false
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	GamePalette.apply_button_theme(btn, 14)


func _style_continue_button() -> void:
	if _continue_btn == null:
		return
	_continue_btn.custom_minimum_size = Vector2(220, 52)
	_continue_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	GamePalette.apply_button_theme(_continue_btn, 18)


func bind(inventory: InventoryController, manager: EncounterManager) -> void:
	_inventory = inventory
	_encounter_manager = manager


func layout_below_top_bar(top_bar: Control, extra_pad: float = 0.0) -> void:
	if top_bar == null or not is_instance_valid(top_bar):
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	var parent_ctrl := get_parent() as Control
	if parent_ctrl == null:
		return
	var top_bottom_local: float = (
		top_bar.get_global_rect().end.y - parent_ctrl.get_global_rect().position.y + extra_pad
	)
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = maxf(top_bottom_local, 0.0)
	offset_right = 0.0
	offset_bottom = 0.0


func open_rest_site() -> void:
	_kill_fade_tween()
	_choice_made = false
	_apply_static_texts()
	_set_choice_phase(true)
	_clear_hint_slot()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0
	move_to_front()
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_QUAD)
	_fade_tween.set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(self, "modulate:a", 1.0, FADE_IN_DURATION)


func close_rest_site() -> void:
	_kill_fade_tween()
	_choice_made = false
	visible = false
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _apply_static_texts() -> void:
	if _prompt_label:
		_prompt_label.text = tr("KEY_REST_SITE_PROMPT")
	if _heal_caption:
		_heal_caption.text = tr("KEY_REST_OPTION_HEAL")
	if _extract_caption:
		_extract_caption.text = tr("KEY_REST_OPTION_EXTRACT")
	if _continue_btn:
		_continue_btn.text = tr("KEY_CONTINUE")


func _set_choice_phase(active: bool) -> void:
	if _options_row:
		_options_row.visible = active
	if _heal_button:
		_heal_button.disabled = not active
	if _extract_button:
		_extract_button.disabled = not active
	if _continue_btn:
		_continue_btn.visible = not active
	if _prompt_label:
		_prompt_label.visible = active


func _clear_hint_slot() -> void:
	## Keep HintSlot height reserved — never toggle label visibility for layout.
	if _hover_label:
		_hover_label.text = ""
		_hover_label.modulate.a = 0.0
	if _result_label:
		_result_label.text = ""
		_result_label.modulate.a = 0.0


func _show_hover_text(message: String) -> void:
	if _hover_label == null:
		return
	_hover_label.text = message
	_hover_label.modulate.a = 1.0
	if _result_label:
		_result_label.modulate.a = 0.0


func _preview_heal_amount() -> int:
	## Actual HP that would be restored right now (capped by missing HP).
	if _inventory == null:
		return 0
	var amount := maxi(1, int(floor(float(_inventory.max_hp) * HEAL_FRACTION)))
	var missing := maxi(0, _inventory.max_hp - _inventory.current_hp)
	return mini(amount, missing)


func _on_heal_hover() -> void:
	if _choice_made:
		return
	## Use format() — "%" in "30%" breaks GDScript's % operator.
	_show_hover_text(tr("KEY_REST_HOVER_HEAL").format([_preview_heal_amount()]))


func _on_extract_hover() -> void:
	if _choice_made:
		return
	_show_hover_text(tr("KEY_REST_HOVER_EXTRACT"))


func _on_option_unhover() -> void:
	if _choice_made:
		return
	if _hover_label:
		_hover_label.text = ""
		_hover_label.modulate.a = 0.0


func _on_heal_pressed() -> void:
	if _choice_made or _encounter_manager == null:
		return
	_choice_made = true
	var healed := _encounter_manager.apply_rest_heal(HEAL_FRACTION)
	_show_result(tr("KEY_REST_RESULT_HEAL").format([healed]))


func _on_extract_pressed() -> void:
	if _choice_made or _encounter_manager == null:
		return
	_choice_made = true
	var removed := _encounter_manager.apply_rest_remove_harmful()
	_show_result(tr("KEY_REST_RESULT_EXTRACT").format([removed]))


func _show_result(_message: String) -> void:
	_set_choice_phase(false)
	_clear_hint_slot()


func _on_continue_pressed() -> void:
	if not _choice_made:
		return
	_kill_fade_tween()
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_QUAD)
	_fade_tween.set_ease(Tween.EASE_IN)
	_fade_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_DURATION)
	_fade_tween.tween_callback(_emit_continue)


func _emit_continue() -> void:
	close_rest_site()
	continue_pressed.emit()


func _on_language_changed(_locale: String) -> void:
	_apply_static_texts()
	if visible and not _choice_made and _hover_label != null and _hover_label.modulate.a > 0.0:
		if _heal_button != null and _heal_button.is_hovered():
			_on_heal_hover()
		elif _extract_button != null and _extract_button.is_hovered():
			_on_extract_hover()


func _kill_fade_tween() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
