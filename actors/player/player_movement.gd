extends Node2D

@export var cell_size: Vector2 = Vector2(32, 32)
@export var speed: float = 100.0
@export var y_offset: float = 16.0 # For isometric view, to sink player visually

# TileMap references
var primary_tilemap_layer: TileMapLayer = null
var tileset: TileSet = null

# References
var game_state_manager: Node
var player
var stats_component 

# Movement state
enum MovementPhase { IDLE, FOLLOWING_PATH }
var current_phase = MovementPhase.IDLE
var current_path_index: int = 0
var final_target_world_position: Vector2
var current_step_target_world_position: Vector2
var blocking_groups = ["NPC", "Solid", "Obstacle", "blocking_tilemap", "Container"]
var freeroam_target_position: Vector2

# Signals
signal path_completed
signal movement_started
signal step_taken(remaining_steps: int)
signal sp_changed(current_sp, max_sp)

var astar_grid = AStarGrid2D.new()
var grid_size

var start = Vector2.ZERO
var end = Vector2.ZERO
var path = []

# Turn-based movement variables
@export var turn_based_tile_highlight_color: Color = Color(0.2, 0.8, 0.3, 0.5)
@export var turn_based_path_highlight_color: Color = Color(0.3, 0.6, 0.9, 0.4)
@export var turn_based_invalid_tile_color: Color = Color(0.9, 0.3, 0.2, 0.5)
@export var aoe_preview_color: Color = Color(0.8, 0.5, 0.2, 0.6)
@export var ability_range_color: Color = Color(0.8, 0.5, 0.2, 0.6)

# Visual aids for turn-based mode
var highlight_tiles: Array[Vector2i] = []
var current_path_tiles: Array[Vector2i] = []
var hover_tile: Vector2i = Vector2i(-1, -1)
var movement_range_indicator: Node2D

var is_in_targeting_mode: bool = false
var valid_target_tiles: Array[Vector2i] = []
var aoe_preview_tiles: Array[Vector2i] = []
var target_ability: AbilityData = null
var last_hoverd_tile: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
	await owner.ready
	# Get player reference from parent
	player = owner as CharacterBody2D
	if not player:
		printerr("PlayerMovement: Parent is not a CharacterBody2D. Movement system needs to be a child of the player.")
		return

	freeroam_target_position = player.global_position

	stats_component = player.stats
	if not stats_component:
		printerr("PlayerMovement: Player does not have a Stats component. Movement system requires Stats for SP management.")
	else:
		if not stats_component.is_connected("sp_changed", Callable(self, "_on_sp_changed")):
			stats_component.sp_changed.connect(_on_sp_changed)
		if is_turn_based_mode():
			show_movement_range()
	
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
	if not primary_tilemap_layer:
		print("Cannot initialize grid: No primary_tilemap_layer set")
		return
	
	if tileset == null:
		tileset = primary_tilemap_layer.tile_set
		if tileset == null:
			print("Cannot initialize grid: No tileset found in primary_tilemap_layer")
			return

	# Now you can use the primary_tilemap_layer to determine grid size if needed
	grid_size = Rect2i(Vector2i.ZERO, Vector2i(100, 100)) 
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

