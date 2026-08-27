extends Node
## Centralized CRT terminal + combat color palette (autoload).

# --- CRT terminal UI (canonical names) ---------------------------------------

## Almost black with a green cast — primary background.
const BACKGROUND_DARK := Color("#080D0A")
## Very dark swamp green — panel backgrounds.
const PANEL_BG := Color("#0D1511")
## Dark grey-green — alternate panels / cards.
const PANEL_BG_ALT := Color("#111C16")
## Dark forest green — inactive / disabled controls.
const INACTIVE_ELEMENT := Color("#173323")
## Muted green — borders, secondary text, grid lines.
const MUTED_GREEN := Color("#285A3A")
## Soft CRT green — primary text and UI chrome.
const CRT_TEXT_MAIN := Color("#4FAF68")
## Light phosphor green — active / focused / filled gauges.
const PHOSPHOR_ACTIVE := Color("#79D88A")
## Very light pale green — maximum highlight / selected / key values.
const PHOSPHOR_BRIGHT := Color("#A8F0A8")
## Dirty olive / yellow — warnings.
const COLOR_WARN := Color("#B6B35A")
## Muted rust red — danger / critical / damage.
const COLOR_DANGER := Color("#A84D4D")
## Cool grey-teal green — system UI accents / shields / intro.
const COLOR_CYAN_SYSTEM := Color("#5FAF91")

# Short aliases (older call sites).
const COLOR_BG := BACKGROUND_DARK
const COLOR_PANEL := PANEL_BG
const COLOR_PANEL_ALT := PANEL_BG_ALT
const COLOR_INACTIVE := INACTIVE_ELEMENT
const COLOR_SECONDARY := MUTED_GREEN
const COLOR_PRIMARY := CRT_TEXT_MAIN
const COLOR_ACTIVE := PHOSPHOR_ACTIVE
const COLOR_HIGHLIGHT := PHOSPHOR_BRIGHT
const COLOR_WARNING := COLOR_WARN
const COLOR_SYSTEM := COLOR_CYAN_SYSTEM

# --- Combat feedback (remapped onto CRT luminance) ---------------------------

const COLOR_PHYSICAL := PHOSPHOR_BRIGHT
const COLOR_CRIT := COLOR_WARN
const COLOR_POISON := PHOSPHOR_ACTIVE
const COLOR_BURN := Color("#C47A3A") ## warm amber still reads as “burn” on CRT
const COLOR_RUST := MUTED_GREEN
const COLOR_HEAL := COLOR_CYAN_SYSTEM
const COLOR_REPAIR := COLOR_CYAN_SYSTEM
const COLOR_MISS := INACTIVE_ELEMENT
const COLOR_HP_MAIN := PHOSPHOR_ACTIVE
const COLOR_HP_GHOST := MUTED_GREEN
const COLOR_SHIELD := COLOR_CYAN_SYSTEM
const COLOR_MAIN_STORY := COLOR_WARN
const COLOR_INTRO := COLOR_CYAN_SYSTEM

# --- Map path / node states --------------------------------------------------

const COLOR_MAP_PATH_LOCKED := INACTIVE_ELEMENT
const COLOR_MAP_PATH_ACTIVE := PHOSPHOR_ACTIVE
const COLOR_MAP_PATH_TRAVELED := MUTED_GREEN
const COLOR_MAP_NODE_AVAILABLE := PHOSPHOR_BRIGHT
const COLOR_MAP_NODE_VISITED := CRT_TEXT_MAIN
const COLOR_MAP_NODE_LOCKED := MUTED_GREEN

# --- Typography (IBM Plex Mono) ----------------------------------------------

const FONT_REGULAR: Font = preload("res://assets/fonts/IBM_Plex_Mono/IBMPlexMono-Regular.ttf")
const FONT_MEDIUM: Font = preload("res://assets/fonts/IBM_Plex_Mono/IBMPlexMono-Medium.ttf")
const FONT_SEMIBOLD: Font = preload("res://assets/fonts/IBM_Plex_Mono/IBMPlexMono-SemiBold.ttf")
const FONT_BOLD: Font = preload("res://assets/fonts/IBM_Plex_Mono/IBMPlexMono-Bold.ttf")
const FONT_ITALIC: Font = preload("res://assets/fonts/IBM_Plex_Mono/IBMPlexMono-Italic.ttf")
const FONT_BOLD_ITALIC: Font = preload("res://assets/fonts/IBM_Plex_Mono/IBMPlexMono-BoldItalic.ttf")


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
			return COLOR_DANGER
		_:
			return COLOR_PHYSICAL


