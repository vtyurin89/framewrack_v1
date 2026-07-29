class_name DialogEventUI
extends Control
## Full-screen Slay-the-Spire-style dialog event:
## left narrative + choices (~58%), right event art (~42%).

signal choice_resolved(outcome: DialogOutcomeData)
signal event_finished(outcome: DialogOutcomeData)
signal closed_without_outcome

const FADE_IN_DURATION := 0.4
const FADE_OUT_DURATION := 0.3
const TITLE_FONT_SIZE := 40
const STORY_FONT_SIZE := 22
const RESULT_FONT_SIZE := 18
const CHOICE_FONT_SIZE := 20
const CHOICE_MIN_HEIGHT := 52.0

@onready var _title_label: Label = %TitleLabel
@onready var _story_text: RichTextLabel = %StoryText
@onready var _result_label: Label = %ResultLabel
@onready var _choices_box: VBoxContainer = %ChoicesBox
@onready var _event_image: TextureRect = %EventImage
@onready var _image_placeholder: ColorRect = %ImagePlaceholder

var _dialog: DialogEventData
var _encounter_manager: EncounterManager
var _current_node_id: String = ""
var _fade_tween: Tween
var _is_closing: bool = false
var _choices_locked: bool = false


func _ready() -> void:
	visible = false
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply_typography()
	if _event_image:
		_event_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_event_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if not LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.connect(_on_language_changed)


func bind_encounter_manager(manager: EncounterManager) -> void:
	_encounter_manager = manager


## Keep the shared gameplay TopBar (title / Menu) visible above this module.
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


func start_event(dialog: DialogEventData) -> void:
	## Preferred entry point — fades the module in under the TopBar.
	open_dialog(dialog)


func open_dialog(dialog: DialogEventData) -> void:
	if dialog == null:
		return
	_kill_fade_tween()
	_is_closing = false
	_choices_locked = false
	_dialog = dialog
	_current_node_id = dialog.start_node_id
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


func _apply_typography() -> void:
	if _title_label:
		_title_label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
		_title_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97))
		_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _story_text:
		_story_text.bbcode_enabled = true
		_story_text.scroll_active = true
		_story_text.fit_content = false
		_story_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_story_text.add_theme_font_size_override("normal_font_size", STORY_FONT_SIZE)
		_story_text.add_theme_font_size_override("bold_font_size", STORY_FONT_SIZE)
		_story_text.add_theme_color_override("default_color", Color(0.82, 0.82, 0.86))
		_story_text.add_theme_constant_override("line_separation", 8)
	if _result_label:
		_result_label.add_theme_font_size_override("font_size", RESULT_FONT_SIZE)
		_result_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
		_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _apply_event_image(dialog: DialogEventData) -> void:
	var tex: Texture2D = dialog.get_image_texture() if dialog != null else null
	if _event_image:
		_event_image.texture = tex
		_event_image.visible = tex != null
	if _image_placeholder:
		_image_placeholder.visible = true
		if tex == null:
			_image_placeholder.color = Color(0.08, 0.08, 0.1, 1)
		else:
			## Keep a dark underlay in letterbox gaps from COVERED stretch.
			_image_placeholder.color = Color(0.03, 0.03, 0.04, 1)


func _show_node(node_id: String) -> void:
	if _dialog == null:
		return
	var node := _dialog.get_node(node_id)
	if node == null:
		_finish_with_outcome(DialogOutcomeData.make_end())
		return
	_current_node_id = node.id
	if _title_label:
		_title_label.text = _dialog.get_display_title()
	if _story_text:
		_story_text.text = node.get_display_text()
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
	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, CHOICE_MIN_HEIGHT)
	btn.add_theme_font_size_override("font_size", CHOICE_FONT_SIZE)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return btn


func _clear_choices() -> void:
	if _choices_box == null:
		return
	for child in _choices_box.get_children():
		child.queue_free()


func _on_choice_pressed(choice: DialogChoiceData) -> void:
	if choice == null or _is_closing or _choices_locked:
		return
	var outcome: DialogOutcomeData = choice.success_outcome
	if choice.has_stat_check() and _encounter_manager != null:
		var passed := _encounter_manager.resolve_stat_check(choice.stat_check, choice.check_dc)
		outcome = choice.success_outcome if passed else choice.failure_outcome
		if _result_label:
			_result_label.visible = true
			_result_label.text = (
				tr("KEY_STAT_CHECK_SUCCESS") if passed else tr("KEY_STAT_CHECK_FAILURE")
			)
	if outcome == null:
		outcome = DialogOutcomeData.make_end()

	## CONTINUE / mid-tree rewards stay inside the dialog — no exit fade.
	if _is_continuing_outcome(outcome):
		if _encounter_manager:
			_encounter_manager.apply_dialog_outcome(outcome)
		if not outcome.message_key.is_empty() and _result_label:
			_result_label.visible = true
			_result_label.text = tr(outcome.message_key)
		var next_id := outcome.next_node_id
		if next_id.is_empty() and outcome.kind == DialogOutcomeData.OutcomeKind.CONTINUE:
			_finish_with_outcome(outcome)
			return
		_show_node(next_id)
		return

	_finish_with_outcome(outcome)


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
		]
		and not outcome.next_node_id.is_empty()
	)


func _finish_with_outcome(outcome: DialogOutcomeData) -> void:
	if _is_closing:
		return
	_is_closing = true
	_choices_locked = true
	_set_choices_disabled(true)
	await _play_exit_fade()
	## Apply after fade so the next module (map / combat) can take over cleanly.
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
