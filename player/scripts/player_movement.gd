extends Node

@export var cell_size: Vector2 = Vector2(32, 32)
@export var speed: float = 100.0
@export var y_offset: float = 16.0 # For isometric view, to sink player visually

# TileMap references
var primary_tilemap_layer: TileMapLayer = null
var tileset: TileSet = null

# References
var game_state_manager: Node
var player: CharacterBody2D

# Movement state
enum MovementPhase { IDLE, FOLLOWING_PATH }
var current_phase = MovementPhase.IDLE
var current_path_index: int = 0
var final_target_world_position: Vector2
var current_step_target_world_position: Vector2
var blocking_groups = ["NPC", "Solid", "Obstacle", "blocking_tilemap", "Container"]

# Player resources
var current_sp # Step Points - limited movement resource in turn-based mode

# Signals
signal path_completed
signal movement_started
signal step_taken(remaining_steps: int)
signal sp_changed(new_sp: int)

var astar_grid = AStarGrid2D.new()
var grid_size

var start = Vector2.ZERO
var end = Vector2.ZERO
var path = []

# Turn-based movement variables
@export var turn_based_tile_highlight_color: Color = Color(0.2, 0.8, 0.3, 0.5)
@export var turn_based_path_highlight_color: Color = Color(0.3, 0.6, 0.9, 0.4)
@export var turn_based_invalid_tile_color: Color = Color(0.9, 0.3, 0.2, 0.5)

# Visual aids for turn-based mode
var highlight_tiles: Array[Vector2i] = []
var current_path_tiles: Array[Vector2i] = []
var hover_tile: Vector2i = Vector2i(-1, -1)
var movement_range_indicator: Node2D

func _ready() -> void:
	# Get player reference from parent
	player = get_parent() as CharacterBody2D
	if not player:
		printerr("PlayerMovement: Parent is not a CharacterBody2D. Movement system needs to be a child of the player.")
		set_process(false)
		set_physics_process(false)
		return

	# Initialize SP after player is assigned
	current_sp = player.max_sp if player.get("max_sp") != null else 0
			
	final_target_world_position = player.global_position
	current_step_target_world_position = player.global_position
	
	# Get the GameStateManager singleton
	game_state_manager = get_node_or_null("/root/GameStateManager")
	if not game_state_manager:
		printerr("PlayerMovement: GameStateManager autoload not found.")
		
	# Connect our own step_taken signal to update the movement range
	if not is_connected("step_taken", Callable(self, "_on_step_taken")):
		connect("step_taken", Callable(self, "_on_step_taken"))
	
	# Also connect sp_changed signal for same purpose
	if not is_connected("sp_changed", Callable(self, "_on_sp_changed")):
		connect("sp_changed", Callable(self, "_on_sp_changed"))

func initialize_grid() -> void:
	if primary_tilemap_layer == null:
		print("Cannot initialize grid: No primary_tilemap_layer set")
		return
	
	if tileset == null:
		tileset = primary_tilemap_layer.tile_set
		if tileset == null:
			print("Cannot initialize grid: No tileset found in primary_tilemap_layer")
			return

	# Now you can use the primary_tilemap_layer to determine grid size if needed
	grid_size = Rect2i(Vector2i.ZERO, Vector2i(100, 100))  # Example region, adjust as needed
	print("Grid initialized with size: ", grid_size)
	astar_grid.region = grid_size  # Use the region property directly with Rect2i
	astar_grid.offset = cell_size / 2  # Center the grid on the origin
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar_grid.cell_shape = AStarGrid2D.CELL_SHAPE_ISOMETRIC_DOWN
	astar_grid.update()
	print("Grid made, isometric: ", astar_grid.default_estimate_heuristic)
	
	# Set tiles solid based on groups
	set_tiles_solid_from_groups()

	# Snap all entities to the grid
	snap_all_entities_to_grid()

func _enter_tree() -> void:
	# Create a node for visualizing movement range
	movement_range_indicator = Node2D.new()
	movement_range_indicator.name = "MovementRangeIndicator"
	movement_range_indicator.z_index = 100  # Make sure it appears above the tilemap
	add_child(movement_range_indicator)
	movement_range_indicator.visible = false

func get_realtime_path() -> Array[Vector2]:
	# This function is a placeholder for real-time pathfinding logic
	# In real-time mode, we might not need a path at all, just move directly
	if primary_tilemap_layer == null:
		print("Cannot find path: No primary_tilemap_layer set")
		return []
	
	# For now, return an empty path
	return []

