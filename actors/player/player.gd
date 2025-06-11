extends CharacterBody2D
class_name Player

var speed: float = 100.0
@export var interaction_groups: Array[String] = ["interactable", "NPC", "Container", "pickup"]

# Player Stats, further stats are in the shared stats.gd
var player_name: String = "Player"
var experience: int = 0
@export var stats: Stats

# References
var game_state_manager
var combat_manager
var interaction_distance: float = 64.0
var current_nearby_npc: NPC = null
var is_my_turn: bool = false
@onready var movement_system = $PlayerMovement

# Signals


func _ready() -> void:
	# Register player in PartyManager
	PartyManager.register_main_character(self)
	print("Player: Registered main character with PartyManager")
	
	await get_tree().process_frame
	# Get GameStateManager
	game_state_manager = get_node_or_null("/root/GameStateManager")
	if game_state_manager:
		game_state_manager.game_mode_changed.connect(_on_game_mode_changed)

	combat_manager = get_node_or_null("/root/CombatManager")
	if combat_manager:
		combat_manager.combat_started.connect(on_combat_started)
		combat_manager.combat_ended.connect(on_combat_ended)
		combat_manager.turn_started.connect(on_combat_manager_turn_started)
	
	# Get player stats
	if not stats:
		printerr("Player: No stats resource assigned!")
		return
	stats.initialize_stats()
	stats.health_changed.connect(_on_health_changed)
	stats.ap_changed.connect(_on_ap_changed)
	# stats.sp_changed.connect(_on_sp_changed)
	stats.died.connect(_on_died)

func _input(event: InputEvent) -> void:
	if combat_manager and combat_manager.is_combat_ended and not is_my_turn:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
		if movement_system.is_in_targeting_mode:
			movement_system.stop_targeting_mode()
			return
		var target_pos = get_global_mouse_position()
		movement_system.set_movement_target(target_pos)
		print("Player: Right-clicked to move to position ", target_pos)
	

# Combat handlers -------------------------------------------------------------

func on_combat_started(_turn_queue):
	is_my_turn = false

func on_combat_ended():
	is_my_turn = false

func on_combat_manager_turn_started(combatant):
	if combatant == self:
		is_my_turn = true
		stats.on_turn_started(combatant)
	else:
		is_my_turn = false
		print("Player: Not my turn anymore")

func _on_health_changed(current_health, max_health):
	emit_signal("health_changed", current_health, max_health)

func _on_ap_changed(current_ap, max_ap):
	emit_signal("ap_changed", current_ap, max_ap)

func _on_died():
	$AnimatedSprite2D.play("Death")
	emit_signal("died", self)

func take_damage(damage_amount):
	if not stats:
		return
	stats.take_damage(damage_amount)

func is_dead() -> bool:
	if not stats: return true
	return not stats.is_alive()

# Simple function to tell movement system where to go
func _on_game_mode_changed(new_mode):
	if movement_system:
		movement_system._handle_game_mode_changed(new_mode)

func _physics_process(_delta: float) -> void:
	if velocity.length_squared() > 0:
		move_and_slide()

	_update_player_animations()

func _update_player_animations() -> void:
	var anim_sprite = $AnimatedSprite2D
	if not anim_sprite or not anim_sprite.has_method("play"):
		return
		
	if velocity == Vector2.ZERO:
		if anim_sprite.animation != "Idle":
			anim_sprite.play("Idle")
		return
			
	var target_animation = ""
	if velocity.x < -0.01: # Moving significantly left
		target_animation = "Walking_Left"
	elif velocity.x > 0.01: # Moving significantly right
		target_animation = "Walking_Right"
	else: # Moving predominantly vertically
		if anim_sprite.animation == "Walking_Left" or anim_sprite.animation == "Walking_Right":
			target_animation = anim_sprite.animation
		else:
			target_animation = "Walking_Right"
	
	if anim_sprite.animation != target_animation:
		anim_sprite.play(target_animation)

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

