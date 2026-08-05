class_name InventoryTheme
extends RefCounted
## Semi-transparent inventory tile palette by category / status.
## Background fill stays translucent so grid cells show through; borders stay opaque.

enum PaletteKind {
	WEAPON,
	ARMOR,
	CONSUMABLE,
	JUNK,
	RARE,
	HARMFUL,
}

## Empty unlocked body-grid cells (blueprint / X-ray).
const CELL_BG := Color("#1D1F24")
const CELL_BORDER := Color("#2F333D")

const _PALETTES := {
	PaletteKind.WEAPON: {
		"bg": Color("#7D6B56B3"),
		"border": Color("#A89279"),
		"text": Color("#E2D8C3"),
	},
	PaletteKind.ARMOR: {
		"bg": Color("#4B5563B3"),
		"border": Color("#6B7280"),
		"text": Color("#E5E7EB"),
	},
	PaletteKind.CONSUMABLE: {
		"bg": Color("#3B5E53B3"),
		"border": Color("#528374"),
		"text": Color("#A7F3D0"),
	},
	PaletteKind.JUNK: {
		"bg": Color("#374151B3"),
		"border": Color("#4B5563"),
		"text": Color("#9CA3AF"),
	},
	PaletteKind.RARE: {
		"bg": Color("#92702DB3"),
		"border": Color("#D97706"),
		"text": Color("#FEF08A"),
	},
	PaletteKind.HARMFUL: {
		"bg": Color("#702A30CC"),
		"border": Color("#B91C1C"),
		"text": Color("#FECDD3"),
	},
}


static func palette_kind_for_item(item: ItemData) -> PaletteKind:
	if item == null:
		return PaletteKind.JUNK
	if item.is_harmful:
		return PaletteKind.HARMFUL
	if item.rarity != null and item.rarity.get_tier() == ItemRarityData.Tier.RARE:
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
		"JUNK", "PARTS", "REACTOR", "CURRENCY":
			return PaletteKind.JUNK
		_:
			return PaletteKind.JUNK


static func colors_for_kind(kind: PaletteKind) -> Dictionary:
	if _PALETTES.has(kind):
		return _PALETTES[kind]
	return _PALETTES[PaletteKind.JUNK]


static func colors_for_item(item: ItemData) -> Dictionary:
	return colors_for_kind(palette_kind_for_item(item))


static func make_item_stylebox(item: ItemData, border_width: int = 1) -> StyleBoxFlat:
	var colors: Dictionary = colors_for_item(item)
	var style := StyleBoxFlat.new()
	style.bg_color = colors["bg"] as Color
	style.border_color = colors["border"] as Color
	style.set_border_width_all(maxi(1, border_width))
	style.set_corner_radius_all(3)
	## Keep content from sitting under the opaque stroke.
	style.set_content_margin_all(2.0)
	return style


static func make_empty_cell_stylebox() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CELL_BG
	style.border_color = CELL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	return style


static func apply_item_panel(panel: Panel, item: ItemData, border_width: int = 1) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", make_item_stylebox(item, border_width))


static func text_color_for_item(item: ItemData) -> Color:
	var colors: Dictionary = colors_for_item(item)
	return colors["text"] as Color