func follow_path() -> void:
	if not player: # Ensure player node is valid
		current_phase = MovementPhase.IDLE # Safety: stop if player is lost
		return

	# If path is empty, movement is done or not started.
	if path.is_empty():
		if player: # Check player again before setting velocity
			player.velocity = Vector2.ZERO
		
		if current_phase == MovementPhase.FOLLOWING_PATH: # Was actively following
			current_phase = MovementPhase.IDLE
			emit_signal("path_completed")
			if is_turn_based_mode():
				show_movement_range() # Update visuals like movement range
		return
		
	var next_target_waypoint: Vector2 = path[0]
	var distance_to_target: float = player.global_position.distance_to(next_target_waypoint)
	
	# Check if player reached the current waypoint
	if distance_to_target < 1.5: # Using a small threshold, adjust if needed
		player.global_position = next_target_waypoint # Snap to waypoint
		path.remove_at(0) # Remove reached waypoint
		
		# Only emit step_taken signal but don't deduct SP again since we already did in _handle_turn_based_input
		if is_turn_based_mode():
			emit_signal("step_taken") # Emit signal that we've taken a step

		# If path becomes empty after removing current waypoint
		if path.is_empty():
			player.velocity = Vector2.ZERO # Stop movement
			current_phase = MovementPhase.IDLE # Set state to idle
			emit_signal("path_completed")
			if is_turn_based_mode():
				show_movement_range() # Update visuals
			return # Movement for this frame ends here
		
		# If path is not empty, update next_target_waypoint for this frame's move
		next_target_waypoint = path[0]
	

	# Move player towards the (new) next_target_waypoint.
	if not path.is_empty():
		player.velocity = player.global_position.direction_to(next_target_waypoint) * speed
	else:
		# This case should ideally be handled by the path empty check above.
		player.velocity = Vector2.ZERO

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
func _process(_delta: float):
	if not is_in_targeting_mode and not is_turn_based_mode():
		return  # Skip processing if not in targeting or turn-based mode

	var current_tile = primary_tilemap_layer.local_to_map(get_global_mouse_position())
	if current_tile == last_hoverd_tile:
		return

	last_hoverd_tile = current_tile

	if is_in_targeting_mode:
		var mouse_tile = primary_tilemap_layer.local_to_map(get_global_mouse_position())
		_update_targeting_preview(mouse_tile)
		return
	elif is_turn_based_mode():
		_update_turn_based_visuals(current_tile)

	

# Add this function to show the movement range in turn-based mode
func show_movement_range():
	if not is_turn_based_mode() or not primary_tilemap_layer or not astar_grid:
		movement_range_indicator.visible = false
		return

	# Clear previous indicators
	movement_range_indicator.queue_redraw()
	highlight_tiles.clear()

	# Get player's current map position and resources
	var player_local_pos = primary_tilemap_layer.to_local(player.global_position)
	var player_map_pos = primary_tilemap_layer.local_to_map(player_local_pos)
	var current_sp = stats_component.get_current_sp()

	# Find all tiles within SP range 
	highlight_tiles = get_tiles_in_range(player_map_pos, current_sp)
	movement_range_indicator.visible = true

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
	
	if highlight_tiles.has(hover_tile):
		var player_local_pos = primary_tilemap_layer.to_local(player.global_position)
		var player_map_pos = primary_tilemap_layer.local_to_map(player_local_pos)
		var path_ids = astar_grid.get_id_path(player_map_pos, hover_tile)

		if path_ids.size() - 1 <= stats_component.get_current_sp() and path_ids.size() > 0:
			current_path_tiles = path_ids
	
	movement_range_indicator.queue_redraw()

# Draw the movement range and path preview
func _update_turn_based_visuals(mouse_tile_pos: Vector2i):
	current_path_tiles.clear()

	if not primary_tilemap_layer or not astar_grid:
		return

	if mouse_tile_pos in highlight_tiles:
		var player_tile_pos = primary_tilemap_layer.local_to_map(player.global_position)
		var new_path = astar_grid.get_id_path(player_tile_pos, mouse_tile_pos)
		var steps_needed = new_path.size() - 1

		if steps_needed <= stats_component.get_current_sp() and steps_needed > 0:
			current_path_tiles = new_path
		
	movement_range_indicator.queue_redraw()
	

# Draw function for movement range indicator
func _draw_tile_highlight(tile_pos: Vector2i, color: Color):
	if not primary_tilemap_layer:
		return
	
	var local_tile_center = primary_tilemap_layer.map_to_local(tile_pos)

	var half_size = cell_size / 2.0
	var points = PackedVector2Array([
		local_tile_center + Vector2(0, -half_size.y),          # Top
		local_tile_center + Vector2(half_size.x, 0),           # Right
		local_tile_center + Vector2(0, half_size.y),           # Bottom
		local_tile_center + Vector2(-half_size.x, 0)           # Left
	])

	draw_colored_polygon(points, color)