func get_status_glyph(damage_type: String) -> String:
	match damage_type.strip_edges().to_lower():
		"poison":
			return "●"
		"burn":
			return "▲"
		"rust":
			return "⚙"
		"heal", "healing", "repair":
			return "+"
		_:
			return ""


# --- StyleBox factories ------------------------------------------------------

func make_panel_stylebox(
	bg: Color = PANEL_BG,
	border: Color = MUTED_GREEN,
	border_width: int = 1,
	corner: int = 0,
	content_margin: float = 8.0,
	with_glow: bool = false
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(maxi(0, border_width))
	style.set_corner_radius_all(maxi(0, corner))
	style.set_content_margin_all(content_margin)
	if with_glow:
		_apply_style_phosphor_glow(style)
	else:
		style.shadow_size = 0
	return style


func make_button_styleboxes() -> Dictionary:
	## Returns { normal, hover, pressed, disabled, focus } StyleBoxFlat.
	var normal := make_panel_stylebox(PANEL_BG_ALT, MUTED_GREEN, 1, 0, 10.0, false)
	var hover := make_panel_stylebox(PANEL_BG_ALT, PHOSPHOR_ACTIVE, 1, 0, 10.0, true)
	var pressed := make_panel_stylebox(INACTIVE_ELEMENT, PHOSPHOR_BRIGHT, 1, 0, 10.0, false)
	var disabled := make_panel_stylebox(
		Color(PANEL_BG.r, PANEL_BG.g, PANEL_BG.b, 0.85),
		INACTIVE_ELEMENT,
		1,
		0,
		10.0,
		false
	)
	var focus := hover.duplicate() as StyleBoxFlat
	return {
		"normal": normal,
		"hover": hover,
		"pressed": pressed,
		"disabled": disabled,
		"focus": focus,
	}


func apply_button_theme(btn: Button, font_size: int = 16) -> void:
	if btn == null:
		return
	var styles := make_button_styleboxes()
	btn.add_theme_stylebox_override("normal", styles["normal"])
	btn.add_theme_stylebox_override("hover", styles["hover"])
	btn.add_theme_stylebox_override("pressed", styles["pressed"])
	btn.add_theme_stylebox_override("disabled", styles["disabled"])
	btn.add_theme_stylebox_override("focus", styles["focus"])
	btn.add_theme_font_override("font", FONT_SEMIBOLD)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", CRT_TEXT_MAIN)
	btn.add_theme_color_override("font_hover_color", PHOSPHOR_ACTIVE)
	btn.add_theme_color_override("font_pressed_color", PHOSPHOR_BRIGHT)
	btn.add_theme_color_override("font_disabled_color", INACTIVE_ELEMENT)
	btn.add_theme_color_override("font_focus_color", PHOSPHOR_ACTIVE)


func apply_font_regular(control: Control) -> void:
	_apply_font(control, FONT_REGULAR)


func apply_font_label(control: Control) -> void:
	## UI labels / stats / important values.
	_apply_font(control, FONT_MEDIUM)


func apply_font_header(control: Control) -> void:
	## Section headers and primary chrome titles.
	_apply_font(control, FONT_SEMIBOLD)


func apply_font_emphasis(control: Control) -> void:
	## SUCCESS / FAILURE / crits / large dice results only.
	_apply_font(control, FONT_BOLD)


func _apply_font(control: Control, font: Font) -> void:
	if control == null or font == null:
		return
	if control is RichTextLabel:
		var rtl := control as RichTextLabel
		rtl.add_theme_font_override("normal_font", font)
		return
	control.add_theme_font_override("font", font)


func apply_label_primary(label: Control) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", CRT_TEXT_MAIN)


func apply_label_value(label: Control) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", PHOSPHOR_BRIGHT)


func apply_label_muted(label: Control) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", MUTED_GREEN)


func apply_label_system(label: Control) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", COLOR_CYAN_SYSTEM)


func apply_phosphor_glow(node: CanvasItem, enabled: bool = true) -> void:
	## Very soft green lift for the brightest interactive elements only.
	if node == null:
		return
	if enabled:
		node.self_modulate = Color(1.08, 1.12, 1.08, 1.0)
	else:
		node.self_modulate = Color.WHITE


func _apply_style_phosphor_glow(style: StyleBoxFlat) -> void:
	style.shadow_color = Color(PHOSPHOR_ACTIVE.r, PHOSPHOR_ACTIVE.g, PHOSPHOR_ACTIVE.b, 0.28)
	style.shadow_size = 4
	style.shadow_offset = Vector2.ZERO


func make_progress_bg_stylebox() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND_DARK
	style.border_color = MUTED_GREEN
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(1)
	return style


func make_progress_fill_stylebox(fill: Color = PHOSPHOR_ACTIVE) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(0)
	style.set_content_margin_all(0)
	return style
