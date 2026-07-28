class_name DialogNodeData
extends Resource
## One step in a dialog event tree.

@export var id: String = ""
@export var text: String = ""
@export var text_key: String = ""
@export var choices: Array[DialogChoiceData] = []


func get_display_text() -> String:
	if not text_key.is_empty():
		return tr(text_key)
	return text