func _draw_movement_indicators():
	if is_in_targeting_mode:
		for tile in valid_target_tiles:
			_draw_tile_highlight(tile, ability_range_color)

		for tile in aoe_preview_tiles:
			_draw_tile_highlight(tile, aoe_preview_color)

	elif is_turn_based_mode():
		# Draw all tiles within range
		for tile in highlight_tiles:
			_draw_tile_highlight(tile, turn_based_tile_highlight_color)
		
		for tile in current_path_tiles:
			_draw_tile_highlight(tile, turn_based_path_highlight_color)
	
	# # Draw all tiles within range
	# for tile_pos in highlight_tiles:
	# 	var rect_pos = primary_tilemap_layer.map_to_local(tile_pos)
	# 	rect_pos = primary_tilemap_layer.to_global(rect_pos)
		
	# 	# Convert to movement_range_indicator's local coordinates
	# 	rect_pos = movement_range_indicator.to_local(rect_pos)
		
	# 	# Draw highlight
	# 	var tile_size = get_tile_size()
	# 	var half_size = Vector2(tile_size/2, tile_size/4)  # Adjusted for isometric
		
	# 	# Draw different shapes based on whether it's in the current path
	# 	if tile_pos in current_path_tiles:
	# 		# Draw path tile
	# 		var points = [
	# 			rect_pos + Vector2(0, -half_size.y),          # Top
	# 			rect_pos + Vector2(half_size.x, 0),           # Right
	# 			rect_pos + Vector2(0, half_size.y),           # Bottom
	# 			rect_pos + Vector2(-half_size.x, 0)           # Left
	# 		]
	# 		movement_range_indicator.draw_colored_polygon(points, turn_based_path_highlight_color)
	# 	else:
	# 		# Draw range tile
	# 		var points = [
	# 			rect_pos + Vector2(0, -half_size.y),          # Top
	# 			rect_pos + Vector2(half_size.x, 0),           # Right
	# 			rect_pos + Vector2(0, half_size.y),           # Bottom
	# 			rect_pos + Vector2(-half_size.x, 0)           # Left
	# 		]
	# 		movement_range_indicator.draw_colored_polygon(points, turn_based_tile_highlight_color)

# Override the existing handle_game_mode_changed function
func _handle_game_mode_changed(new_mode):
	if new_mode == GameStateManager.GameMode.TURN_BASED:
		print("PlayerMovement: Switching to turn-based mode")

		var current_scene = get_tree().current_scene
		if current_scene:
			primary_tilemap_layer = current_scene.find_child("Ground", true, false) as TileMapLayer
			
		if not primary_tilemap_layer:
			printerr("PlayerMovement: PrimaryTileMapLayer not found in scene root. Movement system requires a TileMapLayer.")
			return

		initialize_grid()
		show_movement_range()

	elif new_mode == GameStateManager.GameMode.REAL_TIME:
		print("PlayerMovement: Switching to real-time mode")
		if movement_range_indicator:
			movement_range_indicator.visible = false
		path.clear()

func handle_freeroam_movement(target_position: Vector2):
	self.freeroam_target_position = target_position

func set_movement_target(target_position: Vector2):
	if not is_turn_based_mode():
		handle_freeroam_movement(target_position)
	else:
		handle_grid_movement(target_position)

func handle_grid_movement(target_position: Vector2):
	if not stats_component or not primary_tilemap_layer:
		print("PlayerMovement: No Stats component or TileMapLayer found. Cannot handle grid movement.")
		return

	var target_cell = primary_tilemap_layer.local_to_map(target_position)
	if not target_cell in highlight_tiles:
		print("PlayerMovement: Clicked outside movement range")
		return

	var player_cell = primary_tilemap_layer.local_to_map(player.global_position)
	var new_path = astar_grid.get_id_path(player_cell, target_cell)

	if new_path.size() <= 1: # No path or path is just the current tile
		print("PlayerMovement: No valid path found or target is current location.")
		return
	
	var steps_needed = new_path.size() - 1
	var sp_cost = steps_needed  # 1 SP per tile

	if stats_component.spend_sp(sp_cost):
		path.clear()
		for cell_id in new_path:
			path.append(primary_tilemap_layer.to_global(primary_tilemap_layer.map_to_local(cell_id)))
		_start_following_path()

