extends Node
## Autoload: loads ActData blueprints from res://data/acts.csv.

const ACTS_CSV_PATH := "res://data/acts.csv"

var _acts_by_id: Dictionary = {}  # String -> ActData
var _acts_by_index: Dictionary = {}  # int -> ActData


func _ready() -> void:
	reload()


func reload() -> void:
	_acts_by_id.clear()
	_acts_by_index.clear()
	_load_acts_csv(ACTS_CSV_PATH)


func get_act_by_id(act_id: String) -> ActData:
	var key := act_id.strip_edges().to_lower()
	return _acts_by_id.get(key, null)


func get_act_by_index(index: int) -> ActData:
	return _acts_by_index.get(maxi(index, 1), null)


func get_all_acts() -> Array[ActData]:
	var result: Array[ActData] = []
	var indices: Array = _acts_by_index.keys()
	indices.sort()
	for idx in indices:
		var act: ActData = _acts_by_index[idx]
		if act != null:
			result.append(act)
	return result


func get_act_count() -> int:
	return _acts_by_index.size()


func _load_acts_csv(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("ActDatabase: missing %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("ActDatabase: cannot open %s" % path)
		return
	var header_map: Dictionary = {}
	var line_no := 0
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		line_no += 1
		if line.is_empty() or line.begins_with("#"):
			continue
		var row := _parse_csv_line(line)
		if row.is_empty():
			continue
		if header_map.is_empty():
			header_map = _header_map(row)
			continue
		var act := _row_to_act(row, header_map)
		if act == null or act.id.is_empty():
			push_warning("ActDatabase: skip invalid row %d in %s" % [line_no, path])
			continue
		_register_act(act)
	file.close()


func _register_act(act: ActData) -> void:
	var id_key := act.id.strip_edges().to_lower()
	_acts_by_id[id_key] = act
	_acts_by_index[act.act_index] = act


func _row_to_act(row: PackedStringArray, header: Dictionary) -> ActData:
	var act := ActData.new()
	act.id = _cell(row, header, "id")
	act.act_index = maxi(1, _parse_int(_cell(row, header, "act_index"), 1))
	act.title_key = _cell(row, header, "title_key")
	act.map_depth = maxi(5, _parse_int(_cell(row, header, "map_depth"), 15))
	act.boss_encounter_id = _cell(row, header, "boss_encounter_id")
	act.encounter_pools = _parse_string_list(_cell(row, header, "encounter_pools"))
	act.event_pools = _parse_string_list(_cell(row, header, "event_pools"))

	var faction := _cell(row, header, "primary_faction")
	if not faction.is_empty():
		act.primary_faction = faction.strip_edges().to_lower()
	else:
		_apply_default_faction(act)

	var normal_raw := _cell(row, header, "normal_threat_budget")
	var elite_raw := _cell(row, header, "elite_threat_budget")
	if not normal_raw.is_empty():
		act.normal_threat_budget = maxi(1, _parse_int(normal_raw, act.normal_threat_budget))
	if not elite_raw.is_empty():
		act.elite_threat_budget = maxi(1, _parse_int(elite_raw, act.elite_threat_budget))
	if normal_raw.is_empty() or elite_raw.is_empty():
		_apply_default_threat_budgets(act)

	act.boss_encounter_data = build_boss_encounter(act)
	return act


func _apply_default_faction(act: ActData) -> void:
	match act.act_index:
		2:
			act.primary_faction = "synthet"
		3:
			act.primary_faction = "chimera"
		_:
			act.primary_faction = "human"


func _apply_default_threat_budgets(act: ActData) -> void:
	match act.act_index:
		2:
			act.normal_threat_budget = 22
			act.elite_threat_budget = 38
		3:
			act.normal_threat_budget = 26
			act.elite_threat_budget = 44
		_:
			act.normal_threat_budget = 18
			act.elite_threat_budget = 32


func build_boss_encounter(act: ActData) -> EncounterData:
	var enc := EncounterData.new()
	enc.id = act.boss_encounter_id if not act.boss_encounter_id.is_empty() else "%s_boss" % act.id
	enc.type = EncounterData.EncounterType.COMBAT_BOSS
	enc.title_key = "KEY_TYPE_BOSS"
	enc.payload = {
		"act": act.act_index,
		"faction": act.primary_faction,
		"boss_encounter_id": enc.id,
		"encounter_pool": act.encounter_pools[0] if not act.encounter_pools.is_empty() else "",
	}
	return enc


func _parse_string_list(raw: String) -> Array[String]:
	var result: Array[String] = []
	var cleaned := raw.strip_edges().trim_prefix("\"").trim_suffix("\"")
	if cleaned.is_empty():
		return result
	for part in cleaned.split("|", false):
		if part.find(",") >= 0:
			for sub in str(part).split(",", false):
				var sid := str(sub).strip_edges()
				if not sid.is_empty():
					result.append(sid)
			continue
		var id := str(part).strip_edges()
		if not id.is_empty():
			result.append(id)
	return result


func _header_map(header: PackedStringArray) -> Dictionary:
	var map: Dictionary = {}
	for i in header.size():
		map[str(header[i]).strip_edges().to_lower()] = i
	return map


func _cell(row: PackedStringArray, col: Dictionary, name: String) -> String:
	var idx: int = int(col.get(name.to_lower(), -1))
	if idx < 0 or idx >= row.size():
		return ""
	return str(row[idx]).strip_edges()


func _parse_int(raw: String, default_value: int = 0) -> int:
	var cell := raw.strip_edges()
	if cell.is_empty() or not cell.is_valid_int():
		return default_value
	return int(cell)


func _parse_csv_line(line: String) -> PackedStringArray:
	## Minimal RFC-style CSV row parser (quoted fields supported).
	var out: PackedStringArray = []
	var field := ""
	var in_quotes := false
	var i := 0
	while i < line.length():
		var ch := line[i]
		if in_quotes:
			if ch == "\"":
				if i + 1 < line.length() and line[i + 1] == "\"":
					field += "\""
					i += 2
					continue
				in_quotes = false
				i += 1
				continue
			field += ch
			i += 1
			continue
		if ch == "\"":
			in_quotes = true
			i += 1
			continue
		if ch == ",":
			out.append(field)
			field = ""
			i += 1
			continue
		field += ch
		i += 1
	out.append(field)
	return out
