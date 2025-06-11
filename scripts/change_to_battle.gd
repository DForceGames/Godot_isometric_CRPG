extends Area2D

@export var enemy_scene_path: Array[String]
@export var battle_scene_name: String = ""

var has_been_triggered: bool = false

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D):
	if has_been_triggered or not body is Player:
		print("ChangeToBattle: Already triggered or body is not a Player.")
		return
	
	if enemy_scene_path.is_empty() or battle_scene_name.is_empty():
		printerr("ChangeToBattle: Missing enemy or battle scene path!")
		return
	has_been_triggered = true

	var battle_map_path = "res://maps/battle_maps/" + battle_scene_name + ".tscn"
	if not ResourceLoader.exists(battle_map_path):
		printerr("ChangeToBattle: Battle map not found at path: ", battle_map_path)
		return
	
	var battle_data: Dictionary = {
		"enemies": enemy_scene_path,
		"battle_map": battle_map_path
	}

	var game_state_manager = get_node_or_null("/root/GameStateManager")
	if game_state_manager:
		print("|-----------Change Scene to Battle-----------|")
		print("ChangeToBattle: Preparing for battle with data: ", battle_data)
		game_state_manager.prepare_for_battle(battle_data)
	