func get_ideal_path():
	if start == end:
		return []
	
	# Make sure we have a valid grid
	if primary_tilemap_layer == null:
		print("Cannot find path: No primary_tilemap_layer set")
		return []
	
	# Check all nodes in the scene for blocking groups
	for group in blocking_groups:
		var nodes = get_tree().get_nodes_in_group(group)
		for node in nodes:
			if node is Node2D:
				var node_pos = node.global_position
				var local_pos = primary_tilemap_layer.to_local(node_pos)
				var cell = primary_tilemap_layer.local_to_map(local_pos)
				# Only mark if within grid bounds
				if grid_size.has_point(cell):
					astar_grid.set_point_solid(cell, true)

	# Snap start and end positions to tile centers
	var snapped_start = snap_to_tile(start)
	var snapped_end = snap_to_tile(end)

	# Convert world coordinates to grid coordinates	
	var start_cell = primary_tilemap_layer.local_to_map(primary_tilemap_layer.to_local(snapped_start))
	var end_cell = primary_tilemap_layer.local_to_map(primary_tilemap_layer.to_local(snapped_end))
	
	print("Finding path from world pos ", snapped_start, " to ", snapped_end)
	print("Converted to grid cells: from ", start_cell, " to ", end_cell)
	
	# Check if cells are within bounds
	if not grid_size.has_point(start_cell) or not grid_size.has_point(end_cell):
		print("Start or end position out of grid bounds")
		return []
		# Get path using grid coordinates
	var id_path = astar_grid.get_id_path(start_cell, end_cell)
	
	if id_path.is_empty():
		print("No path found from ", start_cell, " to ", end_cell)
		return []
	
	# Convert path back to world coordinates
	path = []
	for cell_pos in id_path:
		var world_pos = primary_tilemap_layer.to_global(primary_tilemap_layer.map_to_local(cell_pos))
		path.append(world_pos)
	
	print("Path found with ", path.size()-1, " points")
	return path

# Snaps a world position to the nearest tile center
func snap_to_tile(world_position: Vector2) -> Vector2:
	if not primary_tilemap_layer:
		return world_position
		
	# Convert to tilemap coordinates
	var local_pos = primary_tilemap_layer.to_local(world_position)
	var map_pos = primary_tilemap_layer.local_to_map(local_pos)
	
	# Convert back to world coordinates (centered on tile)
	# Add y_offset to ensure visual consistency
	var snapped_pos = primary_tilemap_layer.to_global(primary_tilemap_layer.map_to_local(map_pos))
	
	print("Snapped position from ", world_position, " to ", snapped_pos)
	return snapped_pos

# Snaps an entity (player or NPC) to the nearest tile center
func snap_entity_to_tile(entity: Node2D, npc_id: int = 0) -> void:
	if not is_instance_valid(entity):
		return
		
	var current_pos = entity.global_position
	var snapped_pos = snap_to_tile(current_pos)
	
	# Only snap if the distance isn't too large (prevents abrupt jumps)
	var distance = current_pos.distance_to(snapped_pos)
	if distance < cell_size.length() * 0.75:
		entity.global_position = snapped_pos
		print("Snapped entity ", npc_id, " to tile: distance was ", distance)
	else:
		print("Entity too far from tile center (", distance, "), not snapping")

# Call this after the level is loaded to snap all entities to the grid
func snap_all_entities_to_grid() -> void:
	if not primary_tilemap_layer:
		return
		
	# Snap the player if available
	if is_instance_valid(player):
		snap_entity_to_tile(player)
		
	print("Snapped all entities to grid")

# Implement a new function for processing input during player's turn
func _input(event: InputEvent) -> void:
	if not is_turn_based_mode() or not primary_tilemap_layer:
		return
		
	# Track mouse hover in turn-based mode for tile highlighting
	if event is InputEventMouseMotion:
		var mouse_pos = get_viewport().get_mouse_position()
		var local_mouse_pos = primary_tilemap_layer.to_local(primary_tilemap_layer.get_canvas_transform().affine_inverse() * mouse_pos)
		var new_hover_tile = primary_tilemap_layer.local_to_map(local_mouse_pos)
		
		if new_hover_tile != hover_tile:
			hover_tile = new_hover_tile
			# Add a small delay before updating the pathfinding preview
			if has_node("_hover_timer"):
				get_node("_hover_timer").start()
			else:
				var timer = Timer.new()
				timer.name = "_hover_timer"
				timer.one_shot = true
				timer.wait_time = 0.1
				timer.connect("timeout", Callable(self, "_update_turn_based_pathfinding_preview"))
				add_child(timer)
				timer.start()

	# Add this to your _input() function
	if event is InputEventKey and event.pressed:
		if Input.is_action_pressed("debug_key"):
			print("Tiled debugview toggled")
			toggle_debug_view()

