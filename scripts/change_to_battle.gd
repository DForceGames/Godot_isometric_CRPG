extends Area2D

## If set, this specific name will be used for the battle map scene file (without .tscn).
## If empty, the name of this Area2D node will be used.
@export var custom_battle_map_name: String = ""

## Path to the folder containing battle map scenes.
@export var battle_maps_folder_path: String = "res://maps/battle_maps/"

## Optional fade transition time in seconds. Set to 0 for instant transition.
@export var transition_time: float = 0.5

## Reference to GameStateManager (will be automatically populated in _ready)
var game_state_manager: Node

func _ready() -> void:
	# Connect the body_entered signal if not already connected
	if not is_connected("body_entered", Callable(self, "_on_body_entered")):
		connect("body_entered", Callable(self, "_on_body_entered"))
	
	# Get GameStateManager singleton
	game_state_manager = get_node_or_null("/root/GameStateManager")
	if not game_state_manager:
		printerr("ChangeToBattle: GameStateManager autoload not found! Scene transitions will work but game state won't change.")

func _on_body_entered(body: Node2D) -> void:
	if body is Player: # Check if body is of Player class type
		# Determine battle map name
		var battle_map_name = custom_battle_map_name
		if battle_map_name == "":
			battle_map_name = self.name  # Use the name of this Area2D node if no custom name is set

		# Construct path to battle map scene
		var battle_map_path = battle_maps_folder_path + battle_map_name + ".tscn"
		if not ResourceLoader.exists(battle_map_path):
			printerr("Battle map scene not found at path: ", battle_map_path)
			return
		
		# Switch to turn-based mode using GameStateManager
		if game_state_manager and game_state_manager.has_method("switch_to_turn_based"):
			print("Switching to TURN_BASED mode.")
			game_state_manager.switch_to_turn_based()
		else:
			push_warning("ChangeToBattle: Could not switch game mode - GameStateManager not found or missing method.")
		
		# Perform scene transition
		print("Changing to battle map: ", battle_map_path)
		
		# If transition effect is desired
		if transition_time > 0.0:
			# Optional: Implement simple transition using ColorRect
			var transition_rect = ColorRect.new()
			transition_rect.color = Color(0, 0, 0, 0) # Start transparent
			transition_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			
			# Add to scene tree as overlay
			get_tree().get_root().add_child(transition_rect)
			
			# Create tween for fade effect
			var tween = get_tree().create_tween()
			tween.tween_property(transition_rect, "color", Color(0, 0, 0, 1), transition_time)
			await tween.finished
			
			# Change scene after fade completes
			get_tree().change_scene_to_file(battle_map_path)

			# game_state_manager.player_spawn_position = body.position  # Update player position in GameStateManager
			# print("Player position updated in GameStateManager: ", game_state_manager.player_position)
			
			# Clean up
			transition_rect.queue_free()
		else:
			# No transition, change immediately
			get_tree().change_scene_to_file(battle_map_path)
			
		# Optional: Prevent re-entry if player returns to this spot
		monitoring = false
	else:
		print("Body entered is not in the player group, ignoring.")
