class_name NarrativeGodDialog
extends Resource
## Editor-facing pointer for a starting-god narrative (runtime loads the JSON).

@export var god_id: String = "pale_maiden"
@export var title_key: String = "EVENT_PALE_MAIDEN_TITLE"
@export var god_name: String = "Pale Maiden"
@export var god_name_ru: String = "Бледная дева"
@export_file("*.json") var dialog_json: String = "res://data/encounters/gods/pale_maiden.json"
@export var is_starting_god: bool = true
