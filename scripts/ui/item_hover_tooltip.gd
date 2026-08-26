class_name ItemHoverTooltip
extends PanelContainer
## Floating context tooltip for inventory items.
## Follows the cursor with viewport clamping; auto-sizes to content.
## Appearance is delayed slightly so quick mouse passes don't flash the tip.

const CURSOR_OFFSET := Vector2(14, 18)
const MAX_WIDTH := 320.0
const SHOW_DELAY_SEC := 0.35
const DEFAULT_NAME_COLOR := Color(0.92, 0.92, 0.92)
const META_COLOR := Color(0.62, 0.62, 0.66)
const DESC_COLOR := Color(0.78, 0.78, 0.8)
const TRAIT_ACTIVE_COLOR := Color(0.82, 0.85, 0.88)
const TRAIT_INACTIVE_COLOR := Color(0.45, 0.45, 0.48)

var _name_label: Label
var _ap_label: Label
var _meta_label: RichTextLabel
var _combat_label: RichTextLabel
var _desc_label: RichTextLabel
var _traits_box: VBoxContainer
var _item: ItemData
var _pending_item: ItemData
var _pending_title: String = ""
var _pending_body: String = ""
var _text_mode: bool = false
var _following: bool = false
var _show_timer: Timer
## Optional player stats so tooltips include STR/AGI/INT scaling.
var actor_stats: ActorStats
## Live body grid — used to resolve adjacency bonus notes for placed weapons.
var body_grid: BodyGrid

var _adjacency_label: RichTextLabel
var _hacked_banner: Label
## When valid, returns whether the player is under the Hacked debuff.
var is_hacked_fn: Callable


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	z_index = 100
	visible = false
	custom_minimum_size = Vector2(220, 0)
	_apply_panel_style()
	_build_layout()
	_show_timer = Timer.new()
	_show_timer.one_shot = true
	_show_timer.wait_time = SHOW_DELAY_SEC
	_show_timer.timeout.connect(_on_show_timer_timeout)
	add_child(_show_timer)
	set_process(false)


func _process(_delta: float) -> void:
	if not _following or not visible:
		return
	_reposition_to_mouse()


func request_show_for_item(item: ItemData) -> void:
	## Start (or restart) the hover delay. Call this on mouse enter.
	if item == null:
		hide_tooltip()
		return
	_pending_title = ""
	_pending_body = ""
	_pending_item = item
	if _show_timer:
		_show_timer.start(SHOW_DELAY_SEC)


func request_show_text(title: String, body: String) -> void:
	## Reuse the same hover panel for non-item content (e.g. player stats).
	if title.strip_edges().is_empty() and body.strip_edges().is_empty():
		hide_tooltip()
		return
	_pending_item = null
	_pending_title = title
	_pending_body = body
	if _show_timer:
		_show_timer.start(SHOW_DELAY_SEC)


func show_for_item(item: ItemData) -> void:
	## Immediate show (skips delay). Prefer request_show_for_item() for hover.
	_cancel_pending_show()
	if item == null:
		hide_tooltip()
		return
	_text_mode = false
	_item = item
	_populate(item)
	visible = true
	_following = true
	set_process(true)
	# Wait one frame so size is computed from content before clamping.
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	if not visible or _item != item:
		return
	_reposition_to_mouse()


func show_for_text(title: String, body: String) -> void:
	_cancel_pending_show()
	_item = null
	_text_mode = true
	_populate_text(title, body)
	visible = true
	_following = true
	set_process(true)
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	if not visible or not _text_mode:
		return
	_reposition_to_mouse()


func hide_tooltip() -> void:
	_cancel_pending_show()
	_item = null
	_text_mode = false
	_following = false
	set_process(false)
	visible = false


func _cancel_pending_show() -> void:
	_pending_item = null
	_pending_title = ""
	_pending_body = ""
	if _show_timer:
		_show_timer.stop()


func _on_show_timer_timeout() -> void:
	if not _pending_title.is_empty() or not _pending_body.is_empty():
		var title := _pending_title
		var body := _pending_body
		_pending_title = ""
		_pending_body = ""
		_pending_item = null
		show_for_text(title, body)
		return
	var item := _pending_item
	_pending_item = null
	if item == null:
		return
	show_for_item(item)


