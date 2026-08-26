class_name DebugActModal
extends BaseModalWindow
## Debug: jump to the start of any act (aborts current event).

signal act_selected(act_index: int)

var _list: VBoxContainer
var _title: Label


func _ready() -> void:
	super._ready()
	_build_layout()
	if not LocalizationManager.language_changed.is_connected(_on_locale_changed):
		LocalizationManager.language_changed.connect(_on_locale_changed)


func open_picker() -> void:
	_rebuild_buttons()
	_apply_locale()
	open()


func _on_locale_changed(_locale: String = "") -> void:
	_apply_locale()
	if _is_open:
		_rebuild_buttons()


func _apply_locale() -> void:
	if _title:
		_title.text = tr("KEY_DEBUG_ACT_TITLE")


func _build_layout() -> void:
	if content_container == null:
		content_container = %ContentContainer
	clear_content()
	if _dialog:
		_dialog.custom_minimum_size = Vector2(400, 280)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	GamePalette.apply_label_primary(_title)
	content_container.add_child(_title)

	_list = VBoxContainer.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	content_container.add_child(_list)


func _rebuild_buttons() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	if ActDatabase == null:
		return
	for act: ActData in ActDatabase.get_all_acts():
		if act == null:
			continue
		var btn := Button.new()
		btn.text = act.get_localized_title()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 44)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		GamePalette.apply_button_theme(btn, 14)
		btn.pressed.connect(_on_act_pressed.bind(act.act_index))
		_list.add_child(btn)


func _on_act_pressed(act_index: int) -> void:
	act_selected.emit(act_index)
	close()