func get_tileset() -> TileSet:
	if primary_tilemap_layer and primary_tilemap_layer.tile_set:
		return primary_tilemap_layer.tile_set
	else:
		print("TileSet not found in primary_tilemap_layer")
		return null

func set_tiles_solid_from_groups() -> void:
	if not primary_tilemap_layer or not tileset:
		print("Cannot set tiles solid: No primary_tilemap_layer or tileset found")
		return
	
	if not astar_grid:
		print("Cannot set tiles solid: AStarGrid2D not initialized")
		return
	
	var used_cells = primary_tilemap_layer.get_used_cells()
	var custom_data_layer_name = "Solid" # Custom property to set as solid

	for cell_coords in used_cells:
		if not astar_grid.region.has_point(cell_coords):
			continue
		
		var tile_data: TileData = primary_tilemap_layer.get_cell_tile_data(cell_coords)

		if tile_data:
			var is_tile_solid = tile_data.get_custom_data(custom_data_layer_name)

			if typeof(is_tile_solid) == TYPE_BOOL and is_tile_solid == true:
				print("Tile set as solid at cell: ", cell_coords)
				astar_grid.set_point_solid(cell_coords, true)
			else:
				continue

# Add this to better separate turn-based and real-time input handling
func _process(_delta: float) -> void:
	# Update visuals only in turn-based mode
	if is_turn_based_mode():
		_update_turn_based_visuals()

# Add this function to show the movement range in turn-based mode
func show_movement_range() -> void:
	if not is_turn_based_mode() or not primary_tilemap_layer or not astar_grid:
		movement_range_indicator.visible = false
		return

	# Clear previous indicators
	movement_range_indicator.queue_redraw()
	highlight_tiles.clear()

	# Get player's current map position
	var player_local_pos = primary_tilemap_layer.to_local(player.global_position)
	var player_map_pos = primary_tilemap_layer.local_to_map(player_local_pos)

	# Find all tiles within SP range 
	highlight_tiles = get_tiles_in_range(player_map_pos, current_sp)
	movement_range_indicator.visible = true

	# Update visuals immediately
	movement_range_indicator.queue_redraw()

	print("PlayerMovement: Showing movement range with ", highlight_tiles.size(), " tiles in range for SP: ", current_sp)

# Calculate tiles within movement range
func get_tiles_in_range(start_pos: Vector2i, range_value: int) -> Array[Vector2i]:
	var tiles_in_range: Array[Vector2i] = []
	var visited: Dictionary = {}
	var queue: Array = []
	
	# Start with the starting position at distance 0
	queue.push_back({"pos": start_pos, "dist": 0})
	
	while not queue.is_empty():
		var current = queue.pop_front()
		var pos = current["pos"]
		var dist = current["dist"]
		
		# Skip if already visited or out of range
		if visited.has(pos) or dist > range_value:
			continue
			
		visited[pos] = dist
		
		# Add to tiles in range if walkable
		if astar_grid.region.has_point(pos) and not astar_grid.is_point_solid(pos):
			tiles_in_range.append(pos)
			
			# Add adjacent tiles if still within range
			if dist < range_value:
				queue.push_back({"pos": Vector2i(pos.x + 1, pos.y), "dist": dist + 1})
				queue.push_back({"pos": Vector2i(pos.x - 1, pos.y), "dist": dist + 1})
				queue.push_back({"pos": Vector2i(pos.x, pos.y + 1), "dist": dist + 1})
				queue.push_back({"pos": Vector2i(pos.x, pos.y - 1), "dist": dist + 1})
	
	return tiles_in_range

