extends Node

# Signals
signal combat_started(turn_order)
signal combat_ended(result)
signal turn_started(combatant)
signal new_round_started(round_number)
signal grid_made()

enum CombatState {
	INACTIVE,
	COMBAT_STARTED,
	CHOOSING_COMBATANT,
	PLAYER_TURN,
	ENEMY_TURN,
	COMBAT_ENDED
}
var current_state: CombatState = CombatState.INACTIVE
var active_combatant: Node = null

var npc_id
var ai_brain: AIBrain = AIBrain.new()

var turn_queue: Array[Node] = []
var turn_index: int = 0
var round_number: int = -1
var is_combat_ended: bool = false

# Vars needed for gridmap and positions
var astar_grid = AStarGrid2D.new()
var grid_size
var tileset: TileSet = null
var active_tilemap: TileMapLayer = null
var combatant_positions: Dictionary = {}
var scale_factor = active_tilemap.scale if active_tilemap else Vector2(1, 1)
var cell_size: Vector2 = Vector2(64 * scale_factor.x, 32 * scale_factor.y)
var is_in_targeting_mode: bool = false

func change_state(new_state: CombatState):
	if current_state == new_state:
		return
	
	current_state = new_state
	print("CombatManager: State changed to ", current_state)

	match current_state:
		CombatState.CHOOSING_COMBATANT:
			print("CombatManager: Choosing combatant state")
			if check_end_of_combat_conditions(): 
				change_state(CombatState.COMBAT_ENDED)

			var next_combatant = find_next_living_combatant()
			if next_combatant:
				active_combatant = next_combatant
				if active_combatant.is_in_group("Player") or active_combatant.is_in_group("Ally"):
					change_state(CombatState.PLAYER_TURN)
				elif active_combatant.is_in_group("Enemy"):
					change_state(CombatState.ENEMY_TURN)
			else:
				change_state(CombatState.COMBAT_ENDED)

		CombatState.PLAYER_TURN:
			active_combatant.on_combat_manager_turn_started(active_combatant)
			turn_started.emit(active_combatant)

		CombatState.ENEMY_TURN:
			active_combatant._on_turn_started(active_combatant)
			turn_started.emit(active_combatant)
			var timer = get_tree().create_timer(0.5)
			timer.timeout.connect(func():
				ai_brain.execute_turn_sequence(active_combatant)
			)
		CombatState.COMBAT_ENDED:
			var result = check_end_of_combat_conditions()
			end_combat(result)

func start_combat(player_party, enemies):
	turn_queue.clear()
	turn_index = 0
	round_number = 1
	initialize_grid()

	var combatants_with_rolls = []
	for player in player_party:
		if is_instance_valid(player):
			combatants_with_rolls.append({"Node": player,"Roll": player.stats.initiative})
		
	for enemy in enemies:
		if is_instance_valid(enemy):
			combatants_with_rolls.append({"Node": enemy,"Roll": enemy.stats.initiative})
				
	combatants_with_rolls.sort_custom(func(a, b): return a.Roll > b.Roll)
			
	for combatant_data in combatants_with_rolls:
		var combatant = combatant_data["Node"]
		turn_queue.append(combatant)
		if combatant.has_method("on_start_combat"):
			combatant.on_start_combat()
	combatant_positions.clear()
	for combatant in turn_queue:
		var start_pos = world_to_map(combatant.global_position)
		register_combatant_position(combatant, start_pos)

	combat_started.emit(turn_queue)
	change_state(CombatState.CHOOSING_COMBATANT)

func find_next_living_combatant():
	for _i in range(turn_queue.size()):
		turn_index += 1
		if turn_index >= turn_queue.size():
			turn_index = 0
			round_number += 1
			new_round_started.emit(round_number)

		var current_combatant = turn_queue[turn_index]
		if is_instance_valid(current_combatant) and current_combatant.stats.is_alive():
			print("CombatManager: Next living combatant is %s (Turn Index: %d, Round: %d)" % [current_combatant.name, turn_index, round_number])
			return current_combatant
	return null

func player_ended_turn():
	print("CombatManager: Player ended turn.")
	change_state(CombatState.CHOOSING_COMBATANT)

func enemy_ended_turn():
	print("CombatManager: Enemy ended turn.")
	change_state(CombatState.CHOOSING_COMBATANT)

func end_combat(result: String):
	combat_ended.emit(result)

	# Cleanup
	for combatant in turn_queue:
		if not is_instance_valid(combatant):
			if combatant.has_method("end_combat"):
				continue

		if combatant.has_method("end_combat"):
			combatant.end_combat()
		
	# Reset
	combatant_positions.clear()
	turn_queue.clear()
	turn_index = -1
	round_number = 1

	# Return to main state
	GameStateManager.return_to_exploration()

