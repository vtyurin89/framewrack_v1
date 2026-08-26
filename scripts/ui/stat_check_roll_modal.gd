class_name StatCheckRollModal
extends BaseModalWindow
## Terminal diagnostic skill-check modal. Rolls come from StatCheckManager only.

signal skill_check_completed(success: bool)

const GRAIN_SHADER := preload("res://shaders/crt_grid_noise.gdshader")

const WIDTH_FRAC := 0.60
const HEIGHT_FRAC := 0.42
const MIN_DIALOG := Vector2(520, 360)
const MAX_DIALOG := Vector2(820, 560)

const FLICKER_DURATION := 0.5
const FLICKER_POLL := 0.02
const DELAY_BEFORE_FLICKER := 0.1
const DELAY_AFTER_SETTLE := 0.3
const DELAY_BEFORE_BANNER := 0.3
const HOLD_AFTER_BANNER := 1.25

const DICE_COLUMNS := 4
const DIE_SIZE := Vector2(64, 64)
const DIE_FONT := 36
const TITLE_FONT := 22
const DIAG_FONT := 13
const SECTION_FONT := 12
const BANNER_FONT := 36
const MARKER_SIZE := Vector2(14, 14)

var _root: VBoxContainer
var _title_label: Label
var _dice_count_label: Label
var _threshold_label: Label
var _dice_center: CenterContainer
var _dice_grid: GridContainer
var _success_section: VBoxContainer
var _success_title: Label
var _markers_row: HBoxContainer
var _ratio_label: Label
var _banner_label: Label
var _grain: ColorRect

var _die_panels: Array[PanelContainer] = []
var _die_labels: Array[Label] = []
var _marker_panels: Array[PanelContainer] = []

var _click_player: AudioStreamPlayer
var _busy: bool = false
var _stat_tag: String = "STR"
var _threshold: int = 1


func _ready() -> void:
	super._ready()
	_hide_chrome()
	_ensure_content()
	_ensure_click_audio()
	_apply_dialog_size()


func _unhandled_input(_event: InputEvent) -> void:
	pass


func _on_overlay_gui_input(_event: InputEvent) -> void:
	pass


func _on_viewport_size_changed() -> void:
	super._on_viewport_size_changed()
	if _is_open:
		_apply_dialog_size()


## Present backend rolls. UI never invents final dice values.
func present(
	result: StatCheckManager.CheckResult,
	stat_name: String = "",
	threshold: int = 1
) -> void:
	if result == null:
		return
	_busy = true
	_stat_tag = stat_name.strip_edges().to_upper()
	if _stat_tag.is_empty():
		_stat_tag = "STR"
	_threshold = maxi(1, threshold)
	_ensure_content()
	_apply_dialog_size()
	_reset_presentation(result)
	open()
	await _play_sequence(result)
	skill_check_completed.emit(result.is_success)
	close()
	_busy = false


func is_busy() -> bool:
	return _busy


func _hide_chrome() -> void:
	if _close_btn:
		_close_btn.visible = false
		_close_btn.disabled = true
		var header := _close_btn.get_parent()
		if header is Control:
			(header as Control).visible = false


func _apply_dialog_size() -> void:
	if _dialog == null:
		return
	var vp := get_viewport()
	var size := Vector2(640, 420)
	if vp != null:
		var rect := vp.get_visible_rect().size
		size = Vector2(rect.x * WIDTH_FRAC, rect.y * HEIGHT_FRAC)
	size.x = clampf(size.x, MIN_DIALOG.x, MAX_DIALOG.x)
	size.y = clampf(size.y, MIN_DIALOG.y, MAX_DIALOG.y)
	_dialog.custom_minimum_size = size
	_dialog.size = size


