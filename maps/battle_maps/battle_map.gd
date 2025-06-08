extends Node2D

@onready var player_spawn_points: Array[Marker2D] = [$PlayerSpawns/Spawn1]
@onready var enemy_spawn_points: Array[Marker2D] = [$EnemySpawns/Spawn1, $EnemySpawns/Spawn2, $EnemySpawns/Spawn3]

func _ready():
	var game_state_manager = get_node_or_null("/root/GameStateManager")
	if not game_state_manager:
		printerr("BattleMap: GameStateManager not found!")
		return
	
	var battle_data = game_state_manager.pending_battle_data

	var spawned_party = []
	var party_to_spawn = PartyManager.get_current_party()
	for i in range(party_to_spawn.size()):
		var party_member = party_to_spawn[i]
		if i >= player_spawn_points.size():
			printerr("BattleMap: Not enough player spawn points for all party members!")
			break
		
		if party_member.get_parent():
			party_member.get_parent().remove_child(party_member)
		add_child(party_member)

		party_member.global_position = player_spawn_points[i].global_position
		spawned_party.append(party_member)

	var enemies = []
	var enemy_to_spawn = battle_data["enemies"]
	for i in range(enemy_to_spawn.size()):
		var enemy = enemy_to_spawn[i]
		if i >= enemy_spawn_points.size():
			printerr("BattleMap: Not enough enemy spawn points for all enemies!")
			break
		
		var enemy_scene = load(enemy)
		if not enemy_scene:
			printerr("BattleMap: Enemy scene not found at path: ", enemy)
			continue
		
		var enemy_instance = enemy_scene.instantiate()
		add_child(enemy_instance)
		enemy_instance.global_position = enemy_spawn_points[i].global_position
		enemies.append(enemy)
	
	game_state_manager.switch_to_turn_based()
	CombatManager.start_combat(spawned_party, enemies)

	game_state_manager.pending_battle_data.clear()
