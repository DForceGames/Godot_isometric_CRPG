# The Final Enemy.gd Script
extends CharacterBody2D # It's better to use CharacterBody2D for physics and movement

@export var stats: Stats

# This script will connect to signals when it's ready.
func _ready():
	var combat_manager = get_node_or_null("/root/CombatManager")
	if combat_manager:
		# Connect to the turn_started signal with our new, correct handler
		if not combat_manager.turn_started.is_connected(_on_turn_started):
			combat_manager.turn_started.connect(_on_turn_started)
		
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
		execute_turn()

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

func execute_turn():
	print("Executing turn for: ", name)

	var closest_player = null
	var min_distance = INF

	# This name must match the function in your PartyManager!
	for player_character in PartyManager.get_current_party():
		# Safety check for the player character
		if not is_instance_valid(player_character):
			continue
			
		var distance = self.global_position.distance_to(player_character.global_position)
		if distance < min_distance:
			min_distance = distance
			closest_player = player_character

	# This block now correctly runs AFTER the loop has finished.
	if closest_player:
		print("Closest player to %s is %s." % [name, closest_player.name])
		# TODO: Add attack logic here (e.g., if stats.spend_ap(2): closest_player.take_damage...)
		
	
	print("Turn executed for enemy: ", name)
	
	# End the turn AFTER all logic is complete.
	CombatManager.change_state(CombatManager.CombatState.CHOOSING_COMBATANT)


# --- Utility Function ---
func take_damage(damage_amount):
	if not stats:
		return
	stats.take_damage(damage_amount)

func is_dead() -> bool:
	if not stats: return true
	return not stats.is_alive()
