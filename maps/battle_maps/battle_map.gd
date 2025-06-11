extends Node2D

@onready var tilemap_layer: TileMapLayer = $Ground

@onready var player_spawn_points: Array[Marker2D] = [$PlayerSpawns/Spawn1]
@onready var enemy_spawn_points: Array[Marker2D] = [$EnemySpawns/Spawn1, $EnemySpawns/Spawn2, $EnemySpawns/Spawn3]

func _ready():
	var game_state_manager = get_node_or_null("/root/GameStateManager")
	var combat_manager = get_node_or_null("/root/CombatManager")
	var party_manager = get_node_or_null("/root/PartyManager")

	if not game_state_manager or not combat_manager or not party_manager:
		printerr("BattleMap: GameStateManager not found!")
		return
	combat_manager.set_active_tilemap(tilemap_layer)
	var battle_data = game_state_manager.pending_battle_data
	if battle_data.is_empty():
		printerr("BattleMap: No battle data found in GameStateManager!")
		return

	var spawned_party = []
	var party_to_spawn = party_manager.get_current_party()
	for i in range(party_to_spawn.size()):
		var party_member = party_to_spawn[i]
		if not is_instance_valid(party_member):
			printerr("BattleMap: Party member is not a valid instance: ", party_member)
			continue
		if i >= player_spawn_points.size():
			printerr("BattleMap: Not enough player spawn points for all party members!")
			break
		
		if party_member.get_parent():
			party_member.get_parent().remove_child(party_member)
		add_child(party_member)

		party_member.global_position = player_spawn_points[i].global_position
		spawned_party.append(party_member)

	var spawned_enemies: Array[Node] = []
	var enemy_to_spawn = battle_data["enemies"]
	print("BattleMap: Preparing to spawn enemies: ", enemy_to_spawn)

	for i in range(enemy_to_spawn.size()):
		var enemy = enemy_to_spawn[i]
		print("BattleMap: Spawning enemy: ", enemy, " for posistion ", i)
		if not typeof(enemy) == TYPE_STRING:
			printerr("BattleMap: Enemy path is not a string: ", enemy)
			spawned_enemies.append(enemy)
			continue

		var enemy_scene = load(enemy)
		if not enemy_scene:
			printerr("BattleMap: Enemy scene not found at path: ", enemy)
			continue

		var enemy_instance = enemy_scene.instantiate()
		add_child(enemy_instance)

		if i < enemy_spawn_points.size():
			enemy_instance.global_position = enemy_spawn_points[i].global_position
		
		print("BattleMap: Spawned enemy instance: ", enemy_instance, " at position: ", enemy_spawn_points[i].global_position)
		spawned_enemies.append(enemy_instance)
		print("BattleMap: Current spawned enemies: ", spawned_enemies)
	
	game_state_manager.switch_to_turn_based()
	# print("--- Preparing to start combat ---")
	# print("Spawned Party: ", spawned_party)
	# print("Spawned Enemies: ", spawned_enemies)
	combat_manager.start_combat(spawned_party, spawned_enemies)

	game_state_manager.pending_battle_data.clear()
