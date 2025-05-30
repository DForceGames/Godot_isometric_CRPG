extends Node

var player_spawn_position: Vector2 = Vector2.ZERO
var opened_containers: Array = []

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

func is_real_time() -> bool:
	return current_mode == GameMode.REAL_TIME

func is_turn_based() -> bool:
	return current_mode == GameMode.TURN_BASED

# Optional: Add functions to pause/resume parts of the game,
