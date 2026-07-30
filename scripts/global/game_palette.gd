extends Node
## Centralized combat / UI color palette (autoload).

const COLOR_PHYSICAL := Color("#ECF0F1")
const COLOR_CRIT := Color("#F1C40F")
const COLOR_POISON := Color("#2ECC71")
const COLOR_BURN := Color("#E67E22")
const COLOR_RUST := Color("#95A5A6")
const COLOR_HEAL := Color("#3498DB")
const COLOR_REPAIR := Color("#3498DB")
const COLOR_MISS := Color("#7F8C8D")
const COLOR_HP_MAIN := Color("#E74C3C")
const COLOR_HP_GHOST := Color("#F39C12")
const COLOR_SHIELD := Color("#3498DB")
const COLOR_MAIN_STORY := Color("#F1C40F")
const COLOR_MAP_PATH_LOCKED := Color("#646A73")
const COLOR_MAP_PATH_ACTIVE := Color("#ECF0F1")


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
