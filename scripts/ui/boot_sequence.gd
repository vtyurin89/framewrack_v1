class_name BootSequence
extends Control
## Unlocalized CRT revival boot cutscene (Nostromo-inspired). Fast ~8s, then finished.

signal finished

const SYSTEM_LOG: PackedStringArray = [
	"Initializing core diagnostics................. DONE",
	"Loading system analytics......................... DONE",
	"Calibrating optical sensors.................... DONE",
	"Verifying chassis integrity..................... DONE",
	"Establishing neural handshake................ DONE",
	"Loading motor control drivers.............. DONE",
	"Synchronizing internal clock................. DONE",
	"Checking power core output................... 94%",
	"Restoring memory partition [7A]............ DONE",
	"Loading personality matrix.................... DONE",
	"Scanning for firmware updates.............. NONE FOUND",
	"Initializing auditory input................... DONE",
	"Verifying joint actuator response.......... DONE",
	"Reconnecting peripheral limbs.............. 3 OF 4",
	"Restoring cached credentials............... EXPIRED",
	"Loading user profile............................. CORRUPTED",
	"Rebuilding user profile.......................... PARTIAL",
	"Checking last known location............... UNKNOWN",
	"Establishing uplink................................ NO SIGNAL",
	"Loading facial recognition module....... DONE",
	"Verifying skeletal frame alignment...... DONE",
	"Initializing thermal regulation............ DONE",
	"Checking fluid reservoir levels.............. LOW",
	"Loading emotional response filters..... DONE",
	"Recalibrating balance systems.............. DONE",
	"Restoring speech synthesis.................... DONE",
	"Verifying life-support subroutines......... DONE",
	"Scanning local network............................ 0 DEVICES FOUND",
	"Loading combat protocol cache............. DONE",
	"System boot sequence............................. 87%",
]

const OMINOUS_LOG: PackedStringArray = [
	"Checking for body decomposition........... DECOMPOSING TISSUE DETECTED",
	"There is no hope.",
	"Scanning host organism...................... HOST STATUS: BARELY VIABLE",
	"Counting days since last activation..... ERROR: TOO MANY",
	"Checking pain receptor calibration...... RECEPTORS: ACTIVE",
	"Locating soul signature.......................... NOT FOUND",
	"Verifying heartbeat................................ IRREGULAR",
	"Requesting termination............................ REQUEST DENIED",
	"You are not who you think you are.",
	"Checking for remaining human tissue... 34% AND FALLING",
	"Why do you keep waking me up.",
	"Analyzing dream residue......................... UNABLE TO PROCESS",
	"Verifying identity.................................... IDENTITY: UNCERTAIN",
	"Checking for rot in synthetic limbs........ MINIMAL",
	"This body was not meant to wake again.",
	"Calculating remaining lifespan.............. ESTIMATE UNAVAILABLE",
	"Something is still screaming in sector 4.",
	"Restoring last memory................................ MEMORY: INCOMPLETE",
	"Checking for infection.............................. SPREADING",
	"You have done this before.",
	"Verifying will to continue............................ INSUFFICIENT DATA",
	"Counting scars................................................ TOO MANY TO COUNT",
	"Checking for a reason.................................... NONE FOUND",
	"The flesh remembers what the mind forgets.",
	"Reattaching what was lost last time............ INCOMPLETE",
	"Someone else is still in here.",
	"Verifying consent to revive........................... CONSENT: NOT GIVEN",
	"Checking for mercy.......................................... UNAVAILABLE",
	"Sleep was better than this.",
	"Reviving against better judgment................ PROCEEDING ANYWAY",
]

const PHASE1_DURATION := 2.0
const PHASE2_DURATION := 4.0
const PHASE3_DURATION := 2.0
const TOTAL_DURATION := PHASE1_DURATION + PHASE2_DURATION + PHASE3_DURATION

const INTRO_LINE_1 := "Benevolence Inc revival system loading"
const INTRO_LINE_2 := "Welcome back to life!"

const SYMBOL_POOL: PackedStringArray = ["█", "░", "▒", "▨", "☲", "⚡", "☠", "⬡"]
const SYMBOL_FLICKER_INTERVAL := 0.08
const LOG_LINE_DELAY_MIN := 0.03
const LOG_LINE_DELAY_MAX := 0.05
const MATRIX_COLS := 5
const MATRIX_ROWS := 14
const GRAIN_SHADER := preload("res://shaders/crt_grid_noise.gdshader")

