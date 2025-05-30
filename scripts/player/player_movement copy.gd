extends Node

## Base movement system for the player character
## Handles pathfinding and actual movement execution for both real-time and turn-based modes

# Movement configuration
@export var speed: float = 100.0
@export var snap_distance: float = 5.0
@export var y_offset: float = 16.0 # For isometric view, to sink player visually

# Node dependencies
@export var player: CharacterBody2D 
var primary_tilemap_layer: TileMapLayer
var ground_layers: Array[TileMapLayer] = []
var obstacle_layers: Array[TileMapLayer] = []
var filter_groups: Array[String] = ["obstacle","interactable","NPC"]

# Obstacles detected in the current level
var obstacles: Array = []

# Pathfinding
var astar_grid: AStarGrid2D
enum MovementPhase { IDLE, FOLLOWING_PATH }
var current_phase = MovementPhase.IDLE
var current_path: Array[Vector2i] = []
var current_path_index: int = 0

# Position targets
var final_target_world_position: Vector2
var current_step_target_world_position: Vector2

# Reference to GameStateManager
var game_state_manager: Node

# Signals
signal path_completed
signal movement_started
signal step_taken(remaining_steps: int)
signal sp_changed(new_sp: int)

# Player resources
var sp: int = 4 # Step Points - limited movement resource in turn-based mode

func _ready() -> void:
	if not player:
		player = get_parent() as CharacterBody2D
		if not player:
			printerr("PlayerMovement: Parent is not a CharacterBody2D. Movement system needs to be a child of the player.")
			set_process(false)
			set_physics_process(false)
			return
			
	final_target_world_position = player.global_position
	current_step_target_world_position = player.global_position
	
	# Get the GameStateManager singleton
	game_state_manager = get_node_or_null("/root/GameStateManager")
	if not game_state_manager:
		printerr("PlayerMovement: GameStateManager autoload not found.")

func setup(p_tilemap: TileMapLayer, p_player: CharacterBody2D) -> void:
	player = p_player
	primary_tilemap_layer = p_tilemap
	
	print("PlayerMovement: Setting up with tilemap: ", primary_tilemap_layer.name)
	
	# Clear existing arrays to avoid duplicates if setup is called multiple times
	ground_layers.clear()
	obstacle_layers.clear()
	
	# Now gather obstacle nodes by group rather than by layer
	obstacles = []
	for group in filter_groups:
		var nodes = get_tree().get_nodes_in_group(group)
		print("PlayerMovement: Found ", nodes.size(), " nodes in group: ", group)
		
		# Add any new obstacles to our tracking array
		for node in nodes:
			if node != player and not obstacles.has(node):
				obstacles.append(node)
				
	# Handle ground/walkable areas
	var map_parent = primary_tilemap_layer.get_parent()
	if map_parent:
		for i in range(map_parent.get_child_count()):
			var child = map_parent.get_child(i)
			if child is TileMapLayer:
				var child_name = String(child.name)
				if child_name.begins_with("Ground"):
					ground_layers.append(child)
	
	# Ensure we have at least one ground layer
	if ground_layers.is_empty():
		ground_layers.append(primary_tilemap_layer)
	
	# Initialize the AStar grid for pathfinding
	_initialize_astar()
	
	print("PlayerMovement: Setup complete. ", 
		  obstacles.size(), " obstacles tracked. ",
		  ground_layers.size(), " ground layers found.")

func initialize(p_tilemap: TileMapLayer, p_ground_layers: Array, p_obstacle_layers: Array) -> void:
	"""Initialize the movement system with required tilemap references"""
	primary_tilemap_layer = p_tilemap
	ground_layers = p_ground_layers
	obstacle_layers = p_obstacle_layers
	_initialize_astar()
	
