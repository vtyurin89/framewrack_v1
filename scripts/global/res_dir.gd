class_name ResDir
extends RefCounted
## Helpers for listing res:// folders in editor and exported PCK builds.
## Exported packs often surface packed resources as `file.tres.remap`.

static func strip_export_suffix(file_name: String) -> String:
	var n := file_name
	if n.ends_with(".remap"):
		n = n.substr(0, n.length() - ".remap".length())
	if n.ends_with(".import"):
		n = n.substr(0, n.length() - ".import".length())
	return n


## Returns basenames matching suffix (e.g. ".tres") under dir_path.
static func list_files(dir_path: String, suffix: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var seen: Dictionary = {}

	if ResourceLoader.has_method("list_directory"):
		var listed: Variant = ResourceLoader.call("list_directory", dir_path)
		if listed is PackedStringArray:
			for entry in listed as PackedStringArray:
				var name := strip_export_suffix(str(entry)).trim_suffix("/")
				if name.ends_with(suffix) and not seen.has(name):
					seen[name] = true
					out.append(name)

	if not out.is_empty():
		return out

	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var clean := strip_export_suffix(file_name)
			if clean.ends_with(suffix) and not seen.has(clean):
				seen[clean] = true
				out.append(clean)
		file_name = dir.get_next()
	dir.list_dir_end()
	return out
