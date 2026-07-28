class_name DialogEventUI
extends Control
## Modal UI for DialogEventData trees (choices + optional stat checks).

signal choice_resolved(outcome: DialogOutcomeData)
signal closed_without_outcome

const BASE_MODAL_SCENE := preload("res://scenes/UI/base_modal_window.tscn")

var _modal: BaseModalWindow
var _title_label: Label
var _body_label: Label
var _result_label: Label
var _choices_box: VBoxContainer
var _dialog: DialogEventData
var _encounter_manager: EncounterManager
var _current_node_id: String = ""


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func bind_encounter_manager(manager: EncounterManager) -> void:
	_encounter_manager = manager


func open_dialog(dialog: DialogEventData) -> void:
	if dialog == null:
		return
	_dialog = dialog
	_current_node_id = dialog.start_node_id
	_show_node(_current_node_id)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _modal:
		## Disable X/ESC closing mid-event — choices must resolve.
		if _modal.has_node("%CloseButton"):
			(_modal.get_node("%CloseButton") as CanvasItem).visible = false
		_modal.open()


func close_dialog() -> void:
	if _modal and _modal.is_open():
		_modal.close()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog = null


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal = BASE_MODAL_SCENE.instantiate() as BaseModalWindow
	add_child(_modal)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_title_label)

	_body_label = Label.new()
	_body_label.add_theme_font_size_override("font_size", 15)
	_body_label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.82))
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(480, 0)
	root.add_child(_body_label)

	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 13)
	_result_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.visible = false
	root.add_child(_result_label)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 8)
	root.add_child(_choices_box)

	_modal.set_content(root)
	_modal.closed.connect(_on_modal_closed)


func _show_node(node_id: String) -> void:
	if _dialog == null:
		return
	var node := _dialog.get_node(node_id)
	if node == null:
		choice_resolved.emit(DialogOutcomeData.make_end())
		close_dialog()
		return
	_current_node_id = node.id
	_title_label.text = _dialog.get_display_title()
	_body_label.text = node.get_display_text()
	_result_label.visible = false
	_result_label.text = ""
	_rebuild_choices(node)


func _rebuild_choices(node: DialogNodeData) -> void:
	for child in _choices_box.get_children():
		child.queue_free()
	if node.choices.is_empty():
		var done := Button.new()
		done.text = tr("KEY_CONTINUE")
		done.pressed.connect(func() -> void:
			var outcome := DialogOutcomeData.make_end()
			_emit_and_close(outcome)
		)
		_choices_box.add_child(done)
		return
	for choice: DialogChoiceData in node.choices:
		if choice == null:
			continue
		var btn := Button.new()
		btn.text = choice.get_display_text()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 36)
		var captured := choice
		btn.pressed.connect(func() -> void: _on_choice_pressed(captured))
		_choices_box.add_child(btn)


func _on_choice_pressed(choice: DialogChoiceData) -> void:
	if choice == null:
		return
	var outcome: DialogOutcomeData = choice.success_outcome
	if choice.has_stat_check() and _encounter_manager != null:
		var passed := _encounter_manager.resolve_stat_check(choice.stat_check, choice.check_dc)
		outcome = choice.success_outcome if passed else choice.failure_outcome
		_result_label.visible = true
		_result_label.text = (
			tr("KEY_STAT_CHECK_SUCCESS") if passed else tr("KEY_STAT_CHECK_FAILURE")
		)
	if outcome == null:
		outcome = DialogOutcomeData.make_end()

	## CONTINUE with next_node_id stays in the dialog.
	if (
		outcome.kind == DialogOutcomeData.OutcomeKind.CONTINUE
		or (
			outcome.kind in [
				DialogOutcomeData.OutcomeKind.HEAL,
				DialogOutcomeData.OutcomeKind.DAMAGE,
				DialogOutcomeData.OutcomeKind.GRANT_ITEM,
			]
			and not outcome.next_node_id.is_empty()
		)
	):
		if _encounter_manager:
			_encounter_manager.apply_dialog_outcome(outcome)
		if not outcome.message_key.is_empty():
			_result_label.visible = true
			_result_label.text = tr(outcome.message_key)
		var next_id := outcome.next_node_id
		if next_id.is_empty() and outcome.kind == DialogOutcomeData.OutcomeKind.CONTINUE:
			close_dialog()
			choice_resolved.emit(outcome)
			return
		_show_node(next_id)
		return

	_emit_and_close(outcome)


func _emit_and_close(outcome: DialogOutcomeData) -> void:
	if _encounter_manager:
		_encounter_manager.apply_dialog_outcome(outcome)
	choice_resolved.emit(outcome)
	close_dialog()


func _on_modal_closed() -> void:
	## ESC / overlay close while dialog still active → treat as walking away.
	if _dialog != null:
		var outcome := DialogOutcomeData.make_end()
		if _encounter_manager and _encounter_manager.has_active_encounter():
			_encounter_manager.apply_dialog_outcome(outcome)
		choice_resolved.emit(outcome)
		_dialog = null