func _initialize_astar() -> void:
	astar_grid = AStarGrid2D.new()
	
	# Determine map bounds by combining the used_rects of all layers
	var map_rect = Rect2i()
	if not ground_layers.is_empty():
		map_rect = ground_layers[0].get_used_rect()
		for i in range(1, ground_layers.size()):
			map_rect = map_rect.merge(ground_layers[i].get_used_rect())
		for obstacle_layer in obstacle_layers:
			map_rect = map_rect.merge(obstacle_layer.get_used_rect())
	else:
		printerr("PlayerMovement: Cannot initialize AStar: No ground layers to determine map bounds.")
		return

	if map_rect.size.x == 0 or map_rect.size.y == 0:
		print("PlayerMovement: TileMap appears to be empty or very small. Used rect: ", map_rect)
		astar_grid.region = Rect2i(0,0,1,1) # Default small region to avoid errors
	else:
		astar_grid.region = map_rect
	
	# Configure astar grid properties
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER # 4-directional movement
	astar_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar_grid.update()

	# Mark unwalkable cells as solid in the AStar grid
	var solid_points_count = 0
	for y in range(map_rect.position.y, map_rect.end.y):
		for x in range(map_rect.position.x, map_rect.end.x):
			var cell = Vector2i(x, y)
			if not _is_cell_walkable(cell):
				astar_grid.set_point_solid(cell, true)
				solid_points_count += 1
			
	print("PlayerMovement: AStar grid initialized. Region: ", astar_grid.region, 
		  ". Total solid points set: ", solid_points_count)

func _is_cell_walkable(map_coords: Vector2i) -> bool:
	print("Checking walkability for cell: ", map_coords)
	# Check if there's at least one ground tile on any ground layer
	var has_ground_tile_on_any_ground_layer = false
	for ground_layer in ground_layers:
		if ground_layer.get_cell_source_id(map_coords) != -1:
			has_ground_tile_on_any_ground_layer = true
			break
	if not has_ground_tile_on_any_ground_layer:
		print("  No ground tile found on any ground layer for cell: ", map_coords)
		return false # Must have a ground tile on at least one ground layer

	# Only use group-based checks for obstacles/interactables/NPCs
	if path_has_obstacles([map_coords], filter_groups):
		print("  Cell blocked by group-based obstacle at: ", map_coords)
		return false
	var path_quality = evaluate_path_quality([map_coords])
	if path_quality.has_obstacles or path_quality.tight_spaces > 2:
		print("  Cell failed path quality check: ", path_quality)
		return false
	print("  Cell is walkable: ", map_coords)
	return true

func handle_input(event: InputEvent) -> void:
	"""Central input handler - delegates to mode-specific handlers"""
	if not primary_tilemap_layer or not astar_grid or not player:
		return
		
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed()):
		return
		
	if is_turn_based_mode():
		_handle_turn_based_input(event)
	else:
		_handle_real_time_input(event)

func _handle_turn_based_input(event: InputEvent) -> void:
	# Get world coordinates for mouse click and player position
	var mouse_pos = player.get_global_mouse_position()
	var local_mouse_pos = primary_tilemap_layer.to_local(mouse_pos)
	var clicked_cell = primary_tilemap_layer.local_to_map(local_mouse_pos)

	var player_local_pos_for_map = primary_tilemap_layer.to_local(player.global_position - Vector2(0, y_offset))
	var current_map_coords = primary_tilemap_layer.local_to_map(player_local_pos_for_map)

	# Validate clicked cell and current position
	if not astar_grid.region.has_point(clicked_cell) or astar_grid.is_point_solid(clicked_cell):
		print("PlayerMovement: Clicked on an unwalkable or out-of-bounds tile: ", clicked_cell)
		return
	if not astar_grid.region.has_point(current_map_coords):
		print("PlayerMovement: Current position is out of A* bounds: ", current_map_coords)
		return

	# Calculate path to the target cell
	var new_path = astar_grid.get_id_path(current_map_coords, clicked_cell)

	if new_path.size() <= 1: # No path or path is just the current tile
		print("PlayerMovement: No valid path found or target is current location. Path size: ", new_path.size())
		_reset_path()
		return

	# TURN-BASED MODE: SP matters
	if sp <= 0:
		print("PlayerMovement (Turn-Based): No SP left to move.")
		_reset_path()
		return

	var num_steps_in_full_path = new_path.size() - 1
	var steps_to_take = min(num_steps_in_full_path, sp)

	if steps_to_take <= 0: 
		print("PlayerMovement (Turn-Based): Calculated steps to take is zero or less. Path size: ", new_path.size(), ", SP: ", sp)
		_reset_path()
		return
	
	# Take only the steps we can afford with our SP
	current_path = new_path.slice(0, steps_to_take + 1)
	sp -= steps_to_take
	print("PlayerMovement (Turn-Based): Path initiated. Taking ", steps_to_take, " steps. SP consumed: ", steps_to_take, ". SP remaining: ", sp)
	emit_signal("sp_changed", sp)
	
	_start_following_path()

