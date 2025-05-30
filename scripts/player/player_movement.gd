extends Node

@export var cell_size: Vector2 = Vector2(32, 32)
@export var speed: float = 200.0

# Add this line to declare the primary_tilemap_layer variable
var primary_tilemap_layer: TileMapLayer = null

var astar_grid = AStarGrid2D.new()
var grid_size

var start = Vector2.ZERO
var end = Vector2.ZERO
var path = []

# Debug variable to track NPC ID
var npc_id = 0

func initialize_grid() -> void:
	if primary_tilemap_layer == null:
		print("Cannot initialize grid: No primary_tilemap_layer set")
		return
	
	# Now you can use the primary_tilemap_layer to determine grid size if needed
	grid_size = Rect2i(Vector2i.ZERO, Vector2i(100, 100))  # Example region, adjust as needed
	print("Grid initialized with size: ", grid_size)
	astar_grid.cell_size = cell_size
	astar_grid.size = grid_size.size  # Use only the size (Vector2i), not the Rect2i
	astar_grid.offset = cell_size / 2  # Center the grid on the origin
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar_grid.cell_shape = AStarGrid2D.CELL_SHAPE_ISOMETRIC_DOWN
	astar_grid.update()
	print("Grid made, isometric: ", astar_grid.default_estimate_heuristic)
	
	# Snap all entities to the grid
	snap_all_entities_to_grid()

func get_ideal_path():
	if start == end:
		return []
	
	# Make sure we have a valid grid
	if primary_tilemap_layer == null:
		print("Cannot find path: No primary_tilemap_layer set")
		return []
	
	# Define groups that should block pathfinding
	var blocking_groups = ["NPC", "Solid", "Obstacle", "blocking_tilemap", "Container"]
	
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
	
	# Optionally, mark specific tiles in the tilemap layer as solid
	# (e.g., if you have a "collision" or "solid" tile property)
	# Uncomment and adapt as needed:
	# for x in grid_size.position.x : grid_size.end.x:
	#     for y in grid_size.position.y : grid_size.end.y:
	#         var cell = Vector2i(x, y)
	#         if primary_tilemap_layer.get_cell_tile_data(0, cell) and primary_tilemap_layer.get_cell_tile_data(0, cell).get_custom_data("solid"):
	#             astar_grid.set_cell_blocked(cell, true)
	
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
	var player = get_tree().get_nodes_in_group("Player")
	if player.size() > 0:
		snap_entity_to_tile(player[0])
		
	print("Snapped all entities to grid")
