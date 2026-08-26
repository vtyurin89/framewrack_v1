class_name StatCheckRollModal
extends BaseModalWindow
## Non-dismissible skill-check roll: dice flicker, then Success / Failure.

const FLICKER_DURATION := 0.5
const FLICKER_STEP := 0.045
const HOLD_DURATION := 1.35
const DIE_FONT_SIZE := 42
const RESULT_FONT_SIZE := 28
const DIE_MIN_SIZE := Vector2(72, 72)

var _dice_row: HFlowContainer
var _result_label: Label
var _die_labels: Array[Label] = []
var _click_player: AudioStreamPlayer
var _busy: bool = false


func _ready() -> void:
	super._ready()
	if _close_btn:
		_close_btn.visible = false
		_close_btn.disabled = true
	if _dialog:
		_dialog.custom_minimum_size = Vector2(420, 220)
	_ensure_content()
	_ensure_click_audio()


func _unhandled_input(_event: InputEvent) -> void:
	## Locked until the roll presentation finishes.
	pass


func _on_overlay_gui_input(_event: InputEvent) -> void:
	## No backdrop dismiss.
	pass


func present(result: StatCheckManager.CheckResult) -> void:
	if result == null:
		return
	_busy = true
	_ensure_content()
	_build_dice_cells(maxi(1, result.dice_rolled if result.dice_rolled > 0 else result.rolls.size()))
	_result_label.visible = false
	_result_label.text = ""
	for label in _die_labels:
		label.add_theme_color_override("font_color", GamePalette.CRT_TEXT_MAIN)
		label.text = "[ 1 ]"
	open()
	await _run_flicker(result)
	_apply_final_rolls(result)
	_show_banner(result.is_success)
	await get_tree().create_timer(HOLD_DURATION).timeout
	close()
	_busy = false


func is_busy() -> bool:
	return _busy


func _ensure_content() -> void:
	if _dice_row != null and is_instance_valid(_dice_row):
		return
	if content_container == null:
		content_container = %ContentContainer
	clear_content()

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 22)
	content_container.add_child(root)

	_dice_row = HFlowContainer.new()
	_dice_row.alignment = FlowContainer.ALIGNMENT_CENTER
	_dice_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dice_row.add_theme_constant_override("h_separation", 14)
	_dice_row.add_theme_constant_override("v_separation", 10)
	root.add_child(_dice_row)

	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_label.add_theme_font_size_override("font_size", RESULT_FONT_SIZE)
	_result_label.visible = false
	root.add_child(_result_label)


func _build_dice_cells(count: int) -> void:
	for child in _dice_row.get_children():
		child.queue_free()
	_die_labels.clear()
	for _i in count:
		var cell := PanelContainer.new()
		cell.custom_minimum_size = DIE_MIN_SIZE
		var style := GamePalette.make_panel_stylebox(
			GamePalette.BACKGROUND_DARK, GamePalette.MUTED_GREEN, 1, 0, 4.0, false
		)
		cell.add_theme_stylebox_override("panel", style)

		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", DIE_FONT_SIZE)
		label.add_theme_color_override("font_color", GamePalette.CRT_TEXT_MAIN)
		label.text = "[ 1 ]"
		cell.add_child(label)
		_dice_row.add_child(cell)
		_die_labels.append(label)


func _run_flicker(result: StatCheckManager.CheckResult) -> void:
	var elapsed := 0.0
	while elapsed < FLICKER_DURATION:
		for label in _die_labels:
			label.text = "[ %d ]" % randi_range(1, 6)
			label.add_theme_color_override("font_color", GamePalette.CRT_TEXT_MAIN)
		_play_terminal_click()
		await get_tree().create_timer(FLICKER_STEP).timeout
		elapsed += FLICKER_STEP
	## Ensure final frames land on backend rolls even if flicker overshoots.
	_apply_final_rolls(result)


func _apply_final_rolls(result: StatCheckManager.CheckResult) -> void:
	var rolls: Array[int] = result.rolls.duplicate()
	if rolls.is_empty() and result.is_guaranteed:
		for _i in _die_labels.size():
			rolls.append(6)
	while rolls.size() < _die_labels.size():
		rolls.append(1)
	for i in _die_labels.size():
		var value: int = clampi(int(rolls[i]), 1, 6)
		var label := _die_labels[i]
		label.text = "[ %d ]" % value
		## Face success (5–6) = green; otherwise red. Guaranteed paints all green.
		var success_face := result.is_guaranteed or value >= 5
		label.add_theme_color_override(
			"font_color",
			GamePalette.PHOSPHOR_ACTIVE if success_face else GamePalette.COLOR_DANGER
		)


func _show_banner(passed: bool) -> void:
	_result_label.visible = true
	if passed:
		_result_label.text = tr("KEY_STAT_CHECK_BANNER_SUCCESS")
		_result_label.add_theme_color_override("font_color", GamePalette.PHOSPHOR_BRIGHT)
	else:
		_result_label.text = tr("KEY_STAT_CHECK_BANNER_FAILURE")
		_result_label.add_theme_color_override("font_color", GamePalette.COLOR_DANGER)


func _ensure_click_audio() -> void:
	if _click_player != null and is_instance_valid(_click_player):
		return
	_click_player = AudioStreamPlayer.new()
	_click_player.name = "TerminalClick"
	_click_player.volume_db = -14.0
	_click_player.stream = _make_click_stream()
	add_child(_click_player)


func _play_terminal_click() -> void:
	if _click_player == null or _click_player.stream == null:
		return
	_click_player.stop()
	_click_player.play()


func _make_click_stream() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.028
	var samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(sample_rate)
		var env := 1.0 - (t / duration)
		env *= env
		var tone := sin(t * 2100.0 * TAU) * 0.55 + sin(t * 4200.0 * TAU) * 0.25
		var sample := int(clampf(tone * env * 0.35 * 32767.0, -32768.0, 32767.0))
		data.encode_s16(i * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream
