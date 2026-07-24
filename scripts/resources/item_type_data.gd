class_name ItemTypeData
extends Resource
## Classification for body-modules (weapon, reactor, shield, etc.).
## Provides a shared default icon used when an ItemData has no texture.

@export var id: String = ""
@export var type_name_key: String = ""
@export var display_name: String = "Unknown Type"

## Shared icon for all items of this type that lack a custom texture.
@export var default_type_icon: Texture2D


func get_localized_name() -> String:
	if not type_name_key.is_empty():
		return tr(type_name_key)
	return display_name
