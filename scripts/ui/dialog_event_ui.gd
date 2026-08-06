class_name DialogEventUI
extends Control
## Full-screen Slay-the-Spire-style dialog event:
## left narrative + choices, right event art (aspect preserved).

signal choice_resolved(outcome: DialogOutcomeData)
signal event_finished(outcome: DialogOutcomeData)
signal closed_without_outcome

const FADE_IN_DURATION := 0.4
const FADE_OUT_DURATION := 0.3
## Baseline sizes tuned for 1280×720; scaled by viewport height.
const BASE_VIEWPORT_H := 720.0
const TITLE_FONT_BASE := 26
const STORY_FONT_BASE := 14
const ITALICS_FONT_BASE := 13
const RESULT_FONT_BASE := 13
const CHOICE_FONT_BASE := 12
const CHOICE_MIN_HEIGHT_BASE := 36.0
const END_ENCOUNTER_ID := "end_encounter"

@onready var _title_label: Label = %TitleLabel
@onready var _story_badge: Label = %StoryBadge
@onready var _story_text: RichTextLabel = %StoryText
@onready var _result_label: Label = %ResultLabel
@onready var _choices_box: VBoxContainer = %ChoicesBox
@onready var _event_image: TextureRect = %EventImage
@onready var _image_placeholder: ColorRect = %ImagePlaceholder
@onready var _left_panel: MarginContainer = %LeftPanel
@onready var _right_panel: Control = %RightPanel

var _dialog: DialogEventData
var _encounter_manager: EncounterManager
var _encounter_type: int = EncounterData.EncounterType.EVENT
var _current_node_id: String = ""
var _fade_tween: Tween
var _is_closing: bool = false
var _choices_locked: bool = false
var _pending_select_outcome: DialogOutcomeData
var _pending_stat_choice: DialogChoiceData
var _check_boost_ap: int = 0
var _pending_use_neuro: bool = false
var _pending_use_synapse: bool = false
var _pending_use_neuron_amp: bool = false


func _ready() -> void:
	visible = false
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _event_image:
		_event_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		## Keep aspect — do not squash the god portrait.
		_event_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.connect(_on_language_changed)
	if not get_viewport().size_changed.is_connected(_on_viewport_resized):
		get_viewport().size_changed.connect(_on_viewport_resized)
	_apply_responsive_layout()


func bind_encounter_manager(manager: EncounterManager) -> void:
	_encounter_manager = manager


func set_encounter_type(encounter_type: int) -> void:
	_encounter_type = encounter_type
	_apply_story_badge()


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
	_apply_responsive_layout()


func start_event(dialog: DialogEventData) -> void:
	open_dialog(dialog)


func open_dialog(dialog: DialogEventData) -> void:
	if dialog == null:
		return
	_kill_fade_tween()
	_is_closing = false
	_choices_locked = false
	_dialog = dialog
	_current_node_id = dialog.start_node_id
	_apply_responsive_layout()
	_apply_story_badge()
	_apply_event_image(dialog)
	_show_node(_current_node_id)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0
	move_to_front()
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_QUAD)
	_fade_tween.set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(self, "modulate:a", 1.0, FADE_IN_DURATION)


func close_dialog() -> void:
	_kill_fade_tween()
	_is_closing = false
	_choices_locked = false
	visible = false
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog = null
	_clear_choices()


func _on_viewport_resized() -> void:
	_apply_responsive_layout()
	if _dialog != null and visible:
		_show_node(_current_node_id)


