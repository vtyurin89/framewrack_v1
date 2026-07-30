class_name EventEncounterData
extends EncounterData
## Typed encounter wrapper for dialog-driven encounters.

@export var dialog_event: DialogEventData


func _init() -> void:
	type = EncounterType.EVENT


func get_dialog_event() -> DialogEventData:
	if dialog_event != null:
		return dialog_event
	return super.get_dialog_event()