func is_showing_item(item: ItemData) -> bool:
	return visible and not _text_mode and _item == item


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _apply_panel_style() -> void:
	add_theme_stylebox_override(
		"panel",
		GamePalette.make_panel_stylebox(
			GamePalette.PANEL_BG, GamePalette.MUTED_GREEN, 1, 0, 10.0, false
		)
	)


func _build_layout() -> void:
	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	_name_label = Label.new()
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_name_label)

	_ap_label = Label.new()
	_ap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ap_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_ap_label.add_theme_font_size_override("font_size", 13)
	_ap_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	_ap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_ap_label)

	_meta_label = RichTextLabel.new()
	_meta_label.bbcode_enabled = true
	_meta_label.fit_content = true
	_meta_label.scroll_active = false
	_meta_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_meta_label.add_theme_font_size_override("normal_font_size", 11)
	_meta_label.add_theme_color_override("default_color", META_COLOR)
	_meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_meta_label)

	_combat_label = RichTextLabel.new()
	_combat_label.bbcode_enabled = true
	_combat_label.fit_content = true
	_combat_label.scroll_active = false
	_combat_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_combat_label.custom_minimum_size = Vector2(MAX_WIDTH - 24, 0)
	_combat_label.add_theme_font_size_override("normal_font_size", 12)
	_combat_label.add_theme_color_override("default_color", Color(0.88, 0.88, 0.9))
	_combat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combat_label.visible = false
	root.add_child(_combat_label)

	_adjacency_label = RichTextLabel.new()
	_adjacency_label.bbcode_enabled = true
	_adjacency_label.fit_content = true
	_adjacency_label.scroll_active = false
	_adjacency_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_adjacency_label.custom_minimum_size = Vector2(MAX_WIDTH - 24, 0)
	_adjacency_label.add_theme_font_size_override("normal_font_size", 11)
	_adjacency_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_adjacency_label.visible = false
	root.add_child(_adjacency_label)

	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sep)

	_desc_label = RichTextLabel.new()
	_desc_label.bbcode_enabled = true
	_desc_label.fit_content = true
	_desc_label.scroll_active = false
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(MAX_WIDTH - 24, 0)
	_desc_label.add_theme_color_override("default_color", DESC_COLOR)
	_desc_label.add_theme_font_size_override("normal_font_size", 12)
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_desc_label)

	_hacked_banner = Label.new()
	_hacked_banner.text = tr("KEY_HACKED_BANNER")
	_hacked_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hacked_banner.add_theme_font_size_override("font_size", 13)
	_hacked_banner.add_theme_color_override("font_color", GamePalette.COLOR_DANGER)
	_hacked_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hacked_banner.visible = false
	root.add_child(_hacked_banner)

	_traits_box = VBoxContainer.new()
	_traits_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_traits_box.add_theme_constant_override("separation", 4)
	root.add_child(_traits_box)


func _populate(item: ItemData) -> void:
	var hacked := _is_hacked()
	_name_label.text = TextGlitcher.glitchify(item.get_localized_name()) if hacked else item.get_localized_name()
	if item.rarity != null:
		_name_label.add_theme_color_override("font_color", item.get_rarity_color())
	else:
		_name_label.add_theme_color_override("font_color", DEFAULT_NAME_COLOR)

	if item.consumable or item.ap_cost > 0:
		_ap_label.visible = true
		if item.consumable:
			_ap_label.text = tr("KEY_USE_COST_FMT") % [item.ap_cost, tr("KEY_AP")]
		else:
			_ap_label.text = tr("KEY_AP_COST_FMT") % [item.ap_cost, tr("KEY_AP")]
	else:
		_ap_label.visible = false
		_ap_label.text = ""

	_meta_label.visible = true
	_meta_label.text = TextGlitcher.glitchify(_build_meta_line(item)) if hacked else _build_meta_line(item)
	_combat_label.text = TextGlitcher.glitchify(_build_combat_line(item)) if hacked else _build_combat_line(item)
	_combat_label.visible = not _combat_label.text.is_empty()
	_refresh_adjacency_notes(item)

	var desc := item.get_localized_description()
	if hacked and not desc.is_empty():
		desc = TextGlitcher.glitchify(desc)
	_desc_label.visible = not desc.is_empty()
	_desc_label.text = desc
	if _hacked_banner:
		_hacked_banner.visible = hacked

	_rebuild_traits(item, hacked)
	_force_autosize()


