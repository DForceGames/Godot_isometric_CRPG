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

# Optional: Add functions to pause/resume parts of the game,
