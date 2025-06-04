extends CharacterBody2D
class_name Player

var speed: float = 100.0
@export var tilemap_path: NodePath
@export var interaction_groups: Array[String] = ["interactable", "NPC", "Container", "pickup"]

# Player Stats
var player_name: String = "Player"
var experience: int = 0

# References
var game_state_manager
var movement_system
var interaction_distance: float = 64.0
var current_nearby_npc: NPC = null

# Signals
signal resources_refreshed(current_health, max_health, action_points, max_sp)
signal _on_sp_changed(current_sp: int)

func _ready() -> void:
	await get_tree().process_frame
	# Get GameStateManager
	game_state_manager = get_node_or_null("/root/GameStateManager")
	if game_state_manager:
		game_state_manager.game_mode_changed.connect(_on_game_mode_changed)
	
	# Setup movement system
	movement_system = get_node_or_null("PlayerMovement")
	if movement_system:
		_setup_movement_system()
	else:
		printerr("Player: PlayerMovement node not found as a child")

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed()):
		return
		
	var interactable = get_interactable_at_mouse_position()
	if interactable:
		if is_within_interaction_distance(interactable):
			interactable.interact()
			if interactable is NPC:
				current_nearby_npc = interactable
		else:
			# Move closer to interactable
			var pos_to_move = position_one_tile_away_from(interactable)
			move_to_position(pos_to_move)
	else:
		# Move to clicked position
		move_to_position(get_global_mouse_position())

# Movement and animation -------------------------------------------------------------

func _setup_movement_system() -> void:
	# Just initialize with the tilemap
	if not tilemap_path.is_empty():
		var tilemap = get_node_or_null(tilemap_path)
		if tilemap:
			movement_system.primary_tilemap_layer = tilemap
			movement_system.speed = speed
			movement_system.initialize_grid()

# Simple function to tell movement system where to go
func move_to_position(target_pos: Vector2) -> void:
	if not movement_system:
		return
	
	# Check if we're in turn-based mode
	if game_state_manager and game_state_manager.is_turn_based():
		# Let the movement system handle turn-based movement with SP costs
		movement_system.handle_turn_based_movement(target_pos)
	else:
		# Regular real-time path following
		movement_system.start = global_position
		movement_system.end = target_pos
		movement_system.get_ideal_path()

func _physics_process(_delta: float) -> void:
	if movement_system and movement_system.path.size() > 0: # and GameStateManager.is_turn_based():
		movement_system.follow_path() # Moved to movement_player
	else:
		velocity = Vector2.ZERO
	
	if velocity != Vector2.ZERO:
		move_and_slide()
	
	_update_player_animations()

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
	else: # Moving predominantly vertically
		if anim_sprite.animation == "walking_left" or anim_sprite.animation == "walking_right":
			target_animation = anim_sprite.animation
		else:
			target_animation = "walking_right"
	
	if anim_sprite.animation != target_animation:
		anim_sprite.play(target_animation)

func _on_game_mode_changed(new_mode) -> void:
	if movement_system and movement_system.has_method("handle_game_mode_changed"):
		movement_system.handle_game_mode_changed(new_mode)
	
	var anim_sprite = $AnimatedSprite2D
	if anim_sprite and velocity == Vector2.ZERO:
		anim_sprite.play("idle")

# Interaction Functions ------------------------------------------------------------------------

func get_interactable_at_mouse_position() -> Node:
	var mouse_pos = get_global_mouse_position()
	
	# Physics query for exact hits
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = mouse_pos
	query.collision_mask = 0xFFFFFFFF
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var collider = collision["collider"]
		for group in interaction_groups:
			if collider.is_in_group(group) and collider.has_method("interact"):
				return collider
	
	# Check proximity if no direct hit
	var closest_interactable = null
	var closest_distance_squared = pow(40.0, 2)
	
	var all_interactables = []
	for group in interaction_groups:
		all_interactables.append_array(get_tree().get_nodes_in_group(group))
	
	for interactable in all_interactables:
		if interactable.has_method("interact"):
			var distance_squared = interactable.global_position.distance_squared_to(mouse_pos)
			if distance_squared < closest_distance_squared:
				closest_distance_squared = distance_squared
				closest_interactable = interactable
	
	return closest_interactable

func is_within_interaction_distance(interactable: Node) -> bool:
	return global_position.distance_to(interactable.global_position) <= interaction_distance

func position_one_tile_away_from(interactable: Node) -> Vector2:
	var direction = interactable.global_position.direction_to(global_position)
	if direction.length() < 0.1:
		direction = Vector2.RIGHT
	
	var tile_size = 32.0  # Default
	if movement_system:
		tile_size = movement_system.cell_size.x
	
	# Simple approach: just stand in the direction we're already coming from
	return interactable.global_position + direction.normalized() * tile_size * 1.2

func end_npc_interaction() -> void:
	if current_nearby_npc and current_nearby_npc.has_method("end_interaction"):
		current_nearby_npc.end_interaction()
		current_nearby_npc = null

# Resouces -------------------------------------------------------------------------------------

# func refresh_resources() -> void:
	
# 	# Reset any other resources as needed
# 	print("Player resources refreshed")
	
# 	# Optionally reset inventory or other game state
# 	# if game_state_manager:
# 	# 	game_state_manager.refresh_inventory()

# 	if movement_system:
# 		movement_system.current_sp = Stats.max_sp
# 		emit_signal("_on_sp_changed", movement_system.current_sp)