func _physics_process(_delta: float):
	if not is_instance_valid(player):
		return

	if is_turn_based_mode():
		if path.size() > 0:
			follow_path()
		else:
			player.velocity = Vector2.ZERO  # Stop movement if no path
	else:
		var distance_to_target = player.global_position.distance_to(freeroam_target_position)
		if distance_to_target < 1.5:  
			player.velocity = Vector2.ZERO
		else:
			var direction = player.global_position.direction_to(freeroam_target_position)
			player.velocity = direction * speed

# Handler for sp_changed signal
func _on_sp_changed(_new_sp: int, _max_sp: int) -> void:
	# Update the movement range visuals whenever SP changes from the Stats component
	print("PlayerMovement: SP changed to %s, max SP is %s" % [_new_sp, _max_sp])
	if is_turn_based_mode():
		print("PlayerMovement: Detected SP change from Stats. New SP: %s. Updating movement range." % _new_sp)
		show_movement_range() 
		_update_turn_based_pathfinding_preview() 
		if movement_range_indicator: movement_range_indicator.queue_redraw()

# Ensure _on_step_taken exists if connected in _ready
func _on_step_taken() -> void:
	if is_turn_based_mode():
		if movement_range_indicator: movement_range_indicator.queue_redraw()
		

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

# Function for targeting mode for abilities
func enter_targeting_mode(ability: AbilityData):
	if not is_turn_based_mode():
		print("PlayerMovement: Cannot enter targeting mode in real-time mode.")
		return
	
	if not ability:
		print("PlayerMovement: No ability provided for targeting mode.")
		return
	
	if is_in_targeting_mode:
		print("PlayerMovement: Already in targeting mode.")
		stop_targeting_mode()

	is_in_targeting_mode = true
	target_ability = ability
	var player_local_pos = primary_tilemap_layer.to_local(player.global_position)
	var player_map_pos = primary_tilemap_layer.local_to_map(player_local_pos)
	valid_target_tiles = get_valid_target_tiles(player_map_pos, ability)

	movement_range_indicator.queue_redraw()

func get_valid_target_tiles(start_tile: Vector2i, ability) -> Array[Vector2i]:
	var valid_tiles: Array[Vector2i] = []
	# calculate valid tile based on the player position and minimum and maximum ability range
	if not primary_tilemap_layer or not astar_grid:
		print("PlayerMovement: No primary_tilemap_layer or astar_grid found. Cannot get valid target tiles.")
		return valid_tiles

	var max_range = ability.max_range if ability else 0
	var min_range = ability.min_range if ability else 0
	for tile in astar_grid.get_tiles_in_range(start_tile, max_range):
		if tile.distance_to(start_tile) >= min_range:
			valid_tiles.append(tile)

	print("PlayerMovement: Valid target tiles calculated for ability ", ability.ability_name, ": ", valid_tiles)
	return valid_tiles

func stop_targeting_mode():
	is_in_targeting_mode = false
	target_ability = null
	valid_target_tiles.clear()
	aoe_preview_tiles.clear()
	movement_range_indicator.queue_redraw()

func _update_targeting_preview(mouse_tile_pos: Vector2i):
	aoe_preview_tiles.clear()

	if mouse_tile_pos in valid_target_tiles:
		aoe_preview_tiles = get_aoe_tiles(mouse_tile_pos, target_ability)

	movement_range_indicator.queue_redraw()

func get_aoe_tiles(center_tile: Vector2i, ability: AbilityData) -> Array[Vector2i]:
	var affected_tiles: Array[Vector2i] = []
	match ability.aoe_shape:
		"circle":
			var radius = ability.aoe_radius if ability else 1
			for x in range(-radius, radius + 1):
				for y in range(-radius, radius + 1):
					var tile = Vector2i(center_tile.x + x, center_tile.y + y)
					if tile.distance_to(center_tile) <= radius and astar_grid.region.has_point(tile):
						affected_tiles.append(tile)
		"square":
			var size = ability.aoe_size if ability else 1
			for x in range(-size, size + 1):
				for y in range(-size, size + 1):
					var tile = Vector2i(center_tile.x + x, center_tile.y + y)
					if astar_grid.region.has_point(tile):
						affected_tiles.append(tile)
		"none":
			# No AoE, just return the center tile
			if astar_grid.region.has_point(center_tile):
				affected_tiles.append(center_tile)

	return affected_tiles