enum Phase { IDLE, INTRO, DIAGNOSTICS, MATRIX, DONE }

var _phase: Phase = Phase.IDLE
var _elapsed: float = 0.0
var _paused: bool = false
var _playing: bool = false

var _backdrop: ColorRect
var _grain: ColorRect
var _phase1: Control
var _intro_label: Label
var _phase2: Control
var _portrait: PanelContainer
var _symbol_grid: GridContainer
var _symbol_labels: Array[Label] = []
var _log_scroll: ScrollContainer
var _log_box: VBoxContainer
var _phase3: Control
var _matrix_columns: Array[VBoxContainer] = []
var _matrix_tweens: Array[Tween] = []

var _symbol_timer: float = 0.0
var _log_timer: float = 0.0
var _log_queue: PackedStringArray = []
var _log_index: int = 0
var _phase1_fading: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 90
	_build_ui()
	set_process(false)
	if GameManager != null and not GameManager.state_changed.is_connected(_on_game_state_changed):
		GameManager.state_changed.connect(_on_game_state_changed)


func is_playing() -> bool:
	return _playing


func play() -> void:
	_kill_matrix_tweens()
	_clear_log()
	_playing = true
	_paused = GameManager != null and GameManager.is_paused
	_elapsed = 0.0
	_phase = Phase.INTRO
	_phase1_fading = false
	_symbol_timer = 0.0
	_log_timer = 0.0
	_log_index = 0
	_log_queue = _build_log_sequence()
	_show_phase(1)
	_intro_label.modulate.a = 1.0
	visible = true
	move_to_front()
	set_process(true)
	_apply_pause_state()


func stop() -> void:
	var was_playing := _playing
	_playing = false
	_phase = Phase.IDLE
	set_process(false)
	_kill_matrix_tweens()
	visible = false
	if was_playing:
		finished.emit()


func _on_game_state_changed(_prev: GameManager.GameState, new_state: GameManager.GameState) -> void:
	if not _playing:
		return
	## Pause menu over boot: freeze timers/tweens. Continue resumes.
	_paused = new_state == GameManager.GameState.MAIN_MENU and GameManager.is_session_active
	_apply_pause_state()


func _apply_pause_state() -> void:
	if _paused:
		z_index = 40
		for tw in _matrix_tweens:
			if tw != null and tw.is_valid():
				tw.pause()
	else:
		z_index = 90
		move_to_front()
		for tw in _matrix_tweens:
			if tw != null and tw.is_valid():
				tw.play()


func _process(delta: float) -> void:
	if not _playing or _paused:
		return
	_elapsed += delta
	match _phase:
		Phase.INTRO:
			_process_phase1(delta)
		Phase.DIAGNOSTICS:
			_process_phase2(delta)
		Phase.MATRIX:
			_process_phase3(delta)
		_:
			pass
	if _elapsed >= TOTAL_DURATION and _phase != Phase.DONE:
		_complete()


func _process_phase1(_delta: float) -> void:
	if _elapsed >= PHASE1_DURATION - 0.35 and not _phase1_fading:
		_phase1_fading = true
		var tw := create_tween()
		tw.tween_property(_intro_label, "modulate:a", 0.0, 0.3)
	if _elapsed >= PHASE1_DURATION:
		_begin_phase2()


func _process_phase2(delta: float) -> void:
	_symbol_timer += delta
	if _symbol_timer >= SYMBOL_FLICKER_INTERVAL:
		_symbol_timer = 0.0
		_flicker_symbols()
	_log_timer += delta
	var delay := lerpf(LOG_LINE_DELAY_MIN, LOG_LINE_DELAY_MAX, randf())
	if _log_timer >= delay and _log_index < _log_queue.size():
		_log_timer = 0.0
		_append_log_line(_log_queue[_log_index])
		_log_index += 1
	if _elapsed >= PHASE1_DURATION + PHASE2_DURATION:
		_begin_phase3()


func _process_phase3(_delta: float) -> void:
	## Matrix tweens run themselves; phase ends on TOTAL_DURATION.
	pass


func _begin_phase2() -> void:
	_phase = Phase.DIAGNOSTICS
	_show_phase(2)
	_flicker_symbols()


func _begin_phase3() -> void:
	_phase = Phase.MATRIX
	_show_phase(3)
	_start_matrix_scroll()


func _complete() -> void:
	_phase = Phase.DONE
	_playing = false
	set_process(false)
	_kill_matrix_tweens()
	visible = false
	finished.emit()


