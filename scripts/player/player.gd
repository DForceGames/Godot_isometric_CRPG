extends CharacterBody2D
class_name Player

@export var speed: float = 100.0 # Changed initial value from 200.0 to 100.0, this is the movement speed
@export var tilemap_path: NodePath

# Add this array of interaction groups to the beginning of your Player class
@export var interaction_groups: Array[String] = ["interactable", "NPC", "Container", "pickup"]

# Player Stats - these are now class members and can be modified
var player_name: String = "Player" # Renamed from 'name' to avoid Node.name conflict
var level: int = 1
var max_health: int = 100
var current_health: int = 100
var action_points: int = 6  # Number of action points available per turn
var attack_power: int = 10
var defense: int = 5
var magic_power: int = 15
var magic_defense: int = 3
var experience: int = 0
# --- End of Player Stats ---

# Movement system
var movement_system: Node

# Reference to GameStateManager
var game_state_manager

# Interaction settings
var interaction_distance: float = 64.0  # Distance in pixels for interaction (adjust based on your tile size)
var current_nearby_npc: NPC = null  # Current NPC that player is interacting with

func Refresh_resources() -> void:
	if movement_system and movement_system.has_method("refresh_resources"):
		movement_system.refresh_resources()
	
func _ready() -> void:
	# Get the GameStateManager autoload instance
	game_state_manager = get_node_or_null("/root/GameStateManager")
	if game_state_manager:
		game_state_manager.game_mode_changed.connect(_on_game_mode_changed)
	else:
		printerr("Player: GameStateManager autoload not found. Ensure it is set up correctly.")

	# Setup/find movement system
	movement_system = get_node_or_null("PlayerMovement")
	if not movement_system:
		printerr("Player: PlayerMovement node not found as a child. Movement functionality unavailable.")
		# You could alternatively create it here dynamically:
		# movement_system = load("res://scripts/player_movement.gd").new()
		# movement_system.name = "PlayerMovement"
		# movement_system.player = self
		# add_child(movement_system)
	else:
		_setup_movement_system()

func _setup_movement_system() -> void:
	if not tilemap_path.is_empty():
		# Get the tilemap
		var node = get_node_or_null(tilemap_path)
		if not node is TileMapLayer:
			printerr("Player: Node at tilemap_path is not a TileMapLayer. Path: ", tilemap_path, ". Node is: ", node)
			return
			
		var primary_tilemap_layer = node
		
		# Discover the ground and obstacle layers
		var ground_layers: Array[TileMapLayer] = []
		var obstacle_layers: Array[TileMapLayer] = []
		
		var map_parent = primary_tilemap_layer.get_parent()
		if map_parent:
			print("Player: Searching for layers under parent: ", map_parent.name)
			for child_idx in range(map_parent.get_child_count()):
				var child = map_parent.get_child(child_idx)
				print("Player: Checking child node: ", child.name, " of type: ", child.get_class())
				if child is TileMapLayer:
					var child_name_str = String(child.name)
					print("Player: Found TileMapLayer: ", child_name_str)
					if child_name_str.begins_with("Ground"):
						if not ground_layers.has(child): # Avoid duplicates
							ground_layers.append(child)
							print("Player: Added to ground_layers: ", child_name_str)
					elif child_name_str.begins_with("Obstacle"):
						if not obstacle_layers.has(child): # Avoid duplicates
							obstacle_layers.append(child)
							print("Player: Added to obstacle_layers: ", child_name_str)
		
		# Ensure primary_tilemap_layer is considered a ground layer if no other ground layers are found
		# or if it's named like a ground layer and wasn't picked up.
		if primary_tilemap_layer:
			if String(primary_tilemap_layer.name).begins_with("Ground") and not ground_layers.has(primary_tilemap_layer):
				ground_layers.append(primary_tilemap_layer)
				print("Player: Added primary_tilemap_layer (named Ground*) to ground_layers: ", String(primary_tilemap_layer.name))
			elif ground_layers.is_empty() and not ground_layers.has(primary_tilemap_layer):
				ground_layers.append(primary_tilemap_layer)
				print("Player: No 'Ground*' layers found, using primary tilemap layer as ground: ", String(primary_tilemap_layer.name))
	
		if ground_layers.is_empty() and primary_tilemap_layer:
			# This is a fallback if absolutely no "Ground*" layers were found and the above didn't add it.
			ground_layers.append(primary_tilemap_layer)
			print("Player: Fallback - Using primary tilemap layer as ground: ", String(primary_tilemap_layer.name))
		
		if ground_layers.is_empty():
			printerr("Player: No ground layers found or assigned. Pathfinding will not work.")
			return
	
		print("Player: Using ground layers: ", ground_layers.map(func(layer): return layer.name))
		print("Player: Using obstacle layers: ", obstacle_layers.map(func(layer): return layer.name))
	
		# Initialize the movement system with the found layers
		movement_system.initialize(primary_tilemap_layer, ground_layers, obstacle_layers)
		movement_system.speed = speed  # Sync the speed value
		# Connect to movement system signals if needed
		