func check_end_of_combat_conditions():
	var player_combatants_alive = false
	var enemy_combatants_alive = false

	for combatant in turn_queue:
		if combatant.is_dead():
			continue
		if combatant.is_in_group("Player"):
			player_combatants_alive = true
		elif combatant.is_in_group("Enemy"):
			enemy_combatants_alive = true

	if not player_combatants_alive:
		return "DEFEAT"
	elif not enemy_combatants_alive:
		return "VICTORY"

	return

# ---------------------------- Setup Battle Map with logic ----------------------------

func set_active_tilemap(tilemap: TileMapLayer):
	active_tilemap = tilemap
	print("CombatManager: Active tilemap set to ", active_tilemap.name)

func initialize_grid():
	print("CombatManager: Initializing grid...")
	if not active_tilemap:
		print("Cannot initialize grid: No primary_tilemap_layer set")
		return
	
	if tileset == null:
		tileset = active_tilemap.tile_set
		if tileset == null:
			print("Cannot initialize grid: No tileset found in active_tilemap")
			return

	# Now you can use the active_tilemap to determine grid size if needed
	grid_size = active_tilemap.get_used_rect()
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

	grid_made.emit()

func world_to_map(world_position: Vector2):
	if not active_tilemap:
		printerr("CombatManager: No active tilemap set!")
		return Vector2.ZERO
	
	var adjusted = world_position / active_tilemap.scale
	return active_tilemap.local_to_map(adjusted)

func map_to_world(map_position: Vector2): # Gets it to the centre of the tile
	if not active_tilemap:
		printerr("CombatManager: No active tilemap set!")
		return Vector2.ZERO

	return active_tilemap.map_to_local(map_position)
# Still gridmap related
func register_combatant_position(combatant: Node, map_position: Vector2):
	combatant_positions[map_position] = combatant

func get_combatant_at_tile(map_position: Vector2):
	return combatant_positions.get(map_position, null)

func get_aoe_tiles(center_tile: Vector2i, ability: AbilityData) -> Array[Vector2i]:
	print("CombatManager: Getting AoE tiles for ability: ", ability.ability_name, " wiht AoE shape: ", ability.aoe_shape, " at center tile: ", center_tile)
	var affected_tiles: Array[Vector2i] = []
	match ability.aoe_shape:
		1: # Circle
			var radius = ability.area_of_effect_radius if ability else 1
			for x in range(-radius, radius + 1):
				for y in range(-radius, radius + 1):
					var tile = Vector2i(center_tile.x + x, center_tile.y + y)
					if tile.distance_to(center_tile) <= radius and astar_grid.region.has_point(tile):
						affected_tiles.append(tile)
		2: # Square
			var size = ability.area_of_effect_radius if ability else 1
			for x in range(-size, size + 1):
				for y in range(-size, size + 1):
					var tile = Vector2i(center_tile.x + x, center_tile.y + y)
					if astar_grid.region.has_point(tile):
						affected_tiles.append(tile)
		0: #None
			# No AoE, just return the center tile
			if astar_grid.region.has_point(center_tile):
				affected_tiles.append(center_tile)

	print("CombatManager: Affected tiles for ability ", ability.ability_name, ": ", affected_tiles)
	return affected_tiles

func set_tiles_solid_from_groups() -> void:
	if not active_tilemap or not tileset:
		print("Cannot set tiles solid: No active_tilemap or tileset found")
		return
	
	if not astar_grid:
		print("Cannot set tiles solid: AStarGrid2D not initialized")
		return
	
	var used_cells = active_tilemap.get_used_cells()
	var custom_data_layer_name = "Solid" # Custom property to set as solid

	for cell_coords in used_cells:
		if not astar_grid.region.has_point(cell_coords):
			continue
		
		var tile_data: TileData = active_tilemap.get_cell_tile_data(cell_coords)

		if tile_data:
			var is_tile_solid = tile_data.get_custom_data(custom_data_layer_name)

			if typeof(is_tile_solid) == TYPE_BOOL and is_tile_solid == true:
				print("Tile set as solid at cell: ", cell_coords)
				astar_grid.set_point_solid(cell_coords, true)
			else:
				continue

func get_tile_path(target_cell, player_pos):
	var dynamic_obstacle_cells = []
	var entitie_groups = ["Enemy", "Player", "NPC", "Ally"]

	for group in entitie_groups:
		var nodes = get_tree().get_nodes_in_group(group)
		for node in nodes:
			if node == self:
				# print("Skipping self node in dynamic obstacle detection ", node.name)
				continue # Skip self
			if node is CharacterBody2D or node is Node2D:
				# print("Adding dynamic obstacle for node: ", node.name)
				var cell = world_to_map(node.global_position)

				if grid_size.has_point(cell):
					astar_grid.set_point_solid(cell, true)
					dynamic_obstacle_cells.append(cell)
	var new_path = []

	var player_cell = world_to_map(player_pos)
	if not astar_grid.is_point_solid(target_cell):	
		new_path = astar_grid.get_id_path(player_cell, target_cell)

	for cell in dynamic_obstacle_cells:
		CombatManager.astar_grid.set_point_solid(cell, false)
	return new_path