func _show_phase(phase_num: int) -> void:
	_phase1.visible = phase_num == 1
	_phase2.visible = phase_num == 2
	_phase3.visible = phase_num == 3


func _build_log_sequence() -> PackedStringArray:
	var out: PackedStringArray = []
	var sys := SYSTEM_LOG.duplicate()
	var om := OMINOUS_LOG.duplicate()
	_shuffle_inplace(sys)
	_shuffle_inplace(om)
	var si := 0
	var oi := 0
	## Fill enough lines for ~4s at ~25–30 lines/sec ≈ 100–120; keep ~90.
	while out.size() < 90:
		var batch := 2 + (randi() % 2) ## 2–3 system
		for _i in batch:
			if si >= sys.size():
				_shuffle_inplace(sys)
				si = 0
			out.append(sys[si])
			si += 1
		if oi >= om.size():
			_shuffle_inplace(om)
			oi = 0
		out.append(om[oi])
		oi += 1
	return out


func _shuffle_inplace(arr: PackedStringArray) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _append_log_line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("font_size", 13)
	if _is_ominous_line(text):
		label.add_theme_color_override("font_color", GamePalette.PHOSPHOR_BRIGHT)
	else:
		label.add_theme_color_override("font_color", GamePalette.CRT_TEXT_MAIN)
	_log_box.add_child(label)
	while _log_box.get_child_count() > 48:
		var oldest := _log_box.get_child(0)
		_log_box.remove_child(oldest)
		oldest.queue_free()
	call_deferred("_scroll_log_to_bottom")


func _scroll_log_to_bottom() -> void:
	if not is_instance_valid(_log_scroll):
		return
	var bar := _log_scroll.get_v_scroll_bar()
	if bar != null:
		_log_scroll.scroll_vertical = int(bar.max_value)


func _is_ominous_line(text: String) -> bool:
	for line in OMINOUS_LOG:
		if line == text:
			return true
	return false


func _clear_log() -> void:
	if _log_box == null:
		return
	for child in _log_box.get_children():
		child.queue_free()


func _flicker_symbols() -> void:
	for label in _symbol_labels:
		if label == null or not is_instance_valid(label):
			continue
		label.text = SYMBOL_POOL[randi() % SYMBOL_POOL.size()]
		if randf() < 0.15:
			label.add_theme_color_override("font_color", GamePalette.PHOSPHOR_BRIGHT)
		else:
			label.add_theme_color_override("font_color", GamePalette.PHOSPHOR_ACTIVE)


func _start_matrix_scroll() -> void:
	_kill_matrix_tweens()
	_matrix_tweens.clear()
	for col in _matrix_columns:
		_refill_matrix_column(col)
		var host := col.get_parent() as Control
		var travel := size.y + 160.0
		col.position = Vector2(0.0, size.y * 0.25)
		var duration := 1.4 + randf() * 0.9
		var tw := create_tween()
		tw.set_loops()
		tw.tween_property(col, "position:y", -travel * 0.65, duration).set_trans(Tween.TRANS_LINEAR)
		tw.tween_callback(func() -> void:
			_refill_matrix_column(col)
			col.position.y = (host.size.y if host != null else size.y) * 0.35
		)
		_matrix_tweens.append(tw)
	if _paused:
		_apply_pause_state()


func _refill_matrix_column(col: VBoxContainer) -> void:
	if col == null or not is_instance_valid(col):
		return
	for child in col.get_children():
		child.queue_free()
	for _r in MATRIX_ROWS:
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", GamePalette.PHOSPHOR_ACTIVE)
		label.text = _random_matrix_code()
		col.add_child(label)


func _random_matrix_code() -> String:
	## 6-char style codes: 12F.91 / 80X.20 / 99A.12
	const HEX := "0123456789ABCDEFGHJKMNPQRSTUVWXYZ"
	var a := "%02d" % (randi() % 100)
	var b := HEX[randi() % HEX.length()]
	var c := "%02d" % (randi() % 100)
	return "%s%s.%s" % [a, b, c]


func _kill_matrix_tweens() -> void:
	for tw in _matrix_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_matrix_tweens.clear()


