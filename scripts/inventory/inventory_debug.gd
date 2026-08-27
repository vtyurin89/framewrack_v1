class_name InventoryDebug
extends RefCounted
## Togglable traces for body-grid placement, polyomino masks, and rotation.
## Enable `DEBUG_INVENTORY_LOGS` while diagnosing edge / boundary bugs.

## Toggle to enable/disable detailed inventory placement logs.
const DEBUG_INVENTORY_LOGS: bool = false
## Also mirror lines to Output (print). File is always written when logging is on.
const DEBUG_INVENTORY_PRINT: bool = true
## Log file under user data: user://logs/inv_debug.log
const LOG_DIR := "user://logs"
const LOG_PATH := "user://logs/inv_debug.log"

static var _file: FileAccess = null
static var _path_announced: bool = false


static func log_inv(msg: String) -> void:
	if not DEBUG_INVENTORY_LOGS:
		return
	var line := "[%s] [INV_DEBUG] %s" % [_timestamp(), msg]
	if DEBUG_INVENTORY_PRINT:
		print(line)
	_append_file(line)


static func get_log_path() -> String:
	## Absolute OS path when possible (handy for Explorer).
	return ProjectSettings.globalize_path(LOG_PATH)


static func _timestamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	var ms := Time.get_ticks_msec() % 1000
	return "%04d-%02d-%02d %02d:%02d:%02d.%03d" % [
		int(t.get("year", 0)),
		int(t.get("month", 0)),
		int(t.get("day", 0)),
		int(t.get("hour", 0)),
		int(t.get("minute", 0)),
		int(t.get("second", 0)),
		ms,
	]


static func _ensure_file() -> bool:
	if _file != null and _file.is_open():
		return true
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.make_dir_recursive("logs")
	## Prefer append so a play session keeps history across reloads.
	if FileAccess.file_exists(LOG_PATH):
		_file = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
		if _file != null:
			_file.seek_end()
	else:
		_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _file == null:
		push_warning("InventoryDebug: cannot open log file '%s' (%s)" % [
			LOG_PATH, error_string(FileAccess.get_open_error())
		])
		return false
	if not _path_announced:
		_path_announced = true
		var abs_path := get_log_path()
		print("[INV_DEBUG] Writing inventory log to: %s" % abs_path)
		_file.store_line("[%s] [INV_DEBUG] === session start | %s ===" % [_timestamp(), abs_path])
		_file.flush()
	return true


static func _append_file(line: String) -> void:
	if not _ensure_file():
		return
	_file.store_line(line)
	_file.flush()


static func format_offsets(offsets: Array) -> String:
	if offsets == null or offsets.is_empty():
		return "[]"
	var parts: PackedStringArray = []
	for entry in offsets:
		var o: Vector2i = entry as Vector2i
		parts.append("(%d,%d)" % [o.x, o.y])
	return "[" + ", ".join(parts) + "]"


static func log_check_header(
	item_id: String,
	origin: Vector2i,
	grid_w: int,
	grid_h: int,
	mask: Array,
	rot_label: String = ""
) -> void:
	var rot := (" | %s" % rot_label) if not rot_label.is_empty() else ""
	log_inv(
		"--- [CHECK] Item '%s'%s | Origin: %s | Grid Limits: %dx%d ---"
		% [item_id, rot, str(origin), grid_w, grid_h]
	)
	log_inv("    Transformed Mask Offsets: %s" % format_offsets(mask))


static func log_cell_ok(cell: Vector2i, offset: Vector2i, detail: String = "Valid & Free") -> void:
	log_inv("    [OK] Cell %s (Offset %s) -> %s" % [str(cell), str(offset), detail])


static func log_cell_fail(reason: String, detail: String) -> void:
	log_inv("    [FAIL] %s: %s" % [reason, detail])


static func log_check_success(cell_count: int) -> void:
	log_inv("    [SUCCESS] Placement approved for all %d cells." % cell_count)


static func log_rotate_request(item_id: String, origin: Vector2i, from_label: String, to_label: String) -> void:
	log_inv(
		"=== [ROTATE REQUEST] '%s' at %s: %s -> %s ==="
		% [item_id, str(origin), from_label, to_label]
	)


static func log_rotate_result(item_id: String, success: bool) -> void:
	if success:
		log_inv("=== [ROTATE SUCCESS] '%s' rotated successfully ===" % item_id)
	else:
		log_inv("=== [ROTATE BLOCKED] Reverting rotation for '%s' ===" % item_id)