func _ui_scale() -> float:
	var h := get_viewport_rect().size.y
	if h <= 1.0:
		h = BASE_VIEWPORT_H
	return clampf(h / BASE_VIEWPORT_H, 0.85, 1.35)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	var title_size := int(round(TITLE_FONT_BASE * s))
	var story_size := int(round(STORY_FONT_BASE * s))
	var result_size := int(round(RESULT_FONT_BASE * s))
	var choice_size := int(round(CHOICE_FONT_BASE * s))
	var choice_min_h := CHOICE_MIN_HEIGHT_BASE * s

	if _left_panel:
		_left_panel.add_theme_constant_override("margin_left", int(28 * s))
		_left_panel.add_theme_constant_override("margin_top", int(16 * s))
		_left_panel.add_theme_constant_override("margin_right", int(20 * s))
		_left_panel.add_theme_constant_override("margin_bottom", int(24 * s))
		_left_panel.size_flags_stretch_ratio = 0.54
	if _right_panel:
		_right_panel.size_flags_stretch_ratio = 0.46

	if _title_label:
		_title_label.add_theme_font_size_override("font_size", title_size)
		_title_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97))
		_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _story_badge:
		_story_badge.add_theme_font_size_override("font_size", int(round(12 * s)))
		_story_badge.add_theme_color_override(
			"font_color",
			GamePalette.COLOR_MAIN_STORY if GamePalette != null else Color("#F1C40F")
		)
	_apply_story_badge()
	if _story_text:
		_story_text.bbcode_enabled = true
		_story_text.scroll_active = true
		_story_text.fit_content = false
		_story_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_story_text.add_theme_font_size_override("normal_font_size", story_size)
		_story_text.add_theme_font_size_override("bold_font_size", story_size)
		_story_text.add_theme_font_size_override("italics_font_size", int(round(ITALICS_FONT_BASE * s)))
		_story_text.add_theme_color_override("default_color", Color(0.82, 0.82, 0.86))
		_story_text.add_theme_constant_override("line_separation", int(round(4 * s)))
	if _result_label:
		_result_label.add_theme_font_size_override("font_size", result_size)
		_result_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
		_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _choices_box:
		_choices_box.add_theme_constant_override("separation", int(round(8 * s)))
		## Stash scaled choice metrics for button builders.
		_choices_box.set_meta("choice_font", choice_size)
		_choices_box.set_meta("choice_min_h", choice_min_h)
	if _event_image:
		_event_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


func _apply_event_image(dialog: DialogEventData) -> void:
	var tex: Texture2D = dialog.get_image_texture() if dialog != null else null
	if _event_image:
		_event_image.texture = tex
		_event_image.visible = tex != null
		_event_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if _image_placeholder:
		_image_placeholder.visible = true
		_image_placeholder.color = Color(0.03, 0.03, 0.04, 1) if tex != null else Color(0.08, 0.08, 0.1, 1)


func _apply_story_badge() -> void:
	if _story_badge == null:
		return
	var is_main_story := _encounter_type == EncounterData.EncounterType.MAIN_STORY
	_story_badge.visible = is_main_story
	_story_badge.text = tr("KEY_MAIN_STORY_BADGE")


func _show_node(node_id: String) -> void:
	if _dialog == null:
		return
	if node_id == END_ENCOUNTER_ID or node_id.is_empty():
		_finish_with_outcome(DialogOutcomeData.make_end())
		return
	var node := _dialog.get_node(node_id)
	if node == null:
		_finish_with_outcome(DialogOutcomeData.make_end())
		return
	_current_node_id = node.id
	if _title_label:
		_title_label.text = _dialog.get_display_title()
	if _story_text:
		_story_text.text = _format_story_bbcode(node)
		_story_text.scroll_to_line(0)
	if _result_label:
		_result_label.visible = false
		_result_label.text = ""
	_rebuild_choices(node)


func _rebuild_choices(node: DialogNodeData) -> void:
	_clear_choices()
	if node.choices.is_empty():
		var done := _make_choice_button(tr("KEY_CONTINUE"))
		done.pressed.connect(func() -> void:
			_finish_with_outcome(DialogOutcomeData.make_end())
		)
		_choices_box.add_child(done)
		return
	for choice: DialogChoiceData in node.choices:
		if choice == null:
			continue
		var btn := _make_choice_button(choice.get_display_text())
		var captured := choice
		btn.pressed.connect(func() -> void: _on_choice_pressed(captured))
		_choices_box.add_child(btn)


func _make_choice_button(label: String) -> Button:
	var font_size: int = int(_choices_box.get_meta("choice_font", CHOICE_FONT_BASE))
	var min_h: float = float(_choices_box.get_meta("choice_min_h", CHOICE_MIN_HEIGHT_BASE))
	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, min_h)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.clip_text = false
	return btn


func _clear_choices() -> void:
	if _choices_box == null:
		return
	for child in _choices_box.get_children():
		child.queue_free()


func _on_choice_pressed(choice: DialogChoiceData) -> void:
	if choice == null or _is_closing or _choices_locked:
		return
	if choice.has_stat_check():
		_begin_stat_check_prepare(choice)
		return
	_resolve_choice_outcome(choice.success_outcome)