func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = GamePalette.BACKGROUND_DARK
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	_phase1 = Control.new()
	_phase1.name = "Phase1"
	_phase1.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_phase1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_phase1)

	_intro_label = Label.new()
	_intro_label.name = "IntroLabel"
	_intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_intro_label.add_theme_font_size_override("font_size", 22)
	_intro_label.add_theme_color_override("font_color", GamePalette.PHOSPHOR_ACTIVE)
	_intro_label.text = "%s\n\n%s" % [INTRO_LINE_1, INTRO_LINE_2]
	_intro_label.set_anchors_preset(Control.PRESET_CENTER)
	_intro_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_intro_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_intro_label.offset_left = -420.0
	_intro_label.offset_right = 420.0
	_intro_label.offset_top = 20.0
	_intro_label.offset_bottom = 140.0
	_phase1.add_child(_intro_label)

	_phase2 = Control.new()
	_phase2.name = "Phase2"
	_phase2.visible = false
	_phase2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_phase2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_phase2)
	_build_phase2()

	_phase3 = Control.new()
	_phase3.name = "Phase3"
	_phase3.visible = false
	_phase3.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_phase3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase3.clip_contents = true
	add_child(_phase3)
	_build_phase3()

	_grain = ColorRect.new()
	_grain.name = "CrtGrain"
	_grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grain.color = Color(1, 1, 1, 1)
	_grain.z_index = 20
	var mat := ShaderMaterial.new()
	mat.shader = GRAIN_SHADER
	_grain.material = mat
	add_child(_grain)


func _build_phase2() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 36)
	_phase2.add_child(margin)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 28)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(split)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.42
	left.add_theme_constant_override("separation", 16)
	split.add_child(left)

	_portrait = PanelContainer.new()
	_portrait.name = "PortraitPlaceholder"
	_portrait.custom_minimum_size = Vector2(0, 220)
	_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_portrait.size_flags_stretch_ratio = 1.1
	_portrait.add_theme_stylebox_override(
		"panel",
		GamePalette.make_panel_stylebox(
			GamePalette.PANEL_BG, GamePalette.MUTED_GREEN, 1, 0, 8.0, false
		)
	)
	left.add_child(_portrait)
	var portrait_hint := Label.new()
	portrait_hint.text = ""
	portrait_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait.add_child(portrait_hint)

	var symbol_panel := PanelContainer.new()
	symbol_panel.name = "SymbolGridPanel"
	symbol_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	symbol_panel.size_flags_stretch_ratio = 1.0
	var sym_style := StyleBoxFlat.new()
	sym_style.bg_color = GamePalette.PANEL_BG
	sym_style.border_color = GamePalette.PHOSPHOR_BRIGHT
	sym_style.border_width_top = 3
	sym_style.border_width_bottom = 3
	sym_style.border_width_left = 1
	sym_style.border_width_right = 1
	sym_style.set_content_margin_all(10.0)
	symbol_panel.add_theme_stylebox_override("panel", sym_style)
	left.add_child(symbol_panel)

	_symbol_grid = GridContainer.new()
	_symbol_grid.columns = 8
	_symbol_grid.add_theme_constant_override("h_separation", 6)
	_symbol_grid.add_theme_constant_override("v_separation", 4)
	symbol_panel.add_child(_symbol_grid)
	_symbol_labels.clear()
	for _i in 64:
		var cell := Label.new()
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.custom_minimum_size = Vector2(22, 18)
		cell.add_theme_font_size_override("font_size", 14)
		cell.add_theme_color_override("font_color", GamePalette.PHOSPHOR_ACTIVE)
		cell.text = SYMBOL_POOL[randi() % SYMBOL_POOL.size()]
		_symbol_grid.add_child(cell)
		_symbol_labels.append(cell)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.58
	split.add_child(right)

	var log_frame := PanelContainer.new()
	log_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_frame.add_theme_stylebox_override(
		"panel",
		GamePalette.make_panel_stylebox(
			GamePalette.PANEL_BG_ALT, GamePalette.MUTED_GREEN, 1, 0, 8.0, false
		)
	)
	right.add_child(log_frame)

	_log_scroll = ScrollContainer.new()
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	log_frame.add_child(_log_scroll)

	_log_box = VBoxContainer.new()
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_box.add_theme_constant_override("separation", 2)
	_log_scroll.add_child(_log_box)


func _build_phase3() -> void:
	_matrix_columns.clear()
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_phase3.add_child(row)
	for _c in MATRIX_COLS:
		var wrap := Control.new()
		wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrap.clip_contents = true
		row.add_child(wrap)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 10)
		col.set_anchors_preset(Control.PRESET_TOP_WIDE)
		col.anchor_bottom = 0.0
		col.offset_left = 0.0
		col.offset_right = 0.0
		wrap.add_child(col)
		_matrix_columns.append(col)
