class_name SettingsModal
extends BaseModalWindow
## Settings dialog with draft confirmation:
## - "Save and exit" commits draft values to live settings.
## - Top-right "✕" / Esc / overlay click discard drafts.

const COLOR_CHECK_ON := Color(0.698, 0.231, 0.231, 1.0)       # #B23B3B
const COLOR_CHECK_OFF := Color(0.365, 0.365, 0.353, 1.0)      # ~#5D5D5A
const COLOR_CHECK_HOVER := Color(0.804, 0.380, 0.333, 1.0)    # #CD6155
const COLOR_CHECK_HOVER_ON := Color(0.663, 0.196, 0.149, 1.0) # #A93226

@onready var _title_label: Label = %TitleLabel
@onready var _lang_label: Label = %LanguageLabel
@onready var _lang_option: OptionButton = %LanguageOption
@onready var _difficulty_label: Label = %DifficultyLabel
@onready var _difficulty_option: OptionButton = %DifficultyOption
@onready var _apply_btn: Button = %ApplyButton
@onready var _hide_debug_check: CheckButton = %HideDebugCheck

var _draft_language: String = "en"
var _draft_hide_debug: bool = false
var _draft_difficulty: int = 1


func _ready() -> void:
	super._ready()
	_rewire_close_to_cancel()
	if _lang_option:
		_lang_option.item_selected.connect(_on_language_selected)
	if _difficulty_option:
		_difficulty_option.item_selected.connect(_on_difficulty_selected)
	if _apply_btn:
		_apply_btn.pressed.connect(_on_save_and_exit_pressed)
		_apply_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if _hide_debug_check:
		_hide_debug_check.toggled.connect(_on_hide_debug_toggled)
		_style_debug_check_button()
	if not LocalizationManager.language_changed.is_connected(_on_locale_changed):
		LocalizationManager.language_changed.connect(_on_locale_changed)


func open_settings() -> void:
	_capture_draft_from_live()
	_apply_locale_labels()
	_populate_ui_from_draft()
	open()


func _rewire_close_to_cancel() -> void:
	## Base modal wires ✕ / Esc / overlay to close(); Settings must cancel drafts instead.
	if _close_btn and _close_btn.pressed.is_connected(close):
		_close_btn.pressed.disconnect(close)
	if _close_btn and not _close_btn.pressed.is_connected(_on_close_button_pressed):
		_close_btn.pressed.connect(_on_close_button_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_close_button_pressed()
		get_viewport().set_input_as_handled()


func _on_overlay_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_close_button_pressed()


func _capture_draft_from_live() -> void:
	_draft_language = LocalizationManager.get_locale()
	if _draft_language.is_empty():
		_draft_language = "en"
	_draft_hide_debug = GameSettings.hide_debug_tools
	_draft_difficulty = int(GameSettings.difficulty)


func _populate_ui_from_draft() -> void:
	_refresh_language_options()
	_refresh_difficulty_options()
	_sync_debug_toggle_from_draft()


func _on_locale_changed(_locale: String) -> void:
	_apply_locale_labels()
	## Keep draft selection visible while editing; only rebuild labels.
	if is_open():
		_refresh_language_options()
		_refresh_difficulty_options()


func _apply_locale_labels() -> void:
	if _title_label:
		_title_label.text = tr("KEY_SETTINGS")
	if _lang_label:
		_lang_label.text = tr("KEY_LANGUAGE")
	if _difficulty_label:
		_difficulty_label.text = tr("KEY_DIFFICULTY")
	if _apply_btn:
		_apply_btn.text = tr("KEY_SAVE_AND_EXIT")
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
	var selected_idx := 0
	for i in locales.size():
		var code: String = locales[i]
		var label := "English" if code == "en" else "Русский"
		_lang_option.add_item("%s (%s)" % [label, code.to_upper()], i)
		_lang_option.set_item_metadata(i, code)
		if _draft_language.begins_with(code):
			selected_idx = i
	_lang_option.select(selected_idx)
	if was_connected:
		_lang_option.item_selected.connect(_on_language_selected)


func _refresh_difficulty_options() -> void:
	if _difficulty_option == null:
		return
	var was_connected := _difficulty_option.item_selected.is_connected(_on_difficulty_selected)
	if was_connected:
		_difficulty_option.item_selected.disconnect(_on_difficulty_selected)
	_difficulty_option.clear()
	var levels: Array[int] = [
		GameSettings.Difficulty.EASY,
		GameSettings.Difficulty.NORMAL,
		GameSettings.Difficulty.HARD,
	]
	var selected_idx := 1
	for i in levels.size():
		var level: int = levels[i]
		_difficulty_option.add_item(tr(GameSettings.difficulty_label_key(level)), i)
		_difficulty_option.set_item_metadata(i, level)
		if level == _draft_difficulty:
			selected_idx = i
	_difficulty_option.select(selected_idx)
	if was_connected:
		_difficulty_option.item_selected.connect(_on_difficulty_selected)


func _on_language_selected(index: int) -> void:
	var code: Variant = _lang_option.get_item_metadata(index)
	if code == null:
		return
	_draft_language = str(code)


func _on_difficulty_selected(index: int) -> void:
	var level: Variant = _difficulty_option.get_item_metadata(index)
	if level == null:
		return
	_draft_difficulty = int(level)


func _sync_debug_toggle_from_draft() -> void:
	if _hide_debug_check == null:
		return
	var was_connected := _hide_debug_check.toggled.is_connected(_on_hide_debug_toggled)
	if was_connected:
		_hide_debug_check.toggled.disconnect(_on_hide_debug_toggled)
	_hide_debug_check.button_pressed = _draft_hide_debug
	if was_connected:
		_hide_debug_check.toggled.connect(_on_hide_debug_toggled)


func _on_hide_debug_toggled(button_pressed: bool) -> void:
	_draft_hide_debug = button_pressed


func _on_save_and_exit_pressed() -> void:
	if not LocalizationManager.get_locale().begins_with(_draft_language):
		LocalizationManager.set_language(_draft_language)
	GameSettings.toggle_debug_tools(_draft_hide_debug)
	GameSettings.set_difficulty(_draft_difficulty as GameSettings.Difficulty)
	close()


func _on_close_button_pressed() -> void:
	## Discard drafts and restore UI to live settings without applying.
	_capture_draft_from_live()
	_populate_ui_from_draft()
	close()


func _style_debug_check_button() -> void:
	if _hide_debug_check == null:
		return
	_hide_debug_check.add_theme_stylebox_override("normal", _make_check_style(COLOR_CHECK_OFF))
	_hide_debug_check.add_theme_stylebox_override("pressed", _make_check_style(COLOR_CHECK_ON))
	_hide_debug_check.add_theme_stylebox_override("hover", _make_check_style(COLOR_CHECK_HOVER))
	_hide_debug_check.add_theme_stylebox_override("hover_pressed", _make_check_style(COLOR_CHECK_HOVER_ON))
	_hide_debug_check.add_theme_stylebox_override("focus", _make_check_style(COLOR_CHECK_OFF))
	_hide_debug_check.add_theme_color_override("font_color", Color(0.88, 0.88, 0.9))
	_hide_debug_check.add_theme_color_override("font_pressed_color", Color(0.95, 0.9, 0.9))
	_hide_debug_check.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.93))
	_hide_debug_check.add_theme_color_override("font_hover_pressed_color", Color(1.0, 0.93, 0.9))


func _make_check_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_border_width_all(1)
	style.border_color = Color(bg.r * 0.65, bg.g * 0.65, bg.b * 0.65, 1.0)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style
