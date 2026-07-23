extends Control
## Visual body-grid: unlocked cells, placed modules, corruption overlays.
## Click a free cell to place the currently selected stash item.

signal cell_clicked(cell: Vector2i)
signal stash_item_selected(index: int)

const CELL_SIZE := 48
const CELL_GAP := 4

var inventory: InventoryController
var selected_stash_index: int = -1

@onready var _grid_root: GridContainer = %GridRoot
@onready var _stash_list: VBoxContainer = %StashList
@onready var _hint_label: Label = %HintLabel
@onready var _mutation_label: Label = %MutationLabel


func setup(p_inventory: InventoryController) -> void:
	inventory = p_inventory
	if not EventBus.inventory_changed.is_connected(_on_inventory_changed):
		EventBus.inventory_changed.connect(_on_inventory_changed)
	if not EventBus.grid_expanded.is_connected(_on_grid_expanded):
		EventBus.grid_expanded.connect(_on_grid_expanded)
	if not EventBus.placement_failed.is_connected(_on_placement_failed):
		EventBus.placement_failed.connect(_on_placement_failed)
	refresh()


func refresh() -> void:
	if inventory == null:
		return
	_rebuild_grid()
	_rebuild_stash()
	_hint_label.text = "Select a stash module, then click a grid cell. Edge items need the outer frame."


func _on_inventory_changed() -> void:
	refresh()


func _on_grid_expanded(new_cells: Array[Vector2i]) -> void:
	_mutation_label.text = "MUTATION: flesh/bone overlay +%d cells" % new_cells.size()
	refresh()


func _on_placement_failed(reason: String) -> void:
	_hint_label.text = "Cannot place: %s" % reason


func _rebuild_grid() -> void:
	for child in _grid_root.get_children():
		child.queue_free()

	var g: BodyGrid = inventory.grid
	_grid_root.columns = g.width

	for y in g.height:
		for x in g.width:
			var cell := Vector2i(x, y)
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
			btn.focus_mode = Control.FOCUS_NONE
			btn.pressed.connect(_on_cell_pressed.bind(cell))

			if not g.is_unlocked(cell):
				btn.disabled = true
				btn.modulate = Color(0.15, 0.15, 0.15)
				btn.text = ""
			else:
				var occ := g.get_occupant(cell)
				if occ:
					# Show item name fragment only on origin cell.
					if occ.origin == cell:
						btn.text = _short_name(occ.data.display_name)
						btn.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
						var style := _make_style(occ.data.placeholder_color)
						btn.add_theme_stylebox_override("normal", style)
						btn.add_theme_stylebox_override("hover", style)
						btn.add_theme_stylebox_override("pressed", style)
					else:
						btn.text = ""
						var style2 := _make_style(occ.data.placeholder_color.darkened(0.15))
						btn.add_theme_stylebox_override("normal", style2)
						btn.add_theme_stylebox_override("hover", style2)
						btn.add_theme_stylebox_override("pressed", style2)
				else:
					btn.text = ""
					btn.add_theme_stylebox_override("normal", _make_style(Color(0.22, 0.22, 0.22)))
					btn.add_theme_stylebox_override("hover", _make_style(Color(0.3, 0.3, 0.3)))

				if g.is_corrupted(cell):
					btn.text = "X"
					btn.add_theme_color_override("font_color", Color(1.0, 0.35, 0.45))
					btn.modulate = Color(0.85, 0.4, 0.9)
					btn.tooltip_text = "Corrupted (%d turns)" % g.get_corruption_turns(cell)
				elif g.is_edge_cell(cell) and occ == null:
					btn.tooltip_text = "Edge cell"

			_grid_root.add_child(btn)


func _rebuild_stash() -> void:
	for child in _stash_list.get_children():
		child.queue_free()

	for i in inventory.stash.size():
		var data: ItemData = inventory.stash[i]
		var row := Button.new()
		row.text = "%s  [%dx%d]%s" % [
			data.display_name,
			data.size.x,
			data.size.y,
			"  EDGE" if data.requires_edge else "",
		]
		row.toggle_mode = true
		row.button_pressed = (i == selected_stash_index)
		row.pressed.connect(_on_stash_pressed.bind(i))
		row.tooltip_text = data.description
		_stash_list.add_child(row)


func _on_stash_pressed(index: int) -> void:
	selected_stash_index = index
	stash_item_selected.emit(index)
	_rebuild_stash()
	var data: ItemData = inventory.stash[index]
	_hint_label.text = "Placing: %s — click a free cell." % data.display_name


func _on_cell_pressed(cell: Vector2i) -> void:
	cell_clicked.emit(cell)
	if selected_stash_index < 0:
		# Unequip if clicking an occupied cell outside combat placement mode.
		var occ := inventory.grid.get_occupant(cell)
		if occ:
			inventory.unequip_to_stash(cell)
		return
	if inventory.try_place_from_stash(selected_stash_index, cell):
		selected_stash_index = -1
		_hint_label.text = "Module grafted."
	# else: placement_failed signal updates hint


func _short_name(full: String) -> String:
	var parts := full.split(" ")
	if parts.is_empty():
		return "?"
	return parts[0].substr(0, 4).to_upper()


func _make_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_border_width_all(1)
	s.border_color = Color(0.05, 0.05, 0.05)
	s.set_corner_radius_all(2)
	return s
