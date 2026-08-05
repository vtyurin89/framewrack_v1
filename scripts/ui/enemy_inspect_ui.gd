class_name EnemyInspectUI
extends BaseModalWindow
## Full inspect modal for runtime enemies (opened from EnemyContextMenuUI).
## Shows lore, stats, scaled ability ranges, and traits.

const PREVIEW_SIZE := Vector2(140, 160)

var _enemy: EnemyInstance
var _preview: TextureRect
var _preview_fallback: ColorRect
var _name_label: Label
var _stats_label: RichTextLabel
var _desc_label: RichTextLabel
var _abilities_box: VBoxContainer
var _traits_box: VBoxContainer
var _built: bool = false
var _filtered_texture_cache: Dictionary = {}


func _ready() -> void:
	super._ready()
	_ensure_content()
	if _dialog:
		_dialog.custom_minimum_size = Vector2(560, 380)
	if not LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.connect(_on_language_changed)


func open_enemy(enemy: EnemyInstance) -> void:
	if enemy == null:
		close()
		return
	_ensure_content()
	_enemy = enemy
	_populate(enemy)
	open()


func _on_language_changed(_locale: String) -> void:
	if _is_open and _enemy != null:
		_populate(_enemy)


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
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	preview_host.add_child(_preview)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)

	_name_label = Label.new()
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.add_theme_font_size_override("font_size", 22)
	right.add_child(_name_label)

	_stats_label = RichTextLabel.new()
	_stats_label.bbcode_enabled = true
	_stats_label.fit_content = true
	_stats_label.scroll_active = false
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_label.add_theme_font_size_override("normal_font_size", 15)
	_stats_label.add_theme_color_override("default_color", Color(0.88, 0.88, 0.9))
	_stats_label.custom_minimum_size = Vector2(320, 0)
	right.add_child(_stats_label)

	right.add_child(HSeparator.new())

	_desc_label = RichTextLabel.new()
	_desc_label.bbcode_enabled = true
	_desc_label.fit_content = true
	_desc_label.scroll_active = false
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.add_theme_font_size_override("normal_font_size", 14)
	_desc_label.add_theme_color_override("default_color", Color(0.72, 0.72, 0.76))
	_desc_label.custom_minimum_size = Vector2(320, 0)
	right.add_child(_desc_label)

	var abilities_title := Label.new()
	abilities_title.name = "AbilitiesTitle"
	abilities_title.text = tr("KEY_ABILITIES")
	abilities_title.add_theme_font_size_override("font_size", 15)
	abilities_title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	right.add_child(abilities_title)

	_abilities_box = VBoxContainer.new()
	_abilities_box.add_theme_constant_override("separation", 6)
	right.add_child(_abilities_box)

	var traits_title := Label.new()
	traits_title.name = "TraitsTitle"
	traits_title.text = tr("KEY_TRAITS")
	traits_title.add_theme_font_size_override("font_size", 15)
	traits_title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	right.add_child(traits_title)

	_traits_box = VBoxContainer.new()
	_traits_box.add_theme_constant_override("separation", 4)
	right.add_child(_traits_box)

	_built = true


func _populate(enemy: EnemyInstance) -> void:
	if enemy == null:
		return
	_name_label.text = enemy.get_localized_name()

	var color := Color(0.82, 0.82, 0.85)
	if enemy.data != null:
		color = enemy.data.placeholder_color
	_preview_fallback.color = color

	_preview.texture = null
	_preview.visible = false
	if enemy.data != null and not enemy.data.sprite_path.is_empty() and ResourceLoader.exists(enemy.data.sprite_path):
		var tex := _load_texture_with_mipmaps(enemy.data.sprite_path)
		if tex != null:
			_preview.texture = tex
			_preview.visible = true

	var crit_pct := enemy.get_crit_chance() * 100.0
	_stats_label.text = "%s %d/%d\n%s %d    %s %d    %s %d\n%s %d    %s %d    %s" % [
		tr("KEY_HP"),
		enemy.current_hp,
		enemy.max_hp,
		tr("KEY_STR"),
		enemy.strength,
		tr("KEY_AGI"),
		enemy.agility,
		tr("KEY_END"),
		enemy.endurance,
		tr("KEY_INT"),
		enemy.intelligence,
		tr("KEY_LCK"),
		enemy.luck,
		tr("KEY_CRIT_CHANCE_FMT") % crit_pct,
	]

	_desc_label.text = enemy.get_localized_description()

	for child in _abilities_box.get_children():
		child.queue_free()

	var title: Label = find_child("AbilitiesTitle", true, false) as Label
	if title:
		title.text = tr("KEY_ABILITIES")

	if enemy.abilities.is_empty():
		var empty := Label.new()
		empty.text = tr("KEY_NO_ABILITIES")
		empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
		_abilities_box.add_child(empty)
	else:
		for ability: EnemyAbility in enemy.abilities:
			if ability == null:
				continue
			var block := VBoxContainer.new()
			block.add_theme_constant_override("separation", 2)
			var name_l := Label.new()
			name_l.text = ability.get_localized_name()
			name_l.add_theme_font_size_override("font_size", 14)
			name_l.add_theme_color_override("font_color", Color(0.92, 0.92, 0.94))
			block.add_child(name_l)
			var range_l := Label.new()
			range_l.text = enemy.format_ability_tooltip(ability)
			range_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			range_l.add_theme_font_size_override("font_size", 13)
			range_l.add_theme_color_override("font_color", Color(0.78, 0.85, 0.7))
			block.add_child(range_l)
			var lore := ability.get_localized_description()
			if not lore.is_empty():
				var lore_l := Label.new()
				lore_l.text = lore
				lore_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				lore_l.add_theme_font_size_override("font_size", 12)
				lore_l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
				block.add_child(lore_l)
			_abilities_box.add_child(block)

	_populate_traits(enemy)


func _populate_traits(enemy: EnemyInstance) -> void:
	if _traits_box == null:
		return
	for child in _traits_box.get_children():
		child.queue_free()
	var traits_title: Label = find_child("TraitsTitle", true, false) as Label
	if traits_title:
		traits_title.text = tr("KEY_TRAITS")
	var trait_ids: Array[String] = enemy.get_trait_ids()
	if trait_ids.is_empty():
		var empty := Label.new()
		empty.text = tr("KEY_NO_TRAITS")
		empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
		_traits_box.add_child(empty)
		return
	for trait_id: String in trait_ids:
		var row := Label.new()
		row.text = "• %s" % trait_id
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_font_size_override("font_size", 13)
		row.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
		_traits_box.add_child(row)


func _load_texture_with_mipmaps(path: String) -> Texture2D:
	if _filtered_texture_cache.has(path):
		return _filtered_texture_cache[path] as Texture2D
	var loaded: Resource = load(path)
	if loaded == null or not (loaded is Texture2D):
		return null
	var tex := loaded as Texture2D
	var image := tex.get_image()
	if image == null:
		_filtered_texture_cache[path] = tex
		return tex
	if not image.has_mipmaps():
		image.generate_mipmaps()
	var filtered := ImageTexture.create_from_image(image)
	_filtered_texture_cache[path] = filtered
	return filtered
