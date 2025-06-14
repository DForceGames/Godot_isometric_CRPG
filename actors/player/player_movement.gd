extends Node2D

@export var speed: float = 100.0
var y_offset: float = 16.0 # For isometric view, to sink player visually

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
signal sp_changed(current_sp)

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
	
	# Connect to CombatManager's grid_made signal
	if CombatManager: # Assuming CombatManager is an autoload or globally accessible
		if not CombatManager.is_connected("grid_made", Callable(self, "show_movement_range")):
			var err = CombatManager.connect("grid_made", Callable(self, "show_movement_range"))
			if err != OK:
				printerr("PlayerMovement: Failed to connect to CombatManager.grid_made signal. Error: ", err)
	else:
		printerr("PlayerMovement: CombatManager not found, cannot connect grid_made signal.")

	# Add timer for hover updates
	var hover_timer = Timer.new()
	hover_timer.name = "_hover_timer"
	hover_timer.one_shot = true
	hover_timer.wait_time = 0.05
	hover_timer.connect("timeout", Callable(self, "_update_hover_preview"))
	add_child(hover_timer)

func _process(_delta: float):
	if not CombatManager.is_in_targeting_mode and not is_turn_based_mode():
		return  # Skip processing if not in targeting or turn-based mode

	var current_tile = CombatManager.world_to_map(get_global_mouse_position())
	if current_tile == last_hoverd_tile:
		return

	last_hoverd_tile = current_tile

	if CombatManager.is_in_targeting_mode:
		var mouse_tile = CombatManager.world_to_map(get_global_mouse_position())
		_update_targeting_preview(mouse_tile)
		return
	elif is_turn_based_mode():
		_update_turn_based_visuals(current_tile)

func _enter_tree() -> void:
	# Create a node for visualizing movement range
	movement_range_indicator = Node2D.new()
	movement_range_indicator.name = "MovementRangeIndicator"
	movement_range_indicator.z_index = 100  # Make sure it appears above the tilemap
	add_child(movement_range_indicator)
	movement_range_indicator.visible = false
	# if not movement_range_indicator.is_connected("draw", Callable(self, "_draw")):
	# 	movement_range_indicator.draw.connect(_draw)

func get_realtime_path() -> Array[Vector2]:
	# This function is a placeholder for real-time pathfinding logic
	# In real-time mode, we might not need a path at all, just move directly
	# if CombatManager.active_tilemap == null:
	# 	print("Cannot find path: No CombatManager.active_tilemap set")
	# 	return []
	
	# For now, return an empty path
	return []

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
		
		if is_turn_based_mode():
			# print("PlayerMovement: Step taken, remaining path size: ", path.size())
			# Update entity position in CombatManager
			# CombatManager.update_combatant_position(self, CombatManager.world_to_map(Player.global_position))
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
		stats_component.spend_sp(1)
	

	# Move player towards the (new) next_target_waypoint.
	if not path.is_empty():
		player.velocity = player.global_position.direction_to(next_target_waypoint) * speed
	else:
		# This case should ideally be handled by the path empty check above.
		player.velocity = Vector2.ZERO

func get_tileset() -> TileSet:
	if CombatManager.active_tilemap and CombatManager.active_tilemap.tile_set:
		return CombatManager.active_tilemap.tile_set
	else:
		print("TileSet not found in CombatManager.active_tilemap")
		return null

# Implement a new function for processing input during player's turn ---------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not is_turn_based_mode() or not CombatManager.active_tilemap:
		return
		
	# Track mouse hover in turn-based mode for tile highlighting
	if event is InputEventMouseMotion:
		var new_hover_tile = CombatManager.world_to_map(get_global_mouse_position())

		if new_hover_tile != hover_tile:
			hover_tile = new_hover_tile
			get_node("_hover_timer").start()
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		if CombatManager.is_in_targeting_mode:
			var clicked_tile = CombatManager.world_to_map(get_global_mouse_position())
			if clicked_tile in valid_target_tiles:
				print("PlayerMovement: Clicked tile ", clicked_tile, " is a valid target tile.")
				if target_ability:
					target_ability.use_ability(player, clicked_tile)
					if stats_component and target_ability.has_method("spend_ap"):
						stats_component.spend_ap(target_ability.ap_cost)
				stop_targeting_mode()
				get_viewport().set_input_as_handled()
			else:
				print("PlayerMovement: Clicked tile ", clicked_tile, " is not a valid target tile.")

# Show ranges and highlights in turn-based mode ---------------------------------------------------------------------
func show_movement_range():
	if not is_turn_based_mode() or not CombatManager.active_tilemap or not CombatManager.astar_grid:
		movement_range_indicator.visible = false
		return

	# Clear previous indicators
	queue_redraw()
	highlight_tiles.clear()

	# Get player's current map position and resources
	var player_map_pos = CombatManager.world_to_map(player.global_position)
	var current_sp = stats_component.get_current_sp()
	print("PlayerMovement: ", player_map_pos)

	# Find all tiles within SP range 
	highlight_tiles = CombatManager.get_tiles_in_range(player_map_pos, current_sp, player)
	movement_range_indicator.visible = true

	queue_redraw()

	print("PlayerMovement: Showing movement range with ", highlight_tiles.size(), " tiles in range for SP: ", current_sp)

func _update_hover_preview():
	var mouse_tile = CombatManager.world_to_map(get_global_mouse_position())

	if CombatManager.is_in_targeting_mode:
		_update_targeting_preview(mouse_tile)
	elif is_turn_based_mode():
		_update_turn_based_visuals(mouse_tile)