func _begin_stat_check_prepare(choice: DialogChoiceData, preserve_boost: bool = false) -> void:
	_pending_stat_choice = choice
	if not preserve_boost:
		_check_boost_ap = 0
		_pending_use_neuro = false
		_pending_use_synapse = false
		_pending_use_neuron_amp = false
	_clear_choices()

	var guaranteed := (
		(StatCheckManager != null and StatCheckManager.force_guaranteed_success)
		or _pending_use_synapse
	)
	if _result_label:
		_result_label.visible = true
		if guaranteed:
			_result_label.text = tr("KEY_STAT_CHECK_GUARANTEED")
		elif _check_boost_ap > 0:
			_result_label.text = "%s  (+%dd6)" % [
				tr("KEY_STAT_CHECK_PREPARE") % choice.stat_check.to_upper(),
				_check_boost_ap * 2,
			]
		else:
			_result_label.text = tr("KEY_STAT_CHECK_PREPARE") % choice.stat_check.to_upper()

	var inventory := _get_inventory()
	if (
		StatCheckManager != null
		and not _pending_use_neuro
		and StatCheckManager.has_neuro_stimulator(inventory)
	):
		var neuro_btn := _make_choice_button(tr("KEY_STAT_CHECK_USE_NEURO"))
		neuro_btn.pressed.connect(_on_use_neuro_for_check)
		_choices_box.add_child(neuro_btn)
	if (
		StatCheckManager != null
		and not _pending_use_synapse
		and StatCheckManager.has_synapse_booster(inventory)
	):
		var syn_btn := _make_choice_button(tr("KEY_STAT_CHECK_USE_SYNAPSE"))
		syn_btn.pressed.connect(_on_use_synapse_for_check)
		_choices_box.add_child(syn_btn)
	if (
		StatCheckManager != null
		and not _pending_use_neuron_amp
		and StatCheckManager.has_neuron_amplifier(inventory)
	):
		_add_neuron_amplifier_choice_button(inventory)

	var roll_label := tr("KEY_STAT_CHECK_ROLL")
	if guaranteed:
		roll_label = tr("KEY_STAT_CHECK_GUARANTEED")
	elif _check_boost_ap > 0:
		roll_label = "%s (+%dd6)" % [tr("KEY_STAT_CHECK_ROLL"), _check_boost_ap * 2]
	var roll_btn := _make_choice_button(roll_label)
	roll_btn.pressed.connect(_on_confirm_stat_check)
	_choices_box.add_child(roll_btn)

	var cancel_btn := _make_choice_button(tr("KEY_STAT_CHECK_CANCEL"))
	cancel_btn.pressed.connect(_on_cancel_stat_check)
	_choices_box.add_child(cancel_btn)


func _add_neuron_amplifier_choice_button(inventory: InventoryController) -> void:
	var cost := 4
	if inventory != null:
		cost = inventory.get_neuron_amplifier_hp_cost()
	var btn := _BbcodeTooltipButton.new()
	btn.text = tr("KEY_STAT_CHECK_USE_NEURON") % cost
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, float(_choices_box.get_meta("choice_min_h", CHOICE_MIN_HEIGHT_BASE)))
	btn.add_theme_font_size_override("font_size", int(_choices_box.get_meta("choice_font", CHOICE_FONT_BASE)))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.clip_text = false
	var safe := inventory != null and inventory.can_safely_use_neuron_amplifier()
	if safe:
		btn.modulate = Color.WHITE
		btn.tooltip_text = ""
		btn.set_meta("blocked", false)
		btn.pressed.connect(_on_use_neuron_amp_for_check)
	else:
		## Keep hoverable so the BBCode unsafe tooltip still shows.
		btn.modulate = Color(0.55, 0.55, 0.55, 1.0)
		btn.tooltip_text = tr("KEY_NEURON_AMP_UNSAFE")
		btn.set_meta("blocked", true)
		btn.pressed.connect(func() -> void: pass)
	_choices_box.add_child(btn)


func _on_use_neuro_for_check() -> void:
	if _pending_stat_choice == null or StatCheckManager == null:
		return
	if not StatCheckManager.has_neuro_stimulator(_get_inventory()):
		return
	## Stage consumption until the roll is confirmed (cancel keeps the item).
	_pending_use_neuro = true
	_check_boost_ap += StatCheckManager.NEURO_CHECK_AP_VALUE
	_begin_stat_check_prepare(_pending_stat_choice, true)