func _handle_real_time_input(event: InputEvent) -> void:
	# Get world coordinates for mouse click and player position
	var mouse_pos = player.get_global_mouse_position()
	var local_mouse_pos = primary_tilemap_layer.to_local(mouse_pos)
	var clicked_cell = primary_tilemap_layer.local_to_map(local_mouse_pos)

	var player_local_pos_for_map = primary_tilemap_layer.to_local(player.global_position - Vector2(0, y_offset))
	var current_map_coords = primary_tilemap_layer.local_to_map(player_local_pos_for_map)

	# Validate clicked cell and current position
	if not astar_grid.region.has_point(clicked_cell) or astar_grid.is_point_solid(clicked_cell):
		print("PlayerMovement: Clicked on an unwalkable or out-of-bounds tile: ", clicked_cell)
		return
	if not astar_grid.region.has_point(current_map_coords):
		print("PlayerMovement: Current position is out of A* bounds: ", current_map_coords)
		return

	# Calculate path to the target cell
	var new_path = astar_grid.get_id_path(current_map_coords, clicked_cell)

	if new_path.size() <= 1: # No path or path is just the current tile
		print("PlayerMovement: No valid path found or target is current location. Path size: ", new_path.size())
		_reset_path()
		return

	# REAL-TIME MODE: Take the full path
	var num_steps_in_full_path = new_path.size() - 1
	if num_steps_in_full_path <= 0:
		print("PlayerMovement (Real-Time): Path is zero or less steps. Path size: ", new_path.size())
		_reset_path()
		return
	
	current_path = new_path # Take the full path
	print("PlayerMovement (Real-Time): Path initiated. Taking ", num_steps_in_full_path, " steps. SP not consumed.")
	
	_start_following_path()

func _start_following_path() -> void:
	"""Initialize path following with the current path"""
	current_path_index = 0
	current_phase = MovementPhase.FOLLOWING_PATH
	emit_signal("movement_started")
	
	var last_map_coord = current_path[current_path.size() - 1]
	final_target_world_position = primary_tilemap_layer.map_to_local(last_map_coord) + Vector2(0, y_offset)
	final_target_world_position = primary_tilemap_layer.to_global(final_target_world_position)
	
	var next_map_coord = current_path[current_path_index] # This is the starting point of the path
	current_step_target_world_position = primary_tilemap_layer.map_to_local(next_map_coord) + Vector2(0, y_offset)
	current_step_target_world_position = primary_tilemap_layer.to_global(current_step_target_world_position)

func _reset_path() -> void:
	"""Reset path and movement state"""
	current_path.clear()
	current_path_index = 0
	current_phase = MovementPhase.IDLE

func process_movement() -> Vector2:
	"""Process movement and return the calculated velocity for the player"""
	if not player:
		return Vector2.ZERO
	
	if is_turn_based_mode():
		return _process_turn_based_movement()
	else:
		return _process_real_time_movement()

func _process_turn_based_movement() -> Vector2:
	# In turn-based mode, stop player movement and ensure idle animation
	if player.velocity != Vector2.ZERO:
		return Vector2.ZERO
	
	# In the future, this could handle animated movement between grid cells when it's the player's turn
	return Vector2.ZERO

func _process_real_time_movement() -> Vector2:
	if current_phase == MovementPhase.IDLE:
		# Snap to final target if close enough
		if player.global_position.distance_squared_to(final_target_world_position) < snap_distance * snap_distance:
			if player.global_position != final_target_world_position:
				player.global_position = final_target_world_position
		return Vector2.ZERO

	elif current_phase == MovementPhase.FOLLOWING_PATH:
		if current_path.is_empty() or current_path_index >= current_path.size():
			current_phase = MovementPhase.IDLE
			player.global_position = final_target_world_position # Snap to the final destination
			print("PlayerMovement: Path completed or invalid.")
			emit_signal("path_completed")
			return Vector2.ZERO
	
		if player.global_position.distance_squared_to(current_step_target_world_position) < snap_distance * snap_distance:
			player.global_position = current_step_target_world_position # Snap to current waypoint
			current_path_index += 1
			emit_signal("step_taken", current_path.size() - current_path_index)

			if current_path_index >= current_path.size():
				current_phase = MovementPhase.IDLE
				player.global_position = final_target_world_position # Ensure snapped to final target
				print("PlayerMovement: Reached end of path.")
				emit_signal("path_completed")
				return Vector2.ZERO
			else:
				# Set next waypoint
				var next_map_coord = current_path[current_path_index]
				current_step_target_world_position = primary_tilemap_layer.map_to_local(next_map_coord) + Vector2(0, y_offset)
				current_step_target_world_position = primary_tilemap_layer.to_global(current_step_target_world_position)
				# Calculate velocity for next segment immediately
				return player.global_position.direction_to(current_step_target_world_position) * speed
		else:
			# Move towards current waypoint
			return player.global_position.direction_to(current_step_target_world_position) * speed
	
	return Vector2.ZERO

