extends Control
class_name DialogueUI

var dialogue_text: Label
var options_container: Container
var option_template: Button

func _ready():
	print("DialogueUI: _ready called")
	
	# Fix the layout positioning - CRITICAL!
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_right = 0  # Remove the -1152 offset that's pushing it off-screen
	offset_bottom = 0 # Remove the -650 offset that's pushing it off-screen
	offset_top = 0    # Also fix top offset
	
	# Find our UI components - we expect these to exist in the scene
	dialogue_text = $PanelContainer/VBoxContainer/NPCDialogue
	options_container = $PanelContainer/VBoxContainer/OptionsContainer
	option_template = $PanelContainer/VBoxContainer/OptionsContainer/OptionTemplate
	
	print("DialogueUI: Found components:", 
		dialogue_text != null, 
		options_container != null,
		option_template != null)
	
	# Start hidden
	hide()

func set_dialogue_text(text: String) -> void:
	dialogue_text.text = text
	print("DialogueUI: Set text to: " + text)

func set_dialogue_options(options: Array) -> void:
	# Clear existing options
	for child in options_container.get_children():
		if child != option_template:
			child.queue_free()
	
	# Add new options
	for option in options:
		var button = option_template.duplicate()
		button.text = option.get("text", "...")
		button.visible = true
		
		# Store option ID in button metadata
		var option_id = option.get("id", "")
		button.set_meta("option_id", option_id)
		
		# Connect button press
		button.pressed.connect(func(): _on_option_selected(option_id))
		
		options_container.add_child(button)
		print("DialogueUI: Added option: " + button.text)

func _on_option_selected(option_id: String) -> void:
	print("DialogueUI: Option selected: " + option_id)
	var dialogue_manager = get_node_or_null("/root/DialogueManager")
	if dialogue_manager:
		dialogue_manager.select_option(option_id)