func _ensure_content() -> void:
	if _root != null and is_instance_valid(_root):
		return
	if content_container == null:
		content_container = %ContentContainer
	clear_content()

	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 10)
	content_container.add_child(_root)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", TITLE_FONT)
	_title_label.add_theme_color_override("font_color", GamePalette.PHOSPHOR_BRIGHT)
	_root.add_child(_title_label)
	_root.add_child(_make_separator())

	_dice_count_label = _make_diag_label()
	_root.add_child(_dice_count_label)
	_threshold_label = _make_diag_label()
	_root.add_child(_threshold_label)
	_root.add_child(_make_separator())

	_dice_center = CenterContainer.new()
	_dice_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dice_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(_dice_center)

	_dice_grid = GridContainer.new()
	_dice_grid.columns = DICE_COLUMNS
	_dice_grid.add_theme_constant_override("h_separation", 12)
	_dice_grid.add_theme_constant_override("v_separation", 12)
	_dice_center.add_child(_dice_grid)

	_success_section = VBoxContainer.new()
	_success_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_success_section.add_theme_constant_override("separation", 6)
	_success_section.visible = false
	_root.add_child(_success_section)

	_success_title = Label.new()
	_success_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_success_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_success_title.add_theme_font_size_override("font_size", SECTION_FONT)
	_success_title.add_theme_color_override("font_color", GamePalette.CRT_TEXT_MAIN)
	_success_title.text = tr("KEY_STAT_CHECK_SUCCESS_COUNT")
	_success_section.add_child(_success_title)

	var count_row := HBoxContainer.new()
	count_row.alignment = BoxContainer.ALIGNMENT_CENTER
	count_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_row.add_theme_constant_override("separation", 10)
	_success_section.add_child(count_row)

	_markers_row = HBoxContainer.new()
	_markers_row.add_theme_constant_override("separation", 4)
	count_row.add_child(_markers_row)

	_ratio_label = Label.new()
	_ratio_label.add_theme_font_size_override("font_size", DIAG_FONT)
	_ratio_label.add_theme_color_override("font_color", GamePalette.PHOSPHOR_ACTIVE)
	count_row.add_child(_ratio_label)

	_banner_label = Label.new()
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner_label.add_theme_font_size_override("font_size", BANNER_FONT)
	_banner_label.visible = false
	_root.add_child(_banner_label)

	## Overlay on the modal root (not PanelContainer) so layout stays intact.
	_grain = ColorRect.new()
	_grain.name = "CrtGrain"
	_grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grain.color = Color(1, 1, 1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = GRAIN_SHADER
	mat.set_shader_parameter("grain_amount", 0.03)
	mat.set_shader_parameter("scanline_opacity", 0.05)
	mat.set_shader_parameter("static_speed", 1.4)
	_grain.material = mat
	add_child(_grain)
	_grain.z_index = 20
	set_process(true)


func _process(_delta: float) -> void:
	_sync_grain_rect()


func _sync_grain_rect() -> void:
	if _grain == null or not is_instance_valid(_grain) or _dialog == null:
		return
	_grain.visible = _is_open
	if not _is_open:
		return
	_grain.global_position = _dialog.global_position
	_grain.size = _dialog.size


func _make_diag_label() -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", DIAG_FONT)
	label.add_theme_color_override("font_color", GamePalette.CRT_TEXT_MAIN)
	return label


func _make_separator() -> ColorRect:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.color = GamePalette.MUTED_GREEN
	line.modulate = Color(1, 1, 1, 0.85)
	return line


func _reset_presentation(result: StatCheckManager.CheckResult) -> void:
	var dice_n := maxi(1, result.dice_rolled if result.dice_rolled > 0 else result.rolls.size())
	_title_label.text = tr("KEY_STAT_CHECK_MODAL_TITLE") % _stat_tag
	_dice_count_label.text = _format_diag(tr("KEY_STAT_CHECK_DICE_COUNT"), dice_n)
	_threshold_label.text = _format_diag(tr("KEY_STAT_CHECK_THRESHOLD"), _threshold)
	_success_title.text = tr("KEY_STAT_CHECK_SUCCESS_COUNT")
	_success_section.visible = false
	_banner_label.visible = false
	_banner_label.text = ""
	_build_dice_cells(dice_n)
	_build_markers(dice_n)
	for i in _die_labels.size():
		_set_die_neutral(i)


func _format_diag(label: String, value: int) -> String:
	var val := "%02d" % value
	var pad := 28 - label.length() - val.length()
	var dots := ".".repeat(maxi(3, pad))
	return "%s %s %s" % [label, dots, val]


func _build_dice_cells(count: int) -> void:
	for child in _dice_grid.get_children():
		child.queue_free()
	_die_panels.clear()
	_die_labels.clear()
	_dice_grid.columns = DICE_COLUMNS
	for _i in count:
		var cell := PanelContainer.new()
		cell.custom_minimum_size = DIE_SIZE
		cell.add_theme_stylebox_override("panel", _die_style(GamePalette.MUTED_GREEN))

		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", DIE_FONT)
		label.add_theme_color_override("font_color", GamePalette.CRT_TEXT_MAIN)
		label.text = "?"
		cell.add_child(label)
		_dice_grid.add_child(cell)
		_die_panels.append(cell)
		_die_labels.append(label)


func _build_markers(count: int) -> void:
	for child in _markers_row.get_children():
		child.queue_free()
	_marker_panels.clear()
	for _i in count:
		var mark := PanelContainer.new()
		mark.custom_minimum_size = MARKER_SIZE
		mark.add_theme_stylebox_override("panel", _marker_style(false))
		_markers_row.add_child(mark)
		_marker_panels.append(mark)


func _die_style(border: Color) -> StyleBoxFlat:
	return GamePalette.make_panel_stylebox(
		GamePalette.BACKGROUND_DARK, border, 1, 0, 2.0, false
	)


func _marker_style(filled: bool) -> StyleBoxFlat:
	if filled:
		return GamePalette.make_panel_stylebox(
			GamePalette.PHOSPHOR_ACTIVE, GamePalette.PHOSPHOR_ACTIVE, 1, 0, 0.0, false
		)
	return GamePalette.make_panel_stylebox(
		Color(0, 0, 0, 0), GamePalette.MUTED_GREEN, 1, 0, 0.0, false
	)


func _set_die_neutral(index: int) -> void:
	if index < 0 or index >= _die_labels.size():
		return
	_die_labels[index].text = "?"
	_die_labels[index].modulate = Color.WHITE
	_die_labels[index].add_theme_color_override("font_color", GamePalette.CRT_TEXT_MAIN)
	_die_panels[index].add_theme_stylebox_override("panel", _die_style(GamePalette.MUTED_GREEN))


func _play_sequence(result: StatCheckManager.CheckResult) -> void:
	await get_tree().create_timer(DELAY_BEFORE_FLICKER).timeout
	await _run_flicker()
	_apply_backend_rolls(result)
	await get_tree().create_timer(DELAY_AFTER_SETTLE).timeout
	_show_success_count(result)
	await get_tree().create_timer(DELAY_BEFORE_BANNER).timeout
	_show_banner(result.is_success)
	await get_tree().create_timer(HOLD_AFTER_BANNER).timeout


func _run_flicker() -> void:
	var count := _die_labels.size()
	var die_accum: Array[float] = []
	var die_step: Array[float] = []
	for _i in count:
		die_accum.append(-randf_range(0.0, 0.1))
		die_step.append(randf_range(0.028, 0.055))
	var elapsed := 0.0
	while elapsed < FLICKER_DURATION:
		await get_tree().create_timer(FLICKER_POLL).timeout
		elapsed += FLICKER_POLL
		var any_tick := false
		for i in count:
			die_accum[i] += FLICKER_POLL
			if die_accum[i] < die_step[i]:
				continue
			die_accum[i] = 0.0
			any_tick = true
			_die_labels[i].text = str(randi_range(1, 6))
			_die_labels[i].add_theme_color_override("font_color", GamePalette.CRT_TEXT_MAIN)
			_die_panels[i].add_theme_stylebox_override("panel", _die_style(GamePalette.MUTED_GREEN))
			## Subtle CRT signal hit — visual only.
			if randf() < 0.4:
				_die_labels[i].modulate = Color(1, 1, 1, randf_range(0.55, 1.0))
			else:
				_die_labels[i].modulate = Color.WHITE
		if any_tick:
			_play_terminal_click()


func _apply_backend_rolls(result: StatCheckManager.CheckResult) -> void:
	var rolls: Array[int] = []
	for value in result.rolls:
		rolls.append(int(value))
	## Guaranteed path may already fill rolls; never invent faces beyond that.
	if rolls.is_empty() and result.is_guaranteed:
		for _i in _die_labels.size():
			rolls.append(6)
	for i in _die_labels.size():
		var value := 1
		if i < rolls.size():
			value = clampi(rolls[i], 1, 6)
		_die_labels[i].modulate = Color.WHITE
		_die_labels[i].text = str(value)
		var face_ok := result.is_guaranteed or _is_face_success(value)
		var color := GamePalette.PHOSPHOR_ACTIVE if face_ok else GamePalette.COLOR_DANGER
		_die_labels[i].add_theme_color_override("font_color", color)
		_die_panels[i].add_theme_stylebox_override("panel", _die_style(color))


func _is_face_success(roll: int) -> bool:
	if StatCheckManager != null and StatCheckManager.has_method("is_face_success"):
		return StatCheckManager.is_face_success(roll)
	return roll >= 5


func _show_success_count(result: StatCheckManager.CheckResult) -> void:
	var got := result.successes_count
	if result.is_guaranteed:
		got = _die_labels.size()
	for i in _marker_panels.size():
		_marker_panels[i].add_theme_stylebox_override("panel", _marker_style(i < got))
	_ratio_label.text = "%02d / %02d" % [got, _threshold]
	_ratio_label.add_theme_color_override(
		"font_color",
		GamePalette.PHOSPHOR_ACTIVE if result.is_success else GamePalette.COLOR_DANGER
	)
	_success_section.visible = true


func _show_banner(passed: bool) -> void:
	_banner_label.visible = true
	if passed:
		_banner_label.text = tr("KEY_STAT_CHECK_BANNER_SUCCESS").to_upper()
		_banner_label.add_theme_color_override("font_color", GamePalette.PHOSPHOR_BRIGHT)
	else:
		_banner_label.text = tr("KEY_STAT_CHECK_BANNER_FAILURE").to_upper()
		_banner_label.add_theme_color_override("font_color", GamePalette.COLOR_DANGER)


func _ensure_click_audio() -> void:
	if _click_player != null and is_instance_valid(_click_player):
		return
	_click_player = AudioStreamPlayer.new()
	_click_player.name = "TerminalClick"
	_click_player.volume_db = -16.0
	_click_player.stream = _make_click_stream()
	add_child(_click_player)


func _play_terminal_click() -> void:
	if _click_player == null or _click_player.stream == null:
		return
	_click_player.stop()
	_click_player.play()


func _make_click_stream() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.022
	var samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(sample_rate)
		var env := 1.0 - (t / duration)
		env *= env
		var tone := sin(t * 1900.0 * TAU) * 0.5 + sin(t * 3800.0 * TAU) * 0.2
		var sample := int(clampf(tone * env * 0.28 * 32767.0, -32768.0, 32767.0))
		data.encode_s16(i * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream
