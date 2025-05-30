extends Button

var game_state_manager

func _ready() -> void:
	# Assuming GameStateManager is an autoload singleton
	game_state_manager = get_node_or_null("/root/GameStateManager")
	if not game_state_manager:
		printerr("ToggleGameModeButton: GameStateManager autoload not found!")
		set_process_unhandled_input(false) # Disable button if manager not found
		disabled = true
		text = "Error: GSM Not Found"
		return

	# Connect the pressed signal
	self.pressed.connect(_on_button_pressed)
	
	# Set initial button text
	update_button_text()

func _on_button_pressed() -> void:
	if not game_state_manager:
		return

	if game_state_manager.is_real_time():
		game_state_manager.switch_to_turn_based()
	elif game_state_manager.is_turn_based():
		game_state_manager.switch_to_real_time()
	
	update_button_text()

func update_button_text() -> void:
	if not game_state_manager:
		return
	
	if game_state_manager.is_real_time():
		text = "Switch to Turn-Based"
	else:
		text = "Switch to Real-Time"

# Optional: If you want the button text to update if the mode is changed by something else
# you can connect to the game_mode_changed signal.
# func _init(): # Or _ready, but _init is slightly earlier if no node tree access needed
# 	var gsm = get_node_or_null("/root/GameStateManager")
# 	if gsm:
# 		gsm.game_mode_changed.connect(func(_new_mode): update_button_text())
# Note: Connecting in _init like this might be tricky if the button isn't in tree yet
# when GameStateManager emits for the first time. _ready is safer.
# For this button, since it *causes* the change, direct update is fine.
# If other systems could change the state, then connecting to the signal is robust.
# Let's add it to _ready for robustness.

func _enter_tree() -> void:
	# Re-check and connect if the button is added to the scene dynamically
	# or if GameStateManager might not be ready when _ready is first called.
	if not game_state_manager:
		game_state_manager = get_node_or_null("/root/GameStateManager")
	if game_state_manager and not game_state_manager.game_mode_changed.is_connected(Callable(self, "on_game_mode_changed_externally")):
		game_state_manager.game_mode_changed.connect(on_game_mode_changed_externally)
	update_button_text()

func on_game_mode_changed_externally(_new_mode) -> void:
	update_button_text()
