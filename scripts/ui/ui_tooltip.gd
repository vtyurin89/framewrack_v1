class_name UITooltip
extends PanelContainer
## Shared styled tooltip panel for status icons, intentions, and other UI hosts.

const MAX_WIDTH := 280.0
const TITLE_COLOR := Color(0.92, 0.92, 0.94)
const BODY_COLOR := Color(0.78, 0.78, 0.82)
const META_COLOR := Color(0.62, 0.62, 0.66)


static func create(title: String, body_lines: PackedStringArray = PackedStringArray()) -> UITooltip:
	var tip := UITooltip.new()
	tip._populate(title, body_lines)
	return tip


static func create_from_status(status: StatusInstance) -> UITooltip:
	return create(format_status_title(status), format_status_body_lines(status))


static func create_from_intention(intention: CombatIntention) -> UITooltip:
	return create(format_intention_description(intention))


static func format_status_title(status: StatusInstance) -> String:
	if status == null or status.data == null:
		return ""
	return status.data.get_display_title()


static func format_status_body_lines(status: StatusInstance) -> PackedStringArray:
	var lines: PackedStringArray = []
	if status == null or status.data == null:
		return lines
	lines.append(_format_status_count_label(status))
	var body := status.data.get_display_description(status.stacks, status.duration)
	if not body.is_empty():
		lines.append(body)
	return lines


static func format_status_text(status: StatusInstance) -> String:
	## Plain multiline fallback for hosts that still use tooltip_text.
	var title := format_status_title(status)
	var lines := format_status_body_lines(status)
	if title.is_empty():
		return "\n".join(lines)
	if lines.is_empty():
		return title
	return "%s\n%s" % [title, "\n".join(lines)]


static func format_intention_description(intention: CombatIntention) -> String:
	if intention == null or intention.is_empty():
		return _tr("KEY_INTENT_TIP_UNKNOWN")
	if intention.is_flee:
		return _tr("KEY_INTENT_TIP_FLEE")

	var ability: EnemyAbility = intention.source_ability
	var effect := ""
	if ability != null:
		effect = ability.infer_main_effect()

	if effect == "flee":
		return _tr("KEY_INTENT_TIP_FLEE")
	if effect == "summon":
		return _tr("KEY_INTENT_TIP_SUMMON")
	if effect == "status":
		var csv: PackedStringArray = ability.get_effect_param_list() if ability != null else PackedStringArray()
		if csv.size() >= 1 and str(csv[0]).strip_edges().to_lower() == "fleeing":
			return _tr("KEY_INTENT_TIP_FLEE")
	if _is_charge_windup(intention, ability, effect):
		return _tr("KEY_INTENT_TIP_CHARGE")
	if intention.is_secret or intention.primary_type == CombatIntention.Type.SECRET:
		## Summon is tagged secret for icon fog, but still has a clear tip above.
		if effect == "summon":
			return _tr("KEY_INTENT_TIP_SUMMON")
		return _tr("KEY_INTENT_TIP_SECRET")

	match intention.primary_type:
		CombatIntention.Type.ATTACK:
			if ability != null and ability.requires_prepare:
				return _tr("KEY_INTENT_TIP_HEAVY_ATTACK")
			if intention.hit_count > 1 or (
				ability != null and ability.type == EnemyAbility.AbilityType.MULTI_HIT
			):
				return _tr("KEY_INTENT_TIP_MULTI_ATTACK")
			return _tr("KEY_INTENT_TIP_ATTACK")
		CombatIntention.Type.DEFEND:
			return _tr("KEY_INTENT_TIP_DEFEND")
		CombatIntention.Type.HEAL:
			return _tr("KEY_INTENT_TIP_HEAL")
		CombatIntention.Type.BUFF:
			return _tr("KEY_INTENT_TIP_BUFF")
		CombatIntention.Type.DEBUFF:
			return _tr("KEY_INTENT_TIP_DEBUFF")
		_:
			return _tr("KEY_INTENT_TIP_UNKNOWN")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _populate(title: String, body_lines: PackedStringArray) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_panel_style()

	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	if not title.strip_edges().is_empty():
		var title_label := Label.new()
		title_label.text = title
		title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title_label.custom_minimum_size = Vector2(MAX_WIDTH - 20, 0)
		title_label.add_theme_font_size_override("font_size", 13)
		title_label.add_theme_color_override("font_color", TITLE_COLOR)
		title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(title_label)

	for i in body_lines.size():
		var line := str(body_lines[i]).strip_edges()
		if line.is_empty():
			continue
		var body := Label.new()
		body.text = line
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(MAX_WIDTH - 20, 0)
		body.add_theme_font_size_override("font_size", 12)
		body.add_theme_color_override("font_color", BODY_COLOR if i > 0 else META_COLOR)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(body)

	custom_minimum_size = Vector2(mini(MAX_WIDTH, 220.0), 0)


func _apply_panel_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.09, 0.96)
	style.set_border_width_all(1)
	style.border_color = Color(0.35, 0.35, 0.38)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 4
	add_theme_stylebox_override("panel", style)


static func _format_status_count_label(status: StatusInstance) -> String:
	if status.is_permanent():
		return _tr("KEY_STATUS_TIP_PERMANENT")
	match status.data.stack_type:
		StatusEffectData.StackType.DURATION:
			return _tr("KEY_STATUS_TIP_DURATION") % status.duration
		StatusEffectData.StackType.STACKS:
			return _tr("KEY_STATUS_TIP_STACKS") % status.stacks
		_:
			return _tr("KEY_STATUS_TIP_PERMANENT")


static func _tr(key: String) -> String:
	## Object.tr() is instance-only; static formatters use TranslationServer.
	return TranslationServer.translate(key)


static func _is_charge_windup(
	intention: CombatIntention, ability: EnemyAbility, effect: String
) -> bool:
	if ability == null:
		return false
	if effect != "modify_stat":
		return false
	## Prepare / wind-up rows arm a follow-up ability id in effect_params.
	var csv := ability.get_effect_param_list()
	for token in csv:
		var raw := str(token).strip_edges()
		if raw.begins_with("ABILITY_"):
			return true
	return ability.id.strip_edges().to_upper().begins_with("ABILITY_PREPARE")
