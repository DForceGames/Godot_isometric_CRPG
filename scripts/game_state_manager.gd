extends Node

var player_spawn_position: Vector2 = Vector2.ZERO
var opened_containers: Array = []

var current_combat_instance: Node = null
var exploration_scene_node: Node = null # To return to

@export var combat_scene_path = "res://scenes/combat/combat_scene.tscn"

enum GameMode {
	REAL_TIME,
	TURN_BASED
}

var current_mode: GameMode = GameMode.REAL_TIME:
	set(new_mode):
		if current_mode != new_mode:
			current_mode = new_mode
			game_mode_changed.emit(current_mode)
			print("Game mode switched to: ", GameMode.keys()[current_mode])

signal game_mode_changed(new_mode: GameMode)
signal combat_setup_finished # Emitted after combat scene is ready, before first turn

func switch_to_real_time():
	self.current_mode = GameMode.REAL_TIME

func switch_to_turn_based():
	self.current_mode = GameMode.TURN_BASED
	# Get current enemy in scene if not already set
	# Check for enemies in the current scene
	var enemies = get_tree().get_nodes_in_group("enemies")
	if not enemies.is_empty():
		var enemy_node = enemies.front()
		print("Found enemy for turn-based mode: ", enemy_node.name)
	else:
		print("No enemies found in current scene for turn-based mode")
	
	# Note: This is just preparation for turn-based mode
	# Actual combat initialization happens in start_combat_sequence

func start_combat_sequence(player_nodes_in_party: Array[Node], encounter_data: EncounterData):
	if current_combat_instance != null:
		printerr("GameFlowManager: Combat already in progress.")
		return

	# Store reference to current scene
	exploration_scene_node = get_tree().current_scene
	
	# Switch to turn-based mode
	self.current_mode = GameMode.TURN_BASED

	# 2. Instantiate Enemy Nodes
	var enemy_nodes_for_combat: Array[Node] = []
	if not encounter_data:
		printerr("GameFlowManager: No encounter data provided!")
		return

	for enemy_def in encounter_data.enemy_group_definitions:
		var scene_path: String = enemy_def.get("scene_path")
		var count: int = enemy_def.get("count", 1)

		var enemy_scene_packed: PackedScene = load(scene_path)
		if not enemy_scene_packed:
			printerr("GameFlowManager: Failed to load enemy scene: %s" % scene_path)
			continue
		for _i in range(count):
			var enemy_instance = enemy_scene_packed.instantiate()
			enemy_nodes_for_combat.append(enemy_instance)

	if enemy_nodes_for_combat.is_empty():
		printerr("GameFlowManager: No enemies instantiated for combat!")
		return

	# 3. Load and instance the combat scene
	var combat_scene_packed: PackedScene = load(combat_scene_path)
	if not combat_scene_packed:
		printerr("GameFlowManager: Failed to load combat scene at %s" % combat_scene_path)
		return
	current_combat_instance = combat_scene_packed.instantiate()

	# 4. Add combatants to the combat scene
	var player_spawn_root = current_combat_instance.get_node_or_null("PlayerSpawnArea")
	var enemy_spawn_root = current_combat_instance.get_node_or_null("EnemySpawnArea")

	if not player_spawn_root or not enemy_spawn_root:
		printerr("GameFlowManager: CombatScene is missing PlayerSpawnArea or EnemySpawnArea nodes.")
		current_combat_instance.queue_free()
		current_combat_instance = null
		return

	var final_player_nodes_in_combat_scene: Array[Node] = []
	for p_node in player_nodes_in_party:
		if is_instance_valid(p_node.get_parent()):
			p_node.get_parent().remove_child(p_node)
		player_spawn_root.add_child(p_node)
		final_player_nodes_in_combat_scene.append(p_node)

	var final_enemy_nodes_in_combat_scene: Array[Node] = []
	for e_node in enemy_nodes_for_combat:
		enemy_spawn_root.add_child(e_node)
		final_enemy_nodes_in_combat_scene.append(e_node)

	# 5. Add the combat scene to the tree and make current
	get_tree().root.add_child(current_combat_instance)

	# 6. Get the CombatManager from the instanced scene and initialize it
	var combat_manager = current_combat_instance.get_node_or_null("CombatManager")
	if combat_manager and combat_manager.has_method("initialize_combat_encounter"):
		if not combat_manager.combat_ended.is_connected(_on_combat_manager_combat_ended):
			combat_manager.combat_ended.connect(_on_combat_manager_combat_ended)

		await get_tree().process_frame 
		emit_signal("combat_setup_finished")
		combat_manager.initialize_combat_encounter(final_player_nodes_in_combat_scene, final_enemy_nodes_in_combat_scene)
	else:
		printerr("GameFlowManager: CombatManager node or method not found in CombatScene!")
		_cleanup_combat_scene()

func _on_combat_manager_combat_ended(_result: String):
	# Handle rewards, player state changes based on result
	# ...

	_cleanup_combat_scene()

	# Return player party to exploration scene / party manager control
	var party_nodes = PartyManager.get_current_combat_party_nodes() # Get from PartyManager
	for p_node in party_nodes:
		if is_instance_valid(p_node.get_parent()): # Should be in combat scene's spawn area
			p_node.get_parent().remove_child(p_node)
		# Add back to the exploration scene or a persistent player party node
		# This part needs care based on your scene structure
		# exploration_scene_node.get_node("PlayerPartyHolder").add_child(p_node) # Example
		# p_node.visible = true # Make them visible again

	# Restore exploration scene
	# if is_instance_valid(exploration_scene_node):
	#    exploration_scene_node.set_process(true)
	#    exploration_scene_node.visible = true
	#    get_tree().current_scene = exploration_scene_node # If it was changed
	print("GameFlowManager: Combat ended, returning to exploration (logic placeholder).")

func _cleanup_combat_scene():
	if is_instance_valid(current_combat_instance):
		# Enemy nodes are children of current_combat_instance (in EnemySpawnArea)
		# so they will be freed when the combat scene is freed.
		# Player nodes were reparented, they need to be handled separately (moved back).
		current_combat_instance.queue_free()
		current_combat_instance = null

func is_real_time() -> bool:
	return current_mode == GameMode.REAL_TIME

func is_turn_based() -> bool:
	return current_mode == GameMode.TURN_BASED

# Optional: Add functions to pause/resume parts of the game,
