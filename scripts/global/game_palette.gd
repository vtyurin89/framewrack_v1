extends Node
## Centralized combat / UI color palette (autoload).

# --- Combat / map (legacy) ---------------------------------------------------

const COLOR_PHYSICAL := Color("#ECF0F1")
const COLOR_CRIT := Color("#F1C40F")
const COLOR_POISON := Color("#2ECC71")
const COLOR_BURN := Color("#E67E22")
const COLOR_RUST := Color("#95A5A6")
const COLOR_HEAL := Color("#3498DB")
const COLOR_REPAIR := Color("#3498DB")
const COLOR_MISS := Color("#7F8C8D")
const COLOR_HP_MAIN := Color("#842d2d")
## Trailing ghost uses a lighter tint of the same HP red.
const COLOR_HP_GHOST := Color("#a85a5a")
const COLOR_SHIELD := Color("#3498DB")
const COLOR_MAIN_STORY := Color("#F1C40F")
const COLOR_INTRO := Color("#9B59B6")
const COLOR_MAP_PATH_LOCKED := Color("#646A73")
const COLOR_MAP_PATH_ACTIVE := Color("#ECF0F1")
const COLOR_MAP_NODE_AVAILABLE := Color("#F1C40F")
const COLOR_MAP_NODE_VISITED := Color("#B0B8C0")
const COLOR_MAP_NODE_LOCKED := Color("#7F8C8D")
const COLOR_MAP_PATH_TRAVELED := Color("#9AA3AD")

# --- CRT terminal UI ---------------------------------------------------------

## Almost black with a green cast — primary background.
const COLOR_BG := Color("#080D0A")
## Very dark swamp green — panel backgrounds.
const COLOR_PANEL := Color("#0D1511")
## Dark grey-green — alternate panels.
const COLOR_PANEL_ALT := Color("#111C16")
## Dark forest green — inactive / disabled controls.
const COLOR_INACTIVE := Color("#173323")
## Muted green — secondary text, borders.
const COLOR_SECONDARY := Color("#285A3A")
## Soft CRT green — primary text and UI chrome.
const COLOR_PRIMARY := Color("#4FAF68")
## Light phosphor green — active / interactive elements.
const COLOR_ACTIVE := Color("#79D88A")
## Very light pale green — maximum highlight / emphasis.
const COLOR_HIGHLIGHT := Color("#A8F0A8")
## Dirty olive / yellow — warnings.
const COLOR_WARNING := Color("#B6B35A")
## Muted rust red — danger / critical state.
const COLOR_DANGER := Color("#A84D4D")
## Cool grey-teal green — special system elements.
const COLOR_SYSTEM := Color("#5FAF91")


func get_damage_color(damage_type: String, is_crit: bool = false, is_miss: bool = false) -> Color:
	if is_miss:
		return COLOR_MISS
	if is_crit:
		return COLOR_CRIT
	match damage_type.strip_edges().to_lower():
		"poison":
			return COLOR_POISON
		"burn":
			return COLOR_BURN
		"rust":
			return COLOR_RUST
		"heal", "healing":
			return COLOR_HEAL
		"repair":
			return COLOR_REPAIR
		"shield", "block":
			return COLOR_SHIELD
		"physical", "damage", "":
			return COLOR_PHYSICAL
		_:
			return COLOR_PHYSICAL


func get_status_glyph(damage_type: String) -> String:
	match damage_type.strip_edges().to_lower():
		"poison":
			return "🟢"
		"burn":
			return "🔥"
		"rust":
			return "⚙️"
		"heal", "healing", "repair":
			return "💙"
		_:
			return ""