# Preview path as player hovers over tiles in turn-based mode
func _update_turn_based_pathfinding_preview() -> void:
	if not is_turn_based_mode() or not primary_tilemap_layer or not astar_grid:
		return
		
	current_path_tiles.clear()
	
	# Check if hover tile is within movement range
	if hover_tile in highlight_tiles:
		var player_local_pos = primary_tilemap_layer.to_local(player.global_position)
		var player_map_pos = primary_tilemap_layer.local_to_map(player_local_pos)
		
		var path = astar_grid.get_id_path(player_map_pos, hover_tile)
		
		# Limit by SP
		if path.size() - 1 <= current_sp:
			current_path_tiles = path
			
	movement_range_indicator.queue_redraw()

# Draw the movement range and path preview
func _update_turn_based_visuals() -> void:
	if not movement_range_indicator.visible:
		return
	
	# Connect to the _draw function if not already connected
	if not movement_range_indicator.is_connected("draw", Callable(self, "_draw_movement_indicators")):
		movement_range_indicator.draw.connect(_draw_movement_indicators)
	
	movement_range_indicator.queue_redraw()

# Draw function for movement range indicator
func _draw_movement_indicators() -> void:
	# Draw all tiles within range
	for tile_pos in highlight_tiles:
		var rect_pos = primary_tilemap_layer.map_to_local(tile_pos)
		rect_pos = primary_tilemap_layer.to_global(rect_pos)
		
		# Convert to movement_range_indicator's local coordinates
		rect_pos = movement_range_indicator.to_local(rect_pos)
		
		# Draw highlight
		var tile_size = get_tile_size()
		var half_size = Vector2(tile_size/2, tile_size/4)  # Adjusted for isometric
		
		# Draw different shapes based on whether it's in the current path
		if tile_pos in current_path_tiles:
			# Draw path tile
			var points = [
				rect_pos + Vector2(0, -half_size.y),          # Top
				rect_pos + Vector2(half_size.x, 0),           # Right
				rect_pos + Vector2(0, half_size.y),           # Bottom
				rect_pos + Vector2(-half_size.x, 0)           # Left
			]
			movement_range_indicator.draw_colored_polygon(points, turn_based_path_highlight_color)
		else:
			# Draw range tile
			var points = [
				rect_pos + Vector2(0, -half_size.y),          # Top
				rect_pos + Vector2(half_size.x, 0),           # Right
				rect_pos + Vector2(0, half_size.y),           # Bottom
				rect_pos + Vector2(-half_size.x, 0)           # Left
			]
			movement_range_indicator.draw_colored_polygon(points, turn_based_tile_highlight_color)

# Override the existing handle_game_mode_changed function
func handle_game_mode_changed(new_mode) -> void:
	"""React to game mode changes"""
	if is_turn_based_mode():
		print("PlayerMovement: Switched to TURN_BASED mode.")
		# Stop any current movement immediately
		cancel_current_movement()
		
		# Show movement range when entering turn-based mode
		show_movement_range()
		
	else: # REAL_TIME mode
		print("PlayerMovement: Switched to REAL_TIME mode.")
		# Hide turn-based visuals
		movement_range_indicator.visible = false
		highlight_tiles.clear()
		current_path_tiles.clear()

# Update existing _handle_turn_based_input to use our new visuals
func _handle_turn_based_input(event: InputEvent) -> void:
	# Get world coordinates for mouse click and player position
	var mouse_pos = player.get_global_mouse_position()
	var local_mouse_pos = primary_tilemap_layer.to_local(mouse_pos)
	var clicked_cell = primary_tilemap_layer.local_to_map(local_mouse_pos)

	# First check if the clicked cell is within the movement range
	if not clicked_cell in highlight_tiles:
		print("PlayerMovement: Clicked outside movement range")
		return
		
	var player_local_pos_for_map = primary_tilemap_layer.to_local(player.global_position)
	var current_map_coords = primary_tilemap_layer.local_to_map(player_local_pos_for_map)

	# Calculate path to the target cell
	var new_path = astar_grid.get_id_path(current_map_coords, clicked_cell)

	if new_path.size() <= 1: # No path or path is just the current tile
		print("PlayerMovement: No valid path found or target is current location.")
		_reset_path()
		return

	# Check if we have enough SP for the path
	var steps_needed = new_path.size() - 1
	if steps_needed > current_sp:
		print("PlayerMovement: Not enough SP to take this path")
		return

	# We have enough SP, so take the path
	path = new_path
	current_sp -= steps_needed
	print("PlayerMovement: Path initiated. Taking ", steps_needed, " steps. SP consumed: ", steps_needed, ". SP remaining: ", current_sp)
	emit_signal("sp_changed", current_sp)
	
	# Update visuals immediately
	highlight_tiles.clear()
	current_path_tiles.clear()
	movement_range_indicator.queue_redraw()
	
	_start_following_path()

