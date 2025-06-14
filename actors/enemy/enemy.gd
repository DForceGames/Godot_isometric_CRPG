# The Final Enemy.gd Script
extends CharacterBody2D # It's better to use CharacterBody2D for physics and movement

@export var stats: Stats
var speed: float = 100.0  # Speed of the enemy, can be adjusted in the editor

signal movement_finished # Signal to indicate movement is done

# This script will connect to signals when it's ready.
func _ready():
	var combat_manager = get_node_or_null("/root/CombatManager")
	if combat_manager:
		# Connect to the turn_started signal with our new, correct handler
		# if not combat_manager.turn_started.is_connected(_on_turn_started):
		# 	combat_manager.turn_started.connect(_on_turn_started)
		
		# Also, let's connect to the combat_ended signal for cleanup
		if not combat_manager.combat_ended.is_connected(_on_combat_ended):
			combat_manager.combat_ended.connect(_on_combat_ended)
	
	if not stats:
		printerr("Enemy: No stats resource assigned!")
		return
	stats.initialize_stats()
	# stats.health_changed.connect(_on_health_changed)
	# stats.ap_changed.connect(_on_ap_changed)
	# stats.sp_changed.connect(_on_sp_changed)
	stats.died.connect(_on_died)

# --- Signal Handlers ---

func _on_turn_started(combatant: Node):
	# This function runs every time ANYONE's turn starts.
	# We check if the turn is for this specific instance.
	if combatant == self:
		print("Enemy '", name, "': My turn has begun!")
		
		# Replenish stats and then execute the AI logic
		if stats:
			stats.on_turn_started(combatant)
		# execute_turn()

func _on_combat_ended(_result: String):
	# When combat is over, this enemy should be removed from the battle map.
	print("Enemy '", name, "': Combat is over. Fading away...")
	queue_free()

func _on_died():
	# This function is called when the enemy's stats indicate it has died.
	print("Enemy '%s' has died." % name)
	CombatManager.turn_queue.erase(self)  # Remove this enemy from the turn queue
	queue_free()  # Remove the enemy from the scene when it dies

# --- AI and Action Logic ---

func follow_path(path) -> void:
	if path.is_empty():
		printerr("Enemy: No path to follow!")
		movement_finished.emit()  # Ensure signal is emitted even if path is empty
		return
	
	var path_copy = path.duplicate()  # Create a copy to avoid modifying the original
	var max_steps = 20  # Limit maximum steps to prevent infinite loops
	var step_count = 0
	
	for waypoint in path_copy:
		var timeout_timer = 0.0
		var max_time = 2.0  # Maximum time in seconds to try reaching a waypoint
		
		while global_position.distance_to(waypoint) > 5:  # Using a small threshold
			velocity = global_position.direction_to(waypoint) * speed
			move_and_slide()
			await get_tree().physics_frame  # Wait for the next physics frame
			
			# Safety timeout check to prevent getting stuck
			timeout_timer += get_process_delta_time()
			if timeout_timer > max_time:
				print("Enemy reached timeout while moving to waypoint")
				break
		
		global_position = waypoint  # Snap to the waypoint
		velocity = Vector2.ZERO  # Stop movement
		# Update entity position in CombatManager
		CombatManager.update_combatant_position(self, CombatManager.world_to_map(global_position))

		# Safety check to prevent infinite loops
		step_count += 1
		if step_count >= max_steps:
			print("Enemy reached maximum movement steps")
			break
	
	# Signal completion after all waypoints
	movement_finished.emit()  # Emit signal that movement is finished

# --- Utility Function ---
func take_damage(damage_amount):
	if not stats:
		return
	stats.take_damage(damage_amount)

func is_dead() -> bool:
	if not stats: return true
	return not stats.is_alive()
