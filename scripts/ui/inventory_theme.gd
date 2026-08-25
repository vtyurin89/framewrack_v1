class_name InventoryTheme
extends RefCounted
## CRT monochrome inventory tile palette.
## Category / rarity encoded as border luminance, not hue.

enum PaletteKind {
	WEAPON,
	ARMOR,
	CONSUMABLE,
	JUNK,
	RARE,
	VERY_RARE,
	HARMFUL,
}

## Empty unlocked body-grid cells (blueprint / X-ray).
const CELL_BG := Color("#111C16") ## PANEL_BG_ALT
const CELL_BORDER := Color("#285A3A") ## MUTED_GREEN

const _PALETTES := {
	PaletteKind.WEAPON: {
		"bg": Color("#0D1511CC"),
		"border": Color("#4FAF68"),
		"text": Color("#79D88A"),
	},
	PaletteKind.ARMOR: {
		"bg": Color("#0D1511CC"),
		"border": Color("#285A3A"),
		"text": Color("#4FAF68"),
	},
	PaletteKind.CONSUMABLE: {
		"bg": Color("#0D1511CC"),
		"border": Color("#5FAF91"),
		"text": Color("#A8F0A8"),
	},
	PaletteKind.JUNK: {
		"bg": Color("#0D1511B3"),
		"border": Color("#173323"),
		"text": Color("#285A3A"),
	},
	PaletteKind.RARE: {
		"bg": Color("#111C16CC"),
		"border": Color("#B6B35A"),
		"text": Color("#B6B35A"),
	},
	PaletteKind.VERY_RARE: {
		"bg": Color("#111C16CC"),
		"border": Color("#A8F0A8"),
		"text": Color("#A8F0A8"),
	},
	PaletteKind.HARMFUL: {
		"bg": Color("#1A0E0ECC"),
		"border": Color("#A84D4D"),
		"text": Color("#A84D4D"),
	},
}


static func palette_kind_for_item(item: ItemData) -> PaletteKind:
	if item == null:
		return PaletteKind.JUNK
	if item.is_harmful:
		return PaletteKind.HARMFUL
	if item.rarity != null:
		match item.rarity.get_tier():
			ItemRarityData.Tier.VERY_RARE:
				return PaletteKind.VERY_RARE
			ItemRarityData.Tier.RARE:
				return PaletteKind.RARE
	var type_id := ""
	if item.item_type != null:
		type_id = item.item_type.id.strip_edges().to_upper()
	match type_id:
		"WEAPON":
			return PaletteKind.WEAPON
		"ARMOR", "SHIELD":
			return PaletteKind.ARMOR
		"CONSUMABLE":
			return PaletteKind.CONSUMABLE
		"JUNK", "PARTS", "REACTOR", "CURRENCY", "IMPLANT", "AMPLIFIER", "ACTIVE_MODULE":
			return PaletteKind.JUNK
		_:
			return PaletteKind.JUNK


static func colors_for_kind(kind: PaletteKind) -> Dictionary:
	if _PALETTES.has(kind):
		return _PALETTES[kind]
	return _PALETTES[PaletteKind.JUNK]


static func colors_for_item(item: ItemData) -> Dictionary:
	var colors: Dictionary = colors_for_kind(palette_kind_for_item(item)).duplicate()
	## Rare+ keeps CRT warning / bright border (no rainbow rarity hues).
	if item != null and item.rarity != null:
		var tier := item.rarity.get_tier()
		if tier == ItemRarityData.Tier.RARE:
			colors["border"] = Color("#B6B35A")
			colors["text"] = Color("#B6B35A")
		elif tier == ItemRarityData.Tier.VERY_RARE:
			colors["border"] = Color("#A8F0A8")
			colors["text"] = Color("#A8F0A8")
	return colors


static func make_item_stylebox(item: ItemData, border_width: int = 1) -> StyleBoxFlat:
	var colors: Dictionary = colors_for_item(item)
	var style := StyleBoxFlat.new()
	style.bg_color = colors["bg"] as Color
	style.border_color = colors["border"] as Color
	style.set_border_width_all(maxi(1, border_width))
	style.set_corner_radius_all(0)
	style.set_content_margin_all(2.0)
	return style


static func make_empty_cell_stylebox() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CELL_BG
	style.border_color = CELL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	return style


static func apply_item_panel(panel: Panel, item: ItemData, border_width: int = 1) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", make_item_stylebox(item, border_width))


static func text_color_for_item(item: ItemData) -> Color:
	var colors: Dictionary = colors_for_item(item)
	return colors["text"] as Color