# Handler for step_taken signal
func _on_step_taken(remaining_steps: int) -> void:
	# If we're in turn-based mode, update the movement range
	if is_turn_based_mode():
		# Only update visuals if we have tiles to highlight
		movement_range_indicator.queue_redraw()
		
		# If SP is 0, show no more movement possible
		if remaining_steps <= 0:
			highlight_tiles.clear()
			current_path_tiles.clear()
			movement_range_indicator.queue_redraw()
		else:
			# Otherwise update remaining range
			show_movement_range()

# Handler for sp_changed signal
func _on_sp_changed(new_sp: int) -> void:
	# Update the movement range when SP changes
	if is_turn_based_mode():
		show_movement_range()
		

# Check if we're in turn-based mode
func is_turn_based_mode() -> bool:
	if game_state_manager:
		return game_state_manager.is_turn_based()
	return false

# Cancel current movement
func cancel_current_movement() -> void:
	if current_phase == MovementPhase.FOLLOWING_PATH:
		_reset_path()

# Reset the current path
func _reset_path() -> void:
	path.clear()
	current_path_index = 0
	current_phase = MovementPhase.IDLE
	
	# Also clear visual path in turn-based mode
	if movement_range_indicator:
		current_path_tiles.clear()
		movement_range_indicator.queue_redraw()

# Start following the path
func _start_following_path() -> void:
	current_path_index = 0
	current_phase = MovementPhase.FOLLOWING_PATH
	emit_signal("movement_started")

# Get the tile size based on the tilemap
func get_tile_size() -> float:
	if primary_tilemap_layer and primary_tilemap_layer.tile_set:
		var tile_size = primary_tilemap_layer.tile_set.tile_size
		return min(tile_size.x, tile_size.y)  # Return smallest dimension to be safe
	return cell_size.x  # Default fallback size

# Debug function to visualize tile centers and entity positions
func draw_debug_markers(enable: bool = true) -> void:
	if not movement_range_indicator or not primary_tilemap_layer:
		return
	
	# Clear previous drawings
	movement_range_indicator.queue_redraw()
	
	if not enable:
		return
		
	# Connect to the draw function if not already connected
	if not movement_range_indicator.is_connected("draw", Callable(self, "_draw_debug_markers")):
		movement_range_indicator.draw.connect(_draw_debug_markers)
	
	movement_range_indicator.queue_redraw()

func _draw_debug_markers() -> void:
	# Highlight player position
	var player_pos = movement_range_indicator.to_local(player.global_position)
	movement_range_indicator.draw_circle(player_pos, 4, Color(1, 0, 0, 0.8))
	
	# Draw tile centers
	var visible_rect = Rect2(Vector2.ZERO, get_viewport().size)
	visible_rect = visible_rect.grow(100) # Add some margin
	
	# Draw grid cells in visible area
	var player_map_pos = primary_tilemap_layer.local_to_map(primary_tilemap_layer.to_local(player.global_position))
	for y in range(player_map_pos.y - 10, player_map_pos.y + 10):
		for x in range(player_map_pos.x - 10, player_map_pos.x + 10):
			var cell_pos = Vector2i(x, y)
			# Get world position of tile center
			var tile_center = primary_tilemap_layer.to_global(primary_tilemap_layer.map_to_local(cell_pos))
			# Convert to local coordinates of the debug display
			var local_tile_center = movement_range_indicator.to_local(tile_center)
			
			# Draw tile center
			movement_range_indicator.draw_circle(local_tile_center, 2, Color(0, 0.7, 1, 0.5))
			
			# Draw where the player's feet should be
			var feet_pos = local_tile_center + Vector2(0, y_offset)
			movement_range_indicator.draw_circle(feet_pos, 2, Color(0, 1, 0, 0.5))
			
			# Draw coordinate text
			movement_range_indicator.draw_string(
				ThemeDB.fallback_font, 
				local_tile_center + Vector2(5, -5), 
				str(cell_pos),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				8,
				Color(1, 1, 1, 0.7)
			)

var debug_view_enabled := false

func toggle_debug_view() -> void:
	if debug_view_enabled:
		debug_view_enabled = false
	else:
		debug_view_enabled = true
	draw_debug_markers(debug_view_enabled)
	print("Debug view ", "enabled" if debug_view_enabled else "disabled")