func _input(event: InputEvent) -> void:
	# Focus only on right-click events for movement and interaction
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
		# Check for interactable under mouse cursor first
		var interactable = get_interactable_at_mouse_position()
		
		if interactable:
			print("Right-clicked on interactable: ", interactable.name)
			if is_within_interaction_distance(interactable):
				# We're close enough to interact
				print("Within interaction distance, interacting with: ", interactable.name)
				interactable.interact()
				
				# Store reference if it's an NPC (for dialogue system)
				if interactable is NPC:
					current_nearby_npc = interactable
			else:
				# Interactable exists but we're too far - need to move closer first
				print("Interactable too far, moving closer")
				var pos_to_move = position_one_tile_away_from(interactable)
				if movement_system and movement_system.has_method("set_target_position"):
					movement_system.set_target_position(pos_to_move)
		else:
			# No interactable was clicked on, so just move to the clicked location
			print("No interactable at click location, moving to clicked position")
			if movement_system:
				movement_system.handle_input(event)
		
		# We've handled the right-click event, so return
		return
		
	# For other input types (not right-click), pass to movement system if needed
	if movement_system:
		movement_system.handle_input(event)

func _physics_process(_delta: float) -> void:
	if not movement_system:
		return
		
	velocity = movement_system.process_movement()
	_update_player_animations()
	
	if velocity != Vector2.ZERO:
		move_and_slide()

func _update_player_animations() -> void:
	var anim_sprite = $AnimatedSprite2D
	if not anim_sprite or not anim_sprite.has_method("play"):
		return
		
	if velocity == Vector2.ZERO:
		if anim_sprite.animation != "idle":
			anim_sprite.play("idle")
		return
			
	var target_animation = ""
	if velocity.x < -0.01: # Moving significantly left
		target_animation = "walking_left"
	elif velocity.x > 0.01: # Moving significantly right
		target_animation = "walking_right"
	else: # Moving predominantly vertically (velocity.x is close to 0)
		  # and velocity.y is non-zero because (velocity != Vector2.ZERO)
		# Try to maintain current horizontal facing animation if one is playing
		if anim_sprite.animation == "walking_left" or \
		   anim_sprite.animation == "walking_right":
			target_animation = anim_sprite.animation
		else:
			# Default if not already facing left/right 
			target_animation = "walking_right" # Default to "walking_right"
	
	if anim_sprite.animation != target_animation:
		anim_sprite.play(target_animation)
		
# New function to handle game mode changes
func _on_game_mode_changed(new_mode) -> void:
	if movement_system:
		movement_system.handle_game_mode_changed(new_mode)
		
	var anim_sprite = $AnimatedSprite2D
	if anim_sprite and anim_sprite.has_method("play"):
		if velocity == Vector2.ZERO and anim_sprite.animation != "idle":
			anim_sprite.play("idle")

