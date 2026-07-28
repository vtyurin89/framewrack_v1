class_name SettingsModal
extends BaseModalWindow
## Settings dialog: language selection (EN / RU).

@onready var _title_label: Label = %TitleLabel
@onready var _lang_label: Label = %LanguageLabel
@onready var _lang_option: OptionButton = %LanguageOption
@onready var _apply_btn: Button = %ApplyButton
@onready var _hide_debug_check: CheckButton = %HideDebugCheck


func _ready() -> void:
	super._ready()
	if _lang_option:
		_lang_option.item_selected.connect(_on_language_selected)
	if _apply_btn:
		_apply_btn.pressed.connect(close)
		_apply_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if _hide_debug_check:
		_hide_debug_check.toggled.connect(_on_hide_debug_toggled)
	if not LocalizationManager.language_changed.is_connected(_on_locale_changed):
		LocalizationManager.language_changed.connect(_on_locale_changed)


func open_settings() -> void:
	_refresh_language_options()
	_apply_locale_labels()
	_sync_debug_toggle()
	open()


func _on_locale_changed(_locale: String) -> void:
	_apply_locale_labels()
	if is_open():
		_refresh_language_options()


func _apply_locale_labels() -> void:
	if _title_label:
		_title_label.text = tr("KEY_SETTINGS")
	if _lang_label:
		_lang_label.text = tr("KEY_LANGUAGE")
	if _apply_btn:
		_apply_btn.text = tr("KEY_CLOSE")
	if _hide_debug_check:
		_hide_debug_check.text = tr("KEY_HIDE_DEBUG_TOOLS")


func _refresh_language_options() -> void:
	if _lang_option == null:
		return
	var was_connected := _lang_option.item_selected.is_connected(_on_language_selected)
	if was_connected:
		_lang_option.item_selected.disconnect(_on_language_selected)
	_lang_option.clear()
	var locales: PackedStringArray = LocalizationManager.get_supported_locales()
	var current := LocalizationManager.get_locale()
	var selected_idx := 0
	for i in locales.size():
		var code: String = locales[i]
		var label := "English" if code == "en" else "Русский"
		_lang_option.add_item("%s (%s)" % [label, code.to_upper()], i)
		_lang_option.set_item_metadata(i, code)
		if current.begins_with(code):
			selected_idx = i
	_lang_option.select(selected_idx)
	if was_connected:
		_lang_option.item_selected.connect(_on_language_selected)


func _on_language_selected(index: int) -> void:
	var code: Variant = _lang_option.get_item_metadata(index)
	if code == null:
		return
	var locale := str(code)
	if LocalizationManager.get_locale().begins_with(locale):
		return
	LocalizationManager.set_language(locale)


func _sync_debug_toggle() -> void:
	if _hide_debug_check == null:
		return
	var was_connected := _hide_debug_check.toggled.is_connected(_on_hide_debug_toggled)
	if was_connected:
		_hide_debug_check.toggled.disconnect(_on_hide_debug_toggled)
	_hide_debug_check.button_pressed = GameSettings.hide_debug_tools
	if was_connected:
		_hide_debug_check.toggled.connect(_on_hide_debug_toggled)


func _on_hide_debug_toggled(button_pressed: bool) -> void:
	GameSettings.toggle_debug_tools(button_pressed)