func _on_use_synapse_for_check() -> void:
	if _pending_stat_choice == null or StatCheckManager == null:
		return
	if not StatCheckManager.has_synapse_booster(_get_inventory()):
		return
	_pending_use_synapse = true
	_begin_stat_check_prepare(_pending_stat_choice, true)


func _on_use_neuron_amp_for_check() -> void:
	if _pending_stat_choice == null or StatCheckManager == null:
		return
	var inventory := _get_inventory()
	if not StatCheckManager.has_neuron_amplifier(inventory):
		return
	if inventory == null or not inventory.can_safely_use_neuron_amplifier():
		return
	## Stage until roll confirm — cancel keeps HP.
	_pending_use_neuron_amp = true
	_check_boost_ap += StatCheckManager.NEURON_CHECK_AP_VALUE
	_begin_stat_check_prepare(_pending_stat_choice, true)


func _on_confirm_stat_check() -> void:
	var choice := _pending_stat_choice
	if choice == null:
		return
	var inventory := _get_inventory()
	if _pending_use_neuro and StatCheckManager != null:
		if StatCheckManager.try_consume_neuro_stimulator(inventory) <= 0:
			_check_boost_ap = maxi(0, _check_boost_ap - StatCheckManager.NEURO_CHECK_AP_VALUE)
		_pending_use_neuro = false
	if _pending_use_synapse and StatCheckManager != null:
		if not StatCheckManager.try_consume_synapse_booster(inventory):
			_pending_use_synapse = false
		else:
			_pending_use_synapse = false
	if _pending_use_neuron_amp and StatCheckManager != null:
		if StatCheckManager.try_use_neuron_amplifier(inventory) <= 0:
			_check_boost_ap = maxi(0, _check_boost_ap - StatCheckManager.NEURON_CHECK_AP_VALUE)
		_pending_use_neuron_amp = false
	_pending_stat_choice = null
	var required := choice.get_required_successes()
	var result: StatCheckManager.CheckResult = null
	if _encounter_manager != null:
		result = _encounter_manager.resolve_stat_check(
			choice.stat_check, required, _check_boost_ap
		)
	elif StatCheckManager != null:
		result = StatCheckManager.perform_check(1, required, _check_boost_ap)
	_check_boost_ap = 0
	var passed := result != null and result.is_success
	var outcome: DialogOutcomeData = choice.success_outcome if passed else choice.failure_outcome
	if _result_label:
		_result_label.visible = true
		if result != null and result.is_guaranteed:
			_result_label.text = tr("KEY_STAT_CHECK_GUARANTEED")
		else:
			_result_label.text = (
				tr("KEY_STAT_CHECK_SUCCESS") if passed else tr("KEY_STAT_CHECK_FAILURE")
			)
	_resolve_choice_outcome(outcome)


func _on_cancel_stat_check() -> void:
	_pending_stat_choice = null
	_check_boost_ap = 0
	_pending_use_neuro = false
	_pending_use_synapse = false
	_pending_use_neuron_amp = false
	if _dialog == null:
		return
	_show_node(_current_node_id)


func _get_inventory() -> InventoryController:
	if _encounter_manager != null:
		return _encounter_manager.inventory
	return null


func _resolve_choice_outcome(outcome: DialogOutcomeData) -> void:
	if outcome == null:
		outcome = DialogOutcomeData.make_end()

	## Rewards first, then branch — or fade out on end_encounter.
	if outcome.kind == DialogOutcomeData.OutcomeKind.SELECT_ITEM:
		_choices_locked = true
		if _encounter_manager:
			if not _encounter_manager.item_selection_resolved.is_connected(_on_item_selection_resolved):
				_encounter_manager.item_selection_resolved.connect(
					_on_item_selection_resolved, CONNECT_ONE_SHOT
				)
			_pending_select_outcome = outcome
			_encounter_manager.apply_dialog_outcome(outcome)
		else:
			_finish_with_outcome(outcome)
		return

	if _is_continuing_outcome(outcome):
		if _encounter_manager:
			_encounter_manager.apply_dialog_outcome(outcome)
		if not outcome.message_key.is_empty() and _result_label:
			_result_label.visible = true
			_result_label.text = tr(outcome.message_key)
		var next_id := outcome.next_node_id.strip_edges()
		if next_id.is_empty() or next_id == END_ENCOUNTER_ID:
			_finish_with_outcome(DialogOutcomeData.make_end(outcome.message_key))
			return
		_show_node(next_id)
		return

	_finish_with_outcome(outcome)


