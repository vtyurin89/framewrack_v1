class_name DebugStatusModal
extends BaseModalWindow
## Debug: apply any player-applicable status (2 stacks / duration) to the player.

signal status_applied

const ENEMY_ONLY_IDS := {
	"summoned_creature": true,
	"fleeing": true,
	"frenzy": true,
	"war_god_corruption": true,
}

var _combat: Node
var _list: VBoxContainer
var _title: Label


func _ready() -> void:
	super._ready()
	_build_layout()
	if not LocalizationManager.language_changed.is_connected(_on_locale_changed):
		LocalizationManager.language_changed.connect(_on_locale_changed)


func open_for_combat(combat: Node) -> void:
	_combat = combat
	_rebuild_buttons()
	_apply_locale()
	open()


func _on_locale_changed(_locale: String = "") -> void:
	_apply_locale()
	if _is_open:
		_rebuild_buttons()


func _apply_locale() -> void:
	if _title:
		_title.text = tr("KEY_DEBUG_STATUS_TITLE")


func _build_layout() -> void:
	if content_container == null:
		content_container = %ContentContainer
	clear_content()
	if _dialog:
		_dialog.custom_minimum_size = Vector2(420, 480)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	GamePalette.apply_label_primary(_title)
	content_container.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(380, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_container.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)


func _rebuild_buttons() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	if StatusEffectDatabase == null:
		return
	var statuses: Array[StatusEffectData] = StatusEffectDatabase.get_all()
	statuses.sort_custom(func(a: StatusEffectData, b: StatusEffectData) -> bool:
		return a.get_display_title().to_lower() < b.get_display_title().to_lower()
	)
	for data: StatusEffectData in statuses:
		if data == null or data.id.is_empty():
			continue
		var sid := data.id.strip_edges().to_lower()
		if ENEMY_ONLY_IDS.has(sid):
			continue
		var btn := Button.new()
		btn.text = data.get_display_title()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 36)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		GamePalette.apply_button_theme(btn, 13)
		btn.pressed.connect(_on_status_pressed.bind(sid))
		_list.add_child(btn)


func _on_status_pressed(status_id: String) -> void:
	if _combat == null or not _combat.has_method("apply_player_status"):
		return
	_combat.call("apply_player_status", status_id, 2)
	status_applied.emit()
