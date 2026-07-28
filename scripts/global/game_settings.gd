extends Node

@export var hide_debug_tools: bool = false


func toggle_debug_tools(hide: bool) -> void:
	hide_debug_tools = hide
	get_tree().call_group("debug_ui", "set_visible", not hide)
