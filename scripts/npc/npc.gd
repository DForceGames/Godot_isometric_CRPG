extends CharacterBody2D
class_name NPC

## NPC Identification Information
@export var npc_name: String = "Generic NPC"
@export var npc_id: String = ""  # Unique identifier for this NPC, used for saving/loading state

## Visual Information
@export var visual_representation: NodePath  # Path to Sprite or AnimatedSprite2D node

## State & Interaction
enum NpcState { IDLE, WALKING, TALKING, BUSY, COMBAT }
@export var current_state: NpcState = NpcState.IDLE
@export var is_interactive: bool = true

## Stats
@export_group("Stats")
@export var health: int = 100
@export var max_health: int = 100
@export var movement_speed: float = 50.0

## Movement
@export_group("Movement")
@export var target_position: Vector2 = Vector2.ZERO
@export var patrol_points: Array[Vector2] = []
@export var current_patrol_index: int = 0
@export var idle_time: float = 2.0  # Time in seconds to wait at patrol points
var idle_timer: float = 0.0

## Interaction
@export_group("Interaction")
@export_multiline var interaction_prompt_text: String = "Press E to talk"
@export var default_dialogue_id: String = "default"
@export var disposition: float = 0.0  # -100 to 100, negative = hostile, positive = friendly

## References
var sprite_node: Node2D  # Will hold reference to the visual_representation node
var game_state_manager: Node  # Will hold reference to GameStateManager singleton

## Signals
signal interaction_started(npc_id: String)
signal interaction_ended(npc_id: String)
signal state_changed(new_state: NpcState)
signal health_changed(new_health: int, max_health: int)

var dialogue_active: bool = false

func _ready() -> void:
	# Initialize sprite reference
	if visual_representation:
		sprite_node = get_node_or_null(visual_representation)
	
	# Generate an NPC ID if none was provided
	if npc_id.is_empty():
		npc_id = "%s_%s" % [npc_name.replace(" ", "_").to_lower(), randi() % 1000]
	
	# Get game_state_manager reference
	game_state_manager = get_node_or_null("/root/GameStateManager")
	if game_state_manager:
		game_state_manager.game_mode_changed.connect(_on_game_mode_changed)
	
	# Initialize patrol system if patrol points exist
	if not patrol_points.is_empty():
		target_position = patrol_points[current_patrol_index]

func _physics_process(delta: float) -> void:
	match current_state:
		NpcState.IDLE:
			_process_idle_state(delta)
		NpcState.WALKING:
			_process_walking_state(delta)
		NpcState.TALKING:
			_process_talking_state(delta)
		NpcState.BUSY:
			# Custom behavior defined in derived classes
			pass
		NpcState.COMBAT:
			_process_combat_state(delta)
			
	# Always apply movement if there is velocity
	if velocity != Vector2.ZERO:
		move_and_slide()

func _process_idle_state(delta: float) -> void:
	velocity = Vector2.ZERO
	
	# If we have patrol points, transition to walking after idle timer expires
	if not patrol_points.is_empty():
		idle_timer += delta
		if idle_timer >= idle_time:
			idle_timer = 0.0
			current_patrol_index = (current_patrol_index + 1) % patrol_points.size()
			target_position = patrol_points[current_patrol_index]
			set_state(NpcState.WALKING)

func _process_walking_state(delta: float) -> void:
	if global_position.distance_to(target_position) < 5.0:
		# Reached target position, go back to idle
		set_state(NpcState.IDLE)
		return
		
	# Move towards target position
	var direction = global_position.direction_to(target_position)
	velocity = direction * movement_speed
	update_animation(direction)

func _process_talking_state(_delta: float) -> void:
	if sprite_node and sprite_node is AnimatedSprite2D:
		var anim_sprite = sprite_node as AnimatedSprite2D
		if anim_sprite.sprite_frames.has_animation("talking"):
			anim_sprite.play("Talking")
		else:
			anim_sprite.play("Idle")
	velocity = Vector2.ZERO
	# Just stop movement, don't start dialogue here

func _process_combat_state(_delta: float) -> void:
	# Combat state behavior would be implemented in derived classes
	# or handled by a CombatManager
	pass

func set_state(new_state: NpcState) -> void:
	if current_state != new_state:
		current_state = new_state
		state_changed.emit(new_state)