func refresh_resources() -> void:
	"""Reset step points and other movement resources"""
	sp = 4 # Reset to default value
	emit_signal("sp_changed", sp)
	print("PlayerMovement: Resources refreshed. SP set to: ", sp)

func handle_game_mode_changed(new_mode) -> void:
	"""React to game mode changes"""
	if is_turn_based_mode():
		print("PlayerMovement: Switched to TURN_BASED mode.")
		# Stop any current movement immediately
		current_phase = MovementPhase.IDLE
		
	else: # REAL_TIME mode
		print("PlayerMovement: Switched to REAL_TIME mode.")

func is_turn_based_mode() -> bool:
	"""Check if we're currently in turn-based mode"""
	if game_state_manager:
		return game_state_manager.is_turn_based()
	return false
	
func cancel_current_movement() -> void:
	"""Cancel any ongoing movement"""
	if current_phase == MovementPhase.FOLLOWING_PATH:
		_reset_path()
		
func get_remaining_sp() -> int:
	"""Get the current SP value"""
	return sp

func set_sp(new_value: int) -> void:
	"""Set SP to a specific value"""
	sp = new_value
	emit_signal("sp_changed", sp)
	
func get_tile_size() -> float:
	# Get the approximate tile size based on primary tilemap
	if primary_tilemap_layer and primary_tilemap_layer.tile_set:
		var tile_size = primary_tilemap_layer.tile_set.tile_size
		return min(tile_size.x, tile_size.y)  # Return smallest dimension to be safe
	return 32.0  # Default fallback size
	
func set_target_position(pos: Vector2) -> void:
	"""Set a specific target position, useful for custom movement like going to an NPC"""
	if not primary_tilemap_layer or not astar_grid:
		return

	# Find path using our new function
	var new_world_path = find_path(player.global_position, pos)

	if new_world_path.size() <= 1:
		print("PlayerMovement: No valid path to target position")
		return
	
	# Convert world path to grid path for internal use
	var new_path = []
	for world_pos in new_world_path:
		var local_pos = primary_tilemap_layer.to_local(world_pos - Vector2(0, y_offset))
		var map_coord = primary_tilemap_layer.local_to_map(local_pos)
		new_path.append(map_coord)

	# Process path based on current game mode
	if is_turn_based_mode():
		# Turn-based mode - limit by SP
		var steps_to_take = min(new_path.size() - 1, sp)
		if steps_to_take <= 0:
			return

		current_path = new_path.slice(0, steps_to_take + 1)
		sp -= steps_to_take
		emit_signal("sp_changed", sp)
	else:
		# Real-time mode - take full path
		current_path = new_path

	_start_following_path()

func find_nearest_walkable_tile(map_coords: Vector2i) -> Vector2i:
	"""Find the nearest walkable tile to the given coordinates"""
	# Start with the given coordinates
	var checked = {}
	var queue = [map_coords]
	var max_search_distance = 10  # Limit search radius
	
	while not queue.is_empty() and max_search_distance > 0:
		var current = queue.pop_front()
		
		if checked.has(current):
			continue
			
		checked[current] = true
		
		# Check if this tile is walkable
		if astar_grid.region.has_point(current) and not astar_grid.is_point_solid(current):
			return current
			
		# Add neighboring tiles to the queue
		queue.append(Vector2i(current.x + 1, current.y))
		queue.append(Vector2i(current.x - 1, current.y))
		queue.append(Vector2i(current.x, current.y + 1))
		queue.append(Vector2i(current.x, current.y - 1))
		
		max_search_distance -= 1
		
	# If no walkable tile found, return original (though it's not walkable)
	return map_coords

func path_has_obstacles(path: Array[Vector2i], group_names: Array = []) -> bool:
	# Check if the given path encounters any obstacles or objects in specified groups
	for cell in path:
		if astar_grid.is_point_solid(cell):
			return true
		# Convert cell to world position
		var world_pos = primary_tilemap_layer.to_global(primary_tilemap_layer.map_to_local(cell) + Vector2(0, y_offset))
		for group in group_names:
			for node in get_tree().get_nodes_in_group(group):
				var _node_pos = null
				if node.has_method("get_global_position"):
					_node_pos = node.get_global_position()
				elif node.has_method("global_position"):
					_node_pos = node.global_position
				else:
					continue
				# Check if node is close enough to the cell's world position
				if _node_pos and _node_pos.distance_to(world_pos) < get_tile_size() * 0.5:
					return true
	return false

