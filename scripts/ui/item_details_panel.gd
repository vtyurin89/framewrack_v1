class_name ItemDetailsPanel
extends PanelContainer
## Right-side inspector for a selected body-module.
## Shows localized name/description, combat stats, and merchant price when sellable.

signal closed

const PRICE_SUFFIX := " Scrap"

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
		_rarity.modulate = item.rarity.tint
	else:
		_rarity.text = ""
		_rarity.modulate = Color.WHITE

	if item.item_type != null:
		_type.text = item.item_type.get_localized_name()
	else:
		_type.text = ""

	_stats.text = _build_stats_line(item)
	_traits.text = _build_traits_line(item)
	_update_price_line(item)


func clear() -> void:
	_item = null
	visible = false
	_price.visible = false
	_price.text = ""


func _update_price_line(item: ItemData) -> void:
	## Only render a price row for merchant-sellable items.
	if item != null and item.is_sellable():
		_price.visible = true
		_price.text = "Price: %s%s" % [str(int(item.price)), PRICE_SUFFIX]
	else:
		# price == null (or non-positive): hide the line entirely — no "Not for Sale".
		_price.visible = false
		_price.text = ""


func _build_stats_line(item: ItemData) -> String:
	var parts: PackedStringArray = []
	parts.append("%dx%d" % [item.size.x, item.size.y])
	if item.requires_edge:
		parts.append("EDGE")
	if item.ap_cost > 0:
		parts.append("%d AP" % item.ap_cost)
	var dmg := item.format_damage_display(false)
	if not dmg.is_empty():
		parts.append(dmg)
	var armor := item.format_armor_display(false)
	if not armor.is_empty():
		parts.append(armor)
	if item.consumable and item.max_charges > 0:
		parts.append("%d charges" % item.max_charges)
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
