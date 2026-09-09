extends Node
## Autoload: loads StatusEffectData resources from res://data/statuses/.

const STATUSES_DIR := "res://data/statuses/"

var _by_id: Dictionary = {}  # String -> StatusEffectData


func _ready() -> void:
	reload()


func reload() -> void:
	_by_id.clear()
	var files := ResDir.list_files(STATUSES_DIR, ".tres")
	if files.is_empty():
		push_warning("StatusEffectDatabase: no .tres under %s" % STATUSES_DIR)
		return
	for file_name in files:
		var path := STATUSES_DIR.path_join(file_name)
		if not ResourceLoader.exists(path):
			continue
		var loaded: Resource = ResourceLoader.load(path)
		if loaded is StatusEffectData:
			var data := loaded as StatusEffectData
			var key := data.id.strip_edges().to_lower()
			if key.is_empty():
				key = file_name.get_basename().to_lower()
				data.id = key
			_by_id[key] = data


func has_status(status_id: String) -> bool:
	return _by_id.has(status_id.strip_edges().to_lower())


func get_status(status_id: String) -> StatusEffectData:
	return _by_id.get(status_id.strip_edges().to_lower(), null) as StatusEffectData


func get_all() -> Array[StatusEffectData]:
	var result: Array[StatusEffectData] = []
	for key in _by_id.keys():
		result.append(_by_id[key] as StatusEffectData)
	return result