# Replace your get_npc_at_mouse_position() function with this more generic one
func get_interactable_at_mouse_position() -> Node:
	# Cast a ray from camera to mouse position to find interactable
	var mouse_pos = get_global_mouse_position()
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = mouse_pos
	query.collision_mask = 0xFFFFFFFF  # Check all collision layers

	# First check direct collision with mouse position
	var result = space_state.intersect_point(query)
	for collision in result:
		var collider = collision["collider"]
		# Check if it belongs to any of our interaction groups
		for group in interaction_groups:
			if collider.is_in_group(group) and collider.has_method("interact"):
				print("Found interactable via physics query: ", collider.name, " (group: ", group, ")")
				return collider

	# Alternative: Check if any interactable is close to the mouse cursor
	var closest_interactable = null
	var closest_distance_squared = pow(40.0, 2)  # Increased detection radius to 40 pixels

	# Build a list of all potential interactables from our groups
	var all_interactables = []
	for group in interaction_groups:
		all_interactables.append_array(get_tree().get_nodes_in_group(group))

	print("Found ", all_interactables.size(), " potential interactables to check")

	for interactable in all_interactables:
		if interactable.has_method("interact"):
			var distance_squared = interactable.global_position.distance_squared_to(mouse_pos)
			if distance_squared < closest_distance_squared:
				closest_distance_squared = distance_squared
				closest_interactable = interactable

	if closest_interactable:
		print("Found closest interactable: ", closest_interactable.name, " at distance: ", sqrt(closest_distance_squared))

	return closest_interactable

# Replace is_within_interaction_distance to accept any interactable
func is_within_interaction_distance(interactable: Node) -> bool:
	var distance = global_position.distance_to(interactable.global_position)
	return distance <= interaction_distance

# Replace position_one_tile_away_from to accept any interactable
func position_one_tile_away_from(interactable: Node) -> Vector2:
	# Calculate a position that's one tile away from the interactable
	var direction = interactable.global_position.direction_to(global_position)
	if direction.length() < 0.1:  # If we're at the same position or very close
		direction = Vector2.RIGHT
	else:
		# Normalize the direction vector
		direction = direction.normalized()
	
	# Get the tile size
	var tile_size = 32.0  # Default estimate
	if movement_system and movement_system.has_method("get_tile_size"):
		tile_size = movement_system.get_tile_size()
	
	# Calculate several potential positions around the interactable
	var potential_positions = []
	var angles = [0, 45, -45, 90, -90, 135, -135, 180]
	
	for angle_deg in angles:
		var angle_rad = deg_to_rad(angle_deg)
		var rotated_dir = direction.rotated(angle_rad)
		var pos = interactable.global_position + (rotated_dir * tile_size * 1.2)
		
		# Check if this position is valid (not occupied by an obstacle)
		var is_valid = true
		if movement_system and movement_system.has_method("is_position_walkable"):
			is_valid = movement_system.is_position_walkable(pos)
		
		if is_valid:
			# Add this position to our list
			var distance = global_position.distance_to(pos)
			potential_positions.append({"position": pos, "distance": distance})
	
	# Sort positions by distance to the player
	potential_positions.sort_custom(func(a, b): return a["distance"] < b["distance"])
	
	# Return the closest valid position
	if potential_positions.size() > 0:
		return potential_positions[0]["position"]
	
	# Fallback to the original calculation if no valid positions found
	return interactable.global_position + (direction * tile_size * 1.2)

# Function to end interaction with current NPC
func end_npc_interaction() -> void:
	if current_nearby_npc and current_nearby_npc.has_method("end_interaction"):
		current_nearby_npc.end_interaction()
		current_nearby_npc = null

func _on_hitbox_body_entered() -> void:
	var battle_manager = get_node_or_null("/root/BattleManager")
	var damage_taken = 0
	if battle_manager and battle_manager.has_method("calculate_damage"):
		damage_taken = battle_manager.calculate_damage()
	else:
		printerr("BattleManager not found or does not have calculate_damage method.")
	
	add_damage_to_player(damage_taken)

func add_damage_to_player(damage: int) -> void:
	current_health -= damage
	print("Player took damage: ", damage, " Health remaining: ", current_health)
	
	if current_health <= 0:
		print("Player has died.")
		# Handle player death logic here, e.g., respawn or game over
		# For now, just reset health for demonstration purposes
		current_health = max_health
		print("Player respawned with full health.")