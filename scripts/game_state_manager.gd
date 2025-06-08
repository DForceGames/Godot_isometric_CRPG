extends Node

var player_spawn_position: Vector2 = Vector2.ZERO
var opened_containers: Array = []

var current_combat_instance: Node = null
var exploration_scene_node: Node = null # To return to

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

# Battle variables
var pending_battle_data: Dictionary = {} 
var return_to_scene: String = ""
var return_to_position: Vector2 = Vector2.ZERO

signal game_mode_changed(new_mode: GameMode)

func switch_to_real_time():
	self.current_mode = GameMode.REAL_TIME

func switch_to_turn_based():
	self.current_mode = GameMode.TURN_BASED
	var player_party = PartyManager.get_current_party()
	var enemies = get_tree().get_nodes_in_group("enemies")

	var combat_manager = get_node_or_null("/root/CombatManager")
	combat_manager.start_combat(player_party, enemies)
	UiManager.show_battle_ui()

func is_real_time() -> bool:
	return current_mode == GameMode.REAL_TIME

func is_turn_based() -> bool:
	return current_mode == GameMode.TURN_BASED

func prepare_for_battle(battle_data: Dictionary):
	pending_battle_data = battle_data
	return_to_scene = get_tree().current_scene.scene_file_path

	var player = get_tree().get_first_node_in_group("Player")
	if player:
		return_to_position = player.global_position

	get_tree().change_scene_to_file(battle_data["battle_map"])
	
