extends Node

signal dialogue_started(npc_id: String)
signal dialogue_ended(npc_id: String)

var dialogue_ui: DialogueUI
var is_dialogue_active: bool = false
var current_npc_id: String = ""
var current_dialogue: Dictionary
var last_selected_option: String = ""
var dialogue_history: Dictionary = {}

func _ready() -> void:
	print("DialogueManager: Ready")
	# Create the UI if it doesn't exist
	_ensure_dialogue_ui_exists()

func _ensure_dialogue_ui_exists() -> void:
	# Check if UI already exists
	dialogue_ui = get_node_or_null("/root/DialogueUI")
	print("DialogueManager: Looking for existing DialogueUI:", dialogue_ui != null)
	
	if not dialogue_ui:
		# Create UI from scene
		var scene_path = "res://scenes/ui/dialogue_ui.tscn"
		print("DialogueManager: Loading DialogueUI from:", scene_path)
		
		var scene = load(scene_path)
		if scene:
			dialogue_ui = scene.instantiate()
			get_tree().root.add_child.call_deferred(dialogue_ui)
			print("DialogueManager: Created dialogue UI successfully")
			
			# Wait one frame to ensure _ready is called
			await get_tree().process_frame
			print("DialogueManager: DialogueUI ready after frame")
		else:
			printerr("DialogueManager: Failed to load dialogue UI scene at path:", scene_path)

func start_dialogue(dialogue_data: Dictionary) -> void:
	print("DialogueManager: Starting dialogue with: ", dialogue_data)
	
	# Make sure UI exists
	_ensure_dialogue_ui_exists()
	
	if not dialogue_ui:
		printerr("DialogueManager: No dialogue UI available!")
		return
	
	# Set dialogue data
	current_dialogue = dialogue_data
	current_npc_id = dialogue_data.get("npc_id", "")
	is_dialogue_active = true
	
	# Update UI
	dialogue_ui.set_dialogue_text(dialogue_data.get("text", ""))
	dialogue_ui.set_dialogue_options(dialogue_data.get("options", []))
	
	# Show UI
	dialogue_ui.show()
	
	# Pause game
	get_tree().paused = true
	
	# Emit signal
	dialogue_started.emit(current_npc_id)

func select_option(option_id: String) -> void:
	print("DialogueManager: Option selected: " + option_id)
	
	# Store last selected option
	last_selected_option = option_id
	
	# Store in history
	if not dialogue_history.has(current_npc_id):
		dialogue_history[current_npc_id] = {}
	dialogue_history[current_npc_id]["last_option"] = option_id
	
	# Check if this option leads to more dialogue
	var next_dialogue = null
	for option in current_dialogue.get("options", []):
		if option.get("id") == option_id and option.has("next_dialogue"):
			next_dialogue = option.get("next_dialogue")
			break
	
	if next_dialogue:
		# Continue with next dialogue
		next_dialogue["npc_id"] = current_npc_id  # Preserve NPC ID
		start_dialogue(next_dialogue)
	else:
		# End dialogue
		end_dialogue()

func end_dialogue() -> void:
	if not is_dialogue_active:
		return
		
	# Hide UI
	dialogue_ui.hide()
	
	# Reset state
	is_dialogue_active = false
	
	# Unpause game
	get_tree().paused = false
	
	# Emit signal
	dialogue_ended.emit(current_npc_id)
	current_npc_id = ""

func get_last_selected_option() -> String:
	return last_selected_option

func get_npc_dialogue_state(npc_id: String, key: String) -> Variant:
	if dialogue_history.has(npc_id) and dialogue_history[npc_id].has(key):
		return dialogue_history[npc_id][key]
	return null

func set_npc_dialogue_state(npc_id: String, key: String, value: Variant) -> void:
	if not dialogue_history.has(npc_id):
		dialogue_history[npc_id] = {}
	dialogue_history[npc_id][key] = value
	print("DialogueManager: Set state for NPC ", npc_id, ", ", key, " = ", value)