func _refresh_adjacency_notes(item: ItemData) -> void:
	if _adjacency_label == null:
		return
	var notes := ""
	if item != null and body_grid != null:
		notes = item.format_adjacency_bonus_notes(body_grid, true)
	_adjacency_label.text = notes
	_adjacency_label.visible = not notes.is_empty()


func _populate_text(title: String, body: String) -> void:
	_name_label.text = title if not title.is_empty() else tr("KEY_PLAYER_STATS")
	_name_label.add_theme_color_override("font_color", DEFAULT_NAME_COLOR)
	_ap_label.visible = false
	_ap_label.text = ""
	_meta_label.visible = false
	_meta_label.text = ""
	_combat_label.visible = false
	_combat_label.text = ""
	if _adjacency_label:
		_adjacency_label.visible = false
		_adjacency_label.text = ""
	_desc_label.visible = not body.is_empty()
	_desc_label.text = body
	for child in _traits_box.get_children():
		child.queue_free()
	_traits_box.visible = false
	_force_autosize()


func _build_meta_line(item: ItemData) -> String:
	var parts: PackedStringArray = []
	if item.rarity != null:
		var rarity_name := item.rarity.get_localized_name()
		var rarity_color := item.get_rarity_color()
		parts.append(
			"[color=#%s]%s[/color]" % [rarity_color.to_html(false), rarity_name]
		)
	if item.item_type != null:
		parts.append(item.item_type.get_localized_name())
	return " • ".join(parts)


func _build_combat_line(item: ItemData) -> String:
	var parts: PackedStringArray = []
	var dmg := item.format_damage_display(true, actor_stats)
	var armor := item.format_armor_display(true, actor_stats)
	if not dmg.is_empty():
		parts.append(dmg)
	if not armor.is_empty():
		parts.append(armor)
	if item.cooldown > 0:
		parts.append(tr("KEY_COOLDOWN_FMT") % item.cooldown)
	return "   ".join(parts)


func _rebuild_traits(item: ItemData, hacked: bool = false) -> void:
	for child in _traits_box.get_children():
		child.queue_free()

	if item.traits.is_empty():
		_traits_box.visible = false
		return

	_traits_box.visible = true
	for item_trait: TraitData in item.traits:
		if item_trait == null:
			continue
		_traits_box.add_child(_make_trait_row(item_trait, hacked))


func _make_trait_row(item_trait: TraitData, hacked: bool = false) -> RichTextLabel:
	var row := RichTextLabel.new()
	row.bbcode_enabled = true
	row.fit_content = true
	row.scroll_active = false
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.custom_minimum_size = Vector2(MAX_WIDTH - 24, 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_font_size_override("normal_font_size", 11)

	var trait_name := item_trait.get_localized_name()
	var trait_desc := item_trait.get_localized_description()
	var body := "• [b]%s[/b]" % trait_name
	if not trait_desc.is_empty():
		body += ": %s" % trait_desc
	if hacked:
		body = TextGlitcher.glitchify(body)

	if item_trait.is_active:
		row.add_theme_color_override("default_color", TRAIT_ACTIVE_COLOR)
		row.text = body
	else:
		row.add_theme_color_override("default_color", TRAIT_INACTIVE_COLOR)
		row.text = "[s]%s[/s]" % body

	return row


func _is_hacked() -> bool:
	return is_hacked_fn.is_valid() and bool(is_hacked_fn.call())


func _force_autosize() -> void:
	reset_size()
	custom_minimum_size = Vector2(mini(MAX_WIDTH, maxf(220.0, size.x)), 0)


# ---------------------------------------------------------------------------
# Positioning
# ---------------------------------------------------------------------------

func _reposition_to_mouse() -> void:
	var mouse := get_viewport().get_mouse_position()
	var vp := get_viewport().get_visible_rect().size
	var tip_size := size
	if tip_size.x < 1.0 or tip_size.y < 1.0:
		tip_size = get_combined_minimum_size()

	var pos := mouse + CURSOR_OFFSET

	# Flip left if overflowing right edge.
	if pos.x + tip_size.x > vp.x:
		pos.x = mouse.x - tip_size.x - CURSOR_OFFSET.x
	# Flip up if overflowing bottom edge.
	if pos.y + tip_size.y > vp.y:
		pos.y = mouse.y - tip_size.y - CURSOR_OFFSET.y

	pos.x = clampf(pos.x, 0.0, maxf(0.0, vp.x - tip_size.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, vp.y - tip_size.y))
	global_position = pos