func _on_item_selection_resolved(_item: ItemData) -> void:
	_choices_locked = false
	var outcome := _pending_select_outcome
	_pending_select_outcome = null
	if outcome == null:
		_finish_with_outcome(DialogOutcomeData.make_end())
		return
	var next_id := outcome.next_node_id.strip_edges()
	if next_id.is_empty() or next_id == END_ENCOUNTER_ID:
		_finish_with_outcome(DialogOutcomeData.make_end(outcome.message_key))
		return
	_show_node(next_id)


func _is_continuing_outcome(outcome: DialogOutcomeData) -> bool:
	if outcome == null:
		return false
	if outcome.kind == DialogOutcomeData.OutcomeKind.CONTINUE:
		return true
	return (
		outcome.kind in [
			DialogOutcomeData.OutcomeKind.HEAL,
			DialogOutcomeData.OutcomeKind.DAMAGE,
			DialogOutcomeData.OutcomeKind.GRANT_ITEM,
			DialogOutcomeData.OutcomeKind.GRANT_STAT,
		]
		and not outcome.next_node_id.is_empty()
		and outcome.next_node_id != END_ENCOUNTER_ID
	)


func _format_story_bbcode(node: DialogNodeData) -> String:
	## Prefer narrator_text + speech_text composition with paragraph breaks.
	if node == null:
		return ""
	var composed := node.compose_story_bbcode().strip_edges()
	if composed.is_empty():
		composed = node.get_display_text().strip_edges()
	if composed.is_empty():
		return ""
	## Already tagged narrator blocks stay as authored.
	if composed.find("[i]") >= 0 or composed.find("[I]") >= 0:
		return composed
	## Fallback auto-italicize non-speech paragraphs.
	var blocks: PackedStringArray = composed.split("\n\n", false)
	var out: PackedStringArray = []
	for block in blocks:
		var trimmed := block.strip_edges()
		if trimmed.is_empty():
			continue
		var is_speech := (
			trimmed.begins_with("«")
			or trimmed.begins_with("\"")
			or trimmed.begins_with("“")
			or trimmed.begins_with("'")
		)
		out.append(trimmed if is_speech else "[i]%s[/i]" % trimmed)
	return "\n\n".join(out)


func _finish_with_outcome(outcome: DialogOutcomeData) -> void:
	if _is_closing:
		return
	_is_closing = true
	_choices_locked = true
	_set_choices_disabled(true)
	await _play_exit_fade()
	if _encounter_manager:
		_encounter_manager.apply_dialog_outcome(outcome)
	choice_resolved.emit(outcome)
	event_finished.emit(outcome)
	_dialog = null
	visible = false
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clear_choices()
	_is_closing = false
	_choices_locked = false


func _play_exit_fade() -> void:
	_kill_fade_tween()
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_QUAD)
	_fade_tween.set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_DURATION)
	await _fade_tween.finished


func _kill_fade_tween() -> void:
	if _fade_tween != null and is_instance_valid(_fade_tween):
		_fade_tween.kill()
	_fade_tween = null


func _set_choices_disabled(disabled: bool) -> void:
	if _choices_box == null:
		return
	for child in _choices_box.get_children():
		if child is BaseButton:
			(child as BaseButton).disabled = disabled


func _on_language_changed(_locale: String = "") -> void:
	if _dialog == null or not visible:
		return
	_show_node(_current_node_id)


## Choice button that can render BBCode tooltips (unsafe Neuron Amplifier warning).
class _BbcodeTooltipButton extends Button:
	func _make_custom_tooltip(for_text: String) -> Object:
		if for_text.is_empty():
			return null
		var tip := RichTextLabel.new()
		tip.bbcode_enabled = true
		tip.fit_content = true
		tip.scroll_active = false
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.custom_minimum_size = Vector2(240, 0)
		tip.text = for_text
		tip.add_theme_font_size_override("normal_font_size", 12)
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.08, 0.09, 0.96)
		style.set_border_width_all(1)
		style.border_color = Color(0.45, 0.45, 0.5)
		style.set_content_margin_all(8)
		style.set_corner_radius_all(4)
		panel.add_theme_stylebox_override("panel", style)
		panel.add_child(tip)
		return panel
