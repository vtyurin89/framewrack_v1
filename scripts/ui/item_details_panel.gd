class_name ItemDetailsPanel
extends PanelContainer
## Right-side inspector for a selected body-module.
## Shows localized name/description and combat stats.

signal closed

@onready var _title: Label = %TitleLabel
@onready var _rarity: Label = %RarityLabel
@onready var _type: Label = %TypeLabel
@onready var _desc: RichTextLabel = %DescLabel
@onready var _stats: Label = %StatsLabel
@onready var _price: Label = %PriceLabel
@onready var _traits: Label = %TraitsLabel
@onready var _close_btn: Button = %CloseButton

var _item: ItemData


func _ready() -> void:
	if _close_btn:
		_close_btn.pressed.connect(_on_close)
	visible = false
	_price.visible = false
	if not LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.connect(_on_language_changed)


func _on_language_changed(_locale: String) -> void:
	if _item != null:
		show_item(_item)


func show_item(item: ItemData) -> void:
	_item = item
	visible = item != null
	if item == null:
		_price.visible = false
		return

	_title.text = item.get_localized_name()
	_desc.text = item.get_localized_description()

	if item.rarity != null:
		_rarity.text = item.rarity.get_localized_name()
		_rarity.modulate = Color.WHITE
		_rarity.add_theme_color_override("font_color", item.get_rarity_color())
	else:
		_rarity.text = ""
		_rarity.modulate = Color.WHITE
		_rarity.remove_theme_color_override("font_color")

	if item.item_type != null:
		_type.text = item.item_type.get_localized_name()
	else:
		_type.text = ""

	_stats.text = _build_stats_line(item)
	_traits.text = _build_traits_line(item)


func clear() -> void:
	_item = null
	visible = false
	_price.visible = false
	_price.text = ""


func _build_stats_line(item: ItemData) -> String:
	var parts: PackedStringArray = []
	parts.append("%dx%d" % [item.size.x, item.size.y])
	if item.requires_edge:
		parts.append("EDGE")
	if item.consumable or item.ap_cost > 0:
		if item.consumable:
			parts.append(tr("KEY_USE_COST_FMT") % [item.ap_cost, tr("KEY_AP")])
		else:
			parts.append(tr("KEY_AP_COST_FMT") % [item.ap_cost, tr("KEY_AP")])
	var dmg := item.format_damage_display(false, null)
	if not dmg.is_empty():
		parts.append(dmg)
	var armor := item.format_armor_display(false, null)
	if not armor.is_empty():
		parts.append(armor)
	if item.consumable and item.max_charges > 0:
		parts.append("%d charges" % item.max_charges)
	if item.cooldown > 0:
		parts.append(tr("KEY_COOLDOWN_FMT") % item.cooldown)
	return " · ".join(parts)


func _build_traits_line(item: ItemData) -> String:
	if item.traits.is_empty():
		return ""
	var names: PackedStringArray = []
	for item_trait: TraitData in item.traits:
		if item_trait == null:
			continue
		names.append(item_trait.get_localized_name())
	if names.is_empty():
		return ""
	return "Traits: " + ", ".join(names)


func _on_close() -> void:
	clear()
	closed.emit()