func evaluate_path_quality(path: Array[Vector2i]) -> Dictionary:
	# Evaluate the quality of a path, checking for obstacles and tight spaces
	# var obstacles_count = 0
	# var tight_spaces = 0
	var result = {}
	result["has_obstacles"] = false
	result["obstacles_count"] = 0
	result["tight_spaces"] = 0
	
	for cell in path:
		if astar_grid.is_point_solid(cell):
			result["has_obstacles"] = true
			result["obstacles_count"] += 1
			
		# Count tiles with adjacent obstacles as "tight spaces"
		var adjacent_obstacles = 0
		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var adj = cell + dir
			if not astar_grid.region.has_point(adj) or astar_grid.is_point_solid(adj):
				adjacent_obstacles += 1
		
		if adjacent_obstacles >= 2:
			result["tight_spaces"] += 1
			
	return result

func is_position_walkable(pos: Vector2) -> bool:
	# Convert world position to tile position
	var tile_pos = primary_tilemap_layer.local_to_map(primary_tilemap_layer.to_local(pos))

	# Check if any node in filter_groups is on this tile
	var world_tile_center = primary_tilemap_layer.to_global(primary_tilemap_layer.map_to_local(tile_pos) + Vector2(0, y_offset))
	for group in filter_groups:
		for node in get_tree().get_nodes_in_group(group):
			var node_pos = null
			if node.has_method("get_global_position"):
				node_pos = node.get_global_position()
			elif node.has_method("global_position"):
				node_pos = node.global_position
			else:
				continue
			if node_pos and node_pos.distance_to(world_tile_center) < get_tile_size() * 0.5:
				return false

	# Optionally, check for physics collisions at the position
	var space_state = get_viewport().get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = pos
	query.collision_mask = 0xFFFFFFFF  # Check all collision layers
	var result = space_state.intersect_point(query)

	for collision in result:
		var collider = collision["collider"]
		# If the collider is not the player and has a collision shape
		if collider != get_parent() and (collider.get_node_or_null("CollisionShape2D") or 
										  collider.get_node_or_null("CollisionPolygon2D")):
			return false

	return true

# In your PlayerMovement.gd script, update the find_path method or similar
func find_path(start_pos: Vector2, end_pos: Vector2) -> Array:
	# Convert world positions to tilemap coordinates
	var start_tile = primary_tilemap_layer.local_to_map(primary_tilemap_layer.to_local(start_pos))
	var end_tile = primary_tilemap_layer.local_to_map(primary_tilemap_layer.to_local(end_pos))
	
	# Make sure the end position isn't occupied by an obstacle
	if not is_position_walkable(end_pos):
		print("PlayerMovement: End position is not walkable, finding nearby position")
		
		# Try to find a nearby walkable position
		var directions = [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP, 
			Vector2(1,1), Vector2(-1,1), Vector2(1,-1), Vector2(-1,-1)]
		
		for direction in directions:
			var new_end_pos = end_pos + direction * get_tile_size()
			if is_position_walkable(new_end_pos):
				end_pos = new_end_pos
				end_tile = primary_tilemap_layer.local_to_map(primary_tilemap_layer.to_local(new_end_pos))
				print("PlayerMovement: Found walkable position at", new_end_pos)
				break

	# Ensure both positions are within grid bounds
	if not astar_grid.region.has_point(start_tile) or not astar_grid.region.has_point(end_tile):
		print("PlayerMovement: Start or end position out of bounds")
		return []
		
	if astar_grid.is_point_solid(start_tile) or astar_grid.is_point_solid(end_tile):
		print("PlayerMovement: Start or end position is solid/unwalkable")
		return []
	
	# Calculate path using AStar
	var path_ids = astar_grid.get_id_path(start_tile, end_tile)
	
	if path_ids.size() <= 1:
		print("PlayerMovement: No path found or path is trivial")
		return []
		
	# Convert path from grid coordinates to world coordinates
	var world_path = []
	for cell in path_ids:
		var world_pos = primary_tilemap_layer.to_global(primary_tilemap_layer.map_to_local(cell) + Vector2(0, y_offset))
		world_path.append(world_pos)
		
	print("PlayerMovement: Found path with ", world_path.size(), " points")
	return world_path
