class_name ItemInspectModal
extends BaseModalWindow
## Full inspect dialog for a body-module: large icon preview + detailed stats.

const PREVIEW_SIZE := Vector2(180, 180)
const DEFAULT_NAME_COLOR := Color(0.92, 0.92, 0.92)

var _item: ItemData
var _preview: TextureRect
var _preview_fallback: ColorRect
var _name_label: Label
var _ap_label: Label
var _meta_label: RichTextLabel
var _combat_label: RichTextLabel
var _desc_label: RichTextLabel
var _traits_box: VBoxContainer
var _built: bool = false
## Optional player stats so inspect shows scaled damage/block.
var actor_stats: ActorStats
## Live body grid for adjacency bonus notes on placed weapons.
var body_grid: BodyGrid

var _adjacency_label: RichTextLabel
var _hacked_banner: Label
var is_hacked_fn: Callable


func _ready() -> void:
	super._ready()
	_ensure_content()
	if not LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.connect(_on_language_changed)


func open_item(item: ItemData) -> void:
	if item == null:
		close()
		return
	_ensure_content()
	_item = item
	_populate(item)
	open()


func _on_language_changed(_locale: String) -> void:
	if _is_open and _item != null:
		_populate(_item)


func _ensure_content() -> void:
	if _built:
		return
	if content_container == null:
		content_container = %ContentContainer
	clear_content()

	var root := HBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 18)
	content_container.add_child(root)

	## Left: large texture preview
	var left := VBoxContainer.new()
	left.custom_minimum_size = PREVIEW_SIZE
	root.add_child(left)

	var preview_host := Control.new()
	preview_host.custom_minimum_size = PREVIEW_SIZE
	preview_host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(preview_host)

	_preview_fallback = ColorRect.new()
	_preview_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_fallback.color = Color(0.25, 0.25, 0.28)
	preview_host.add_child(_preview_fallback)

	_preview = TextureRect.new()
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_host.add_child(_preview)

	## Right: detailed stats
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	right.add_child(header)

	_name_label = Label.new()
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.add_theme_font_size_override("font_size", 22)
	header.add_child(_name_label)

	_ap_label = Label.new()
	_ap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ap_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_ap_label.add_theme_font_size_override("font_size", 16)
	_ap_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	header.add_child(_ap_label)

	_meta_label = RichTextLabel.new()
	_meta_label.bbcode_enabled = true
	_meta_label.fit_content = true
	_meta_label.scroll_active = false
	_meta_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_meta_label.add_theme_font_size_override("normal_font_size", 13)
	_meta_label.add_theme_color_override("default_color", Color(0.65, 0.65, 0.7))
	right.add_child(_meta_label)

	_combat_label = RichTextLabel.new()
	_combat_label.bbcode_enabled = true
	_combat_label.fit_content = true
	_combat_label.scroll_active = false
	_combat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_combat_label.add_theme_font_size_override("normal_font_size", 16)
	_combat_label.add_theme_color_override("default_color", Color(0.9, 0.9, 0.92))
	_combat_label.custom_minimum_size = Vector2(320, 0)
	_combat_label.visible = false
	right.add_child(_combat_label)

	_adjacency_label = RichTextLabel.new()
	_adjacency_label.bbcode_enabled = true
	_adjacency_label.fit_content = true
	_adjacency_label.scroll_active = false
	_adjacency_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_adjacency_label.add_theme_font_size_override("normal_font_size", 13)
	_adjacency_label.custom_minimum_size = Vector2(320, 0)
	_adjacency_label.visible = false
	right.add_child(_adjacency_label)

	var sep := HSeparator.new()
	right.add_child(sep)

	_desc_label = RichTextLabel.new()
	_desc_label.bbcode_enabled = true
	_desc_label.fit_content = true
	_desc_label.scroll_active = false
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.add_theme_font_size_override("normal_font_size", 14)
	_desc_label.add_theme_color_override("default_color", Color(0.8, 0.8, 0.82))
	_desc_label.custom_minimum_size = Vector2(320, 0)
	right.add_child(_desc_label)

	_hacked_banner = Label.new()
	_hacked_banner.text = tr("KEY_HACKED_BANNER")
	_hacked_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hacked_banner.add_theme_font_size_override("font_size", 15)
	_hacked_banner.add_theme_color_override("font_color", GamePalette.COLOR_DANGER)
	_hacked_banner.visible = false
	right.add_child(_hacked_banner)

	_traits_box = VBoxContainer.new()
	_traits_box.add_theme_constant_override("separation", 6)
	right.add_child(_traits_box)

	_built = true


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

	var meta_parts: PackedStringArray = []
	if item.rarity != null:
		var rarity_hex := item.get_rarity_color().to_html(false)
		meta_parts.append(
			"[color=#%s]%s[/color]" % [rarity_hex, item.rarity.get_localized_name()]
		)
	if item.item_type != null:
		meta_parts.append(item.item_type.get_localized_name())
	_meta_label.text = TextGlitcher.glitchify(" • ".join(meta_parts)) if hacked else " • ".join(meta_parts)

	var combat_parts: PackedStringArray = []
	var dmg_line := item.format_damage_display(true, actor_stats)
	var armor_line := item.format_armor_display(true, actor_stats)
	if not dmg_line.is_empty():
		combat_parts.append(dmg_line)
	if not armor_line.is_empty():
		combat_parts.append(armor_line)
	var combat_text := "\n".join(combat_parts)
	_combat_label.text = TextGlitcher.glitchify(combat_text) if hacked and not combat_text.is_empty() else combat_text
	_combat_label.visible = not _combat_label.text.is_empty()

	var adj_notes := ""
	if body_grid != null:
		adj_notes = item.format_adjacency_bonus_notes(body_grid, true)
	if _adjacency_label:
		_adjacency_label.text = adj_notes
		_adjacency_label.visible = not adj_notes.is_empty()

	var desc := item.get_localized_description()
	if hacked and not desc.is_empty():
		desc = TextGlitcher.glitchify(desc)
	_desc_label.visible = not desc.is_empty()
	_desc_label.text = desc
	if _hacked_banner:
		_hacked_banner.visible = hacked

	var tex := item.get_texture()
	if tex != null:
		_preview.texture = tex
		_preview.visible = true
		_preview_fallback.color = Color(0.18, 0.18, 0.2)
	else:
		_preview.texture = null
		_preview.visible = false
		_preview_fallback.color = item.placeholder_color

	_rebuild_traits(item, hacked)