func _update_turn_based_visuals(mouse_tile_pos: Vector2i):
	current_path_tiles.clear()

	if not CombatManager.active_tilemap or not CombatManager.astar_grid:
		return

	if mouse_tile_pos in highlight_tiles:
		var new_path_ids = CombatManager.get_tile_path(mouse_tile_pos, player.global_position) # Use the existing function

		if new_path_ids.size() > 1:
			current_path_tiles = new_path_ids.slice(1) 
			var steps_needed = current_path_tiles.size() 

			if steps_needed <= stats_component.get_current_sp() and steps_needed > 0:
				pass
			else:
				current_path_tiles.clear()
		else:
			current_path_tiles.clear()
		
	queue_redraw()
	
func _draw() -> void:
	_draw_movement_indicators()

func _draw_movement_indicators():
	if CombatManager.is_in_targeting_mode:
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

func _draw_tile_highlight(tile_pos: Vector2i, color: Color):
	if not CombatManager.active_tilemap:
		return
	
	var world_pos = CombatManager.active_tilemap.to_global(CombatManager.active_tilemap.map_to_local(tile_pos))
	var indicator_pos = movement_range_indicator.to_local(world_pos)

	var half_size = CombatManager.cell_size / 2.0
	var points = PackedVector2Array([
		indicator_pos + Vector2(0, -half_size.y),          # Top
		indicator_pos + Vector2(half_size.x, 0),           # Right
		indicator_pos + Vector2(0, half_size.y),           # Bottom
		indicator_pos + Vector2(-half_size.x, 0)           # Left
	])

	draw_colored_polygon(points, color)

func handle_freeroam_movement(target_position: Vector2):
	self.freeroam_target_position = target_position

func set_movement_target(target_position: Vector2):
	if not is_turn_based_mode():
		handle_freeroam_movement(target_position)
	else:
		handle_grid_movement(target_position)

func handle_grid_movement(target_position: Vector2):
	if not stats_component or not CombatManager.active_tilemap:
		print("PlayerMovement: No Stats component or TileMapLayer found. Cannot handle grid movement.")
		return

	var target_cell = CombatManager.world_to_map(target_position)
	if not target_cell in highlight_tiles:
		print("PlayerMovement: Clicked outside movement range")
		return

	var new_path = CombatManager.get_tile_path(target_cell, player.global_position)

	if new_path.size() <= 1: # No path or path is just the current tile
		print("PlayerMovement: No valid path found or target is current location.")
		return
	
	var steps_needed = new_path.size() - 1
	var sp_cost = steps_needed  # 1 SP per tile

	if sp_cost <= stats_component.get_current_sp():
		path.clear()
		for cell_id in new_path:
			path.append(CombatManager.active_tilemap.to_global(CombatManager.active_tilemap.map_to_local(cell_id)))
		_start_following_path()

func _physics_process(_delta: float):
	if not is_instance_valid(player):
		return

	if GameStateManager.is_turn_based():
		speed = 100
	elif GameStateManager.is_real_time():
		speed = 200  # Use player's speed in real-time mode

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
func _on_sp_changed(_new_sp):
	if is_turn_based_mode():
		print("PlayerMovement: Detected SP change from Stats. New SP: %s. Updating movement range." % _new_sp)
		show_movement_range() 
		# _update_turn_based_pathfinding_preview() 
		if movement_range_indicator: queue_redraw()

# Ensure _on_step_taken exists if connected in _ready
func _on_step_taken() -> void:
	if is_turn_based_mode():
		# Update entity position in CombatManager
		CombatManager.update_combatant_position(player, CombatManager.world_to_map(player.global_position))
		if movement_range_indicator: queue_redraw()
		

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
		queue_redraw()

# Start following the path
func _start_following_path() -> void:
	current_path_index = 0
	current_phase = MovementPhase.FOLLOWING_PATH
	emit_signal("movement_started")

# Function for targeting mode for abilities
func enter_targeting_mode(ability: AbilityData):
	if not is_turn_based_mode():
		print("PlayerMovement: Cannot enter targeting mode in real-time mode.")
		return
	
	if not ability:
		print("PlayerMovement: No ability provided for targeting mode.")
		return
	
	if CombatManager.is_in_targeting_mode:
		print("PlayerMovement: Already in targeting mode.")
		stop_targeting_mode()

	get_node("_hover_timer").stop()
	CombatManager.is_in_targeting_mode = true
	target_ability = ability
	var player_map_pos = CombatManager.world_to_map(player.global_position)
	valid_target_tiles = get_valid_target_tiles(player_map_pos, ability)

	queue_redraw()

func get_valid_target_tiles(start_tile: Vector2i, ability) -> Array[Vector2i]:
	var valid_tiles: Array[Vector2i] = []
	# calculate valid tile based on the player position and minimum and maximum ability range
	if not CombatManager.active_tilemap or not CombatManager.astar_grid:
		print("PlayerMovement: No CombatManager.active_tilemap or CombatManager.astar_grid found. Cannot get valid target tiles.")
		return valid_tiles

	var max_range = ability.max_range if ability else 0
	var min_range = ability.min_range if ability else 0
	for tile in CombatManager.get_tiles_in_range(start_tile, max_range, player):
		if tile.distance_to(start_tile) >= min_range:
			valid_tiles.append(tile)

	print("PlayerMovement: Valid target tiles calculated for ability ", ability.ability_name, ": ", valid_tiles)
	return valid_tiles

func stop_targeting_mode():
	get_node("_hover_timer").stop()
	CombatManager.is_in_targeting_mode = false
	target_ability = null
	valid_target_tiles.clear()
	aoe_preview_tiles.clear()
	queue_redraw()

func _update_targeting_preview(mouse_tile_pos: Vector2i):
	aoe_preview_tiles.clear()

	if mouse_tile_pos in valid_target_tiles:
		aoe_preview_tiles = CombatManager.get_aoe_tiles(mouse_tile_pos, target_ability)

	queue_redraw()