func update_animation(direction: Vector2) -> void:
	if not sprite_node:
		return
	
	# Default implementation - derived classes can override for specific animations
	if sprite_node is AnimatedSprite2D:
		var anim_sprite = sprite_node as AnimatedSprite2D
		
		if velocity == Vector2.ZERO:
			anim_sprite.play("idle")
		else:
			# Simple direction-based animation selection
			if abs(direction.x) > abs(direction.y):
				# Moving predominantly horizontally
				if direction.x > 0:
					anim_sprite.play("walk_right")
				else:
					anim_sprite.play("walk_left")
			else:
				# Moving predominantly vertically
				if direction.y > 0:
					anim_sprite.play("walk_down")
				else:
					anim_sprite.play("walk_up")

func interact() -> void:
	# Check if interactive but don't block based on dialogue_active
	if not is_interactive:
		return

	print("Starting interaction with NPC: ", npc_name)
	set_state(NpcState.TALKING)
	interaction_started.emit(npc_id)

	# Face the player
	var player = get_closest_player()
	if player:
		var direction = global_position.direction_to(player.global_position)
		update_animation(direction)

	# Get dialogue data
	var dialogue_data = get_dialogue()
	if not dialogue_data.has("npc_id"):
		dialogue_data["npc_id"] = npc_id

	# Use DialogueManager to start the dialogue
	var dialogue_manager = get_node_or_null("/root/DialogueManager")
	if dialogue_manager:
		# Make sure we always disconnect previous connections first
		if dialogue_manager.dialogue_ended.is_connected(_on_dialogue_ended):
			dialogue_manager.dialogue_ended.disconnect(_on_dialogue_ended)
		dialogue_manager.dialogue_ended.connect(_on_dialogue_ended, CONNECT_ONE_SHOT)
		
		# Start dialogue - only set dialogue_active to true if dialogue actually starts
		dialogue_active = true
		dialogue_manager.start_dialogue(dialogue_data)
	else:
		print("DialogueManager not found. NPC says: ", dialogue_data.get("text", "..."))
		end_interaction()

func _on_dialogue_ended(_npc_id: String) -> void:
	dialogue_active = false  # Make sure to reset this flag
	end_interaction()

func end_interaction() -> void:
	dialogue_active = false  # Reset in both places for safety
	if current_state == NpcState.TALKING:
		set_state(NpcState.IDLE)
		interaction_ended.emit(npc_id)

func get_closest_player() -> Node2D:
	# Find the closest player in the scene
	var players = get_tree().get_nodes_in_group("Player")
	if players.is_empty():
		return null
		
	var closest_player = players[0]
	var closest_distance = global_position.distance_squared_to(closest_player.global_position)
	
	for i in range(1, players.size()):
		var distance = global_position.distance_squared_to(players[i].global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_player = players[i]
	
	return closest_player

func take_damage(amount: int) -> void:
	health -= amount
	health = max(0, health)  # Don't go below 0
	health_changed.emit(health, max_health)
	
	if health <= 0:
		die()

func heal(amount: int) -> void:
	health += amount
	health = min(health, max_health)  # Don't exceed max health
	health_changed.emit(health, max_health)

func die() -> void:
	# Basic implementation - override in derived classes for specific death behaviors
	set_state(NpcState.BUSY)
	
	# Disable collision and interaction
	is_interactive = false
	
	# Here you would typically play a death animation
	if sprite_node is AnimatedSprite2D:
		var anim_sprite = sprite_node as AnimatedSprite2D
		if anim_sprite.sprite_frames.has_animation("death"):
			anim_sprite.play("death")
			await anim_sprite.animation_finished
	
	# After animation or immediately if no animation
	queue_free()  # Remove from scene
	# Alternative: hide() if you want to keep the NPC in the scene but invisible

func get_dialogue() -> Dictionary:
	# Override this in derived classes to provide specific dialogue
	return {
		"id": default_dialogue_id,
		"text": "Hello, I am %s." % npc_name,
		"options": []
	}

func _on_game_mode_changed(new_mode) -> void:
	# React to game mode changes (real-time vs turn-based)
	if game_state_manager.is_turn_based():
		# Stop movement in turn-based mode
		if current_state == NpcState.WALKING:
			set_state(NpcState.IDLE)
			velocity = Vector2.ZERO
	else:
		# Could resume movement in real-time mode if needed
		pass