func _is_hacked() -> bool:
	return is_hacked_fn.is_valid() and bool(is_hacked_fn.call())


func _rebuild_traits(item: ItemData, hacked: bool = false) -> void:
	for child in _traits_box.get_children():
		child.queue_free()

	for item_trait: TraitData in item.traits:
		if item_trait == null:
			continue
		_traits_box.add_child(_make_trait_block(item_trait, hacked))


func _make_trait_block(item_trait: TraitData, hacked: bool = false) -> RichTextLabel:
	var row := RichTextLabel.new()
	row.bbcode_enabled = true
	row.fit_content = true
	row.scroll_active = false
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.custom_minimum_size = Vector2(320, 0)
	row.add_theme_font_size_override("normal_font_size", 13)

	var trait_name := item_trait.get_localized_name()
	var trait_desc := item_trait.get_localized_description()
	var status := tr("KEY_TRAIT_ACTIVE") if item_trait.is_active else tr("KEY_TRAIT_INACTIVE")
	var body := "• [b]%s[/b]  ([i]%s[/i])" % [trait_name, status]
	if not trait_desc.is_empty():
		body += "\n%s" % trait_desc
	if hacked:
		body = TextGlitcher.glitchify(body)

	if item_trait.is_active:
		row.add_theme_color_override("default_color", Color(0.85, 0.88, 0.9))
		row.text = body
	else:
		row.add_theme_color_override("default_color", Color(0.48, 0.48, 0.5))
		row.text = "[s]%s[/s]" % body

	return row