func get_tiles_in_range(start_pos: Vector2i, range_value: int, player):
	var tiles_in_range: Array[Vector2i] = []
	var visited: Dictionary = {}
	var queue: Array = []

	if not CombatManager.active_tilemap or not CombatManager.astar_grid:
		printerr("PlayerMovement: Cannot get tiles in range. Missing TileMapLayer or AStarGrid.")
		return tiles_in_range

	var dynamic_obstacle_cells: Array[Vector2i] = []
	var entitie_groups = ["Enemy", "Player", "NPC", "Ally"] # Consider all relevant groups

	if not is_in_targeting_mode:
		for group_name in entitie_groups:
			var nodes_in_group = get_tree().get_nodes_in_group(group_name)
			for node_instance in nodes_in_group:
				if node_instance == player: # Don't block the starting player tile itself for range calculation
					continue
				if node_instance is Node2D: # Check if it's a Node2D to get global_position
					var entity_map_pos = CombatManager.world_to_map(node_instance.global_position)
					if CombatManager.astar_grid.region.has_point(entity_map_pos) and not CombatManager.astar_grid.is_point_solid(entity_map_pos):
						CombatManager.astar_grid.set_point_solid(entity_map_pos, true)
						dynamic_obstacle_cells.append(entity_map_pos)

	queue.push_back({"pos": start_pos, "dist": 0})
	
	while not queue.is_empty():
		var current = queue.pop_front()
		var pos: Vector2i = current["pos"]
		var dist: int = current["dist"]
		
		if visited.has(pos) or dist > range_value:
			continue
			
		visited[pos] = dist

		if CombatManager.astar_grid.region.has_point(pos) and not CombatManager.astar_grid.is_point_solid(pos):
			tiles_in_range.append(pos)
			
			if dist < range_value:
				var neighbors = [
					Vector2i(pos.x + 1, pos.y),
					Vector2i(pos.x - 1, pos.y),
					Vector2i(pos.x, pos.y + 1),
					Vector2i(pos.x, pos.y - 1)
				]
				for neighbor_pos in neighbors:
					if CombatManager.astar_grid.region.has_point(neighbor_pos): # Check if neighbor is within grid
						queue.push_back({"pos": neighbor_pos, "dist": dist + 1})

	for cell_to_revert in dynamic_obstacle_cells:
		var tile_data: TileData = CombatManager.active_tilemap.get_cell_tile_data(cell_to_revert)
		var is_permanently_solid = false
		if tile_data:
			is_permanently_solid = tile_data.get_custom_data("Solid") == true
		
		if not is_permanently_solid:
			CombatManager.astar_grid.set_point_solid(cell_to_revert, false)

	return tiles_in_range

func get_adjacent_tiles(tile_pos):
	var neighbors = []
	var directions = [
		Vector2i(1, 0),  # Right
		Vector2i(-1, 0), # Left
		Vector2i(0, 1),  # Down
		Vector2i(0, -1)  # Up
	]
	for dir in directions:
		var neighbor_pos = tile_pos + dir
		if astar_grid.region.has_point(neighbor_pos) and not astar_grid.is_point_solid(neighbor_pos):
			neighbors.append(neighbor_pos)
	print("CombatManager: Adjacent tiles for ", tile_pos, ": ", neighbors)
	return neighbors


func get_combatant_position(combatant):
	var combatant_global_pos = combatant.global_position
	print("CombatManager: Getting combatant position for ", combatant.name, " at global position: ", combatant_global_pos)
	var combatant_pos = world_to_map(combatant_global_pos)
	print("CombatManager: Combatant position for ", combatant.name, " is at map position: ", combatant_pos)
	return combatant_pos

func get_all_players():
	var players = []
	for player_node in get_tree().get_nodes_in_group("Player"):
		players.append(player_node)
	for ally_node in get_tree().get_nodes_in_group("Ally"):
		players.append(ally_node)
	return players

func get_all_enemies():
	var enemies = []
	for enemy in get_tree().get_nodes_in_group("Enemy"):
		enemies.append(enemy)
	return enemies

func get_units_in_aoe_tiles(aoe_center_pos, ability):
	var tiles_in_aoe = get_aoe_tiles(aoe_center_pos, ability)
	var unit_in_aoe = []
	for tile in tiles_in_aoe:
		if not astar_grid.region.has_point(tile):
			continue
		
		var combatant = get_combatant_at_tile(tile)
		if combatant and combatant.stats.is_alive():
			unit_in_aoe.append(combatant)
	return unit_in_aoe
