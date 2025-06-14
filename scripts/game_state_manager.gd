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
	game_mode_changed.emit(current_mode)

func switch_to_turn_based():
	self.current_mode = GameMode.TURN_BASED
	game_mode_changed.emit(current_mode)
	UiManager.show_battle_ui()

func is_real_time() -> bool:
	return current_mode == GameMode.REAL_TIME

func is_turn_based() -> bool:
	return current_mode == GameMode.TURN_BASED

func prepare_for_battle(battle_data: Dictionary):
	self.pending_battle_data = battle_data
	print("GameStateManager: Preparing for battle with data: ", battle_data)

	self.return_to_scene = get_tree().current_scene.scene_file_path
	var player = PartyManager.main_character
	if is_instance_valid(player):
		self.return_to_position = player.global_position

	PartyManager.make_party_persistent_for_transition()

	get_tree().call_deferred("change_scene_to_file", battle_data["battle_map"])

func return_to_exploration():
	if not return_to_scene:
		printerr("GameStateManager: No return scene set!")
		return
	var player = PartyManager.main_character
	if not is_instance_valid(player) and is_instance_valid(return_to_position):
		printerr("GameStateManager: Main character is not valid!")
		return

	PartyManager.make_party_persistent_for_transition()
	player.global_position = return_to_position
	switch_to_real_time()
	print("GameStateManager: Returning to exploration scene: ", return_to_scene, " at position: ", return_to_position)
	print("GameStateManager: current gamemode is now: ", current_mode)
	get_tree().call_deferred("change_scene_to_file", return_to_scene)
