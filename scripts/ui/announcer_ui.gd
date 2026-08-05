class_name AnnouncerUI
extends Control

@export_group("Default Announcement")
@export var default_bg_color: Color = Color("1A1D24B3")
@export var default_fade_in_time: float = 0.5
@export var default_display_time: float = 2.0
@export var default_fade_out_time: float = 0.8

@export_group("Chapter Announcement")
@export var chapter_bg_color: Color = Color("1A1D24B3")
@export var chapter_fade_in_time: float = 0.7
@export var chapter_display_time: float = 3.2
@export var chapter_fade_out_time: float = 1.5

@onready var _background_panel: Panel = %BackgroundPanel
@onready var _announcement_label: Label = %AnnouncementLabel

var _announce_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func announce(text: String, custom_bg_color: Color = Color.TRANSPARENT) -> void:
	_announce_with_settings(
		text,
		default_bg_color,
		default_fade_in_time,
		default_display_time,
		default_fade_out_time,
		custom_bg_color
	)


func announce_chapter(text: String, custom_bg_color: Color = Color.TRANSPARENT) -> void:
	_announce_with_settings(
		text,
		chapter_bg_color,
		chapter_fade_in_time,
		chapter_display_time,
		chapter_fade_out_time,
		custom_bg_color
	)


func _announce_with_settings(
	text: String,
	base_bg_color: Color,
	fade_in_time: float,
	display_time: float,
	fade_out_time: float,
	custom_bg_color: Color
) -> void:
	if _background_panel == null or _announcement_label == null:
		return
	var active_color := custom_bg_color if custom_bg_color != Color.TRANSPARENT else base_bg_color

	var style_box := StyleBoxFlat.new()
	style_box.bg_color = active_color
	style_box.set_corner_radius_all(4)
	style_box.set_content_margin_all(8)
	_background_panel.add_theme_stylebox_override("panel", style_box)

	_announcement_label.text = text

	if _announce_tween != null and _announce_tween.is_valid():
		_announce_tween.kill()
	modulate.a = 0.0
	show()

	_announce_tween = create_tween()
	_announce_tween.tween_property(self, "modulate:a", 1.0, fade_in_time)
	_announce_tween.tween_interval(display_time)
	_announce_tween.tween_property(self, "modulate:a", 0.0, fade_out_time)
	_announce_tween.tween_callback(hide)
