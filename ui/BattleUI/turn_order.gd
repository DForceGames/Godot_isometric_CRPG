extends Control

@export var playerBackgroundColor := Color(0,1,0, 0.5) # Added some alpha
@export var enemyBackgroundColor := Color(1,0,0, 0.5)  # Added some alpha
@export var neutralBackgroundColor := Color(0.5, 0.5, 0.5, 0.5) # Example for neutral

@onready var character_container: HBoxContainer = %CharacterContainer

const CHARACTER_DISPLAY_CONTAINER: PackedScene = preload("res://UI/gameui/character_icon_display.tscn") # Ensure this path is correct

var character_node_list: Array[Node] = [] # Stores character nodes from CombatManager

func _ready() -> void:
	# Attempt to connect to CombatManager.
	# CombatManager should be in a group "CombatManager" or be an autoload.
	await get_tree().process_frame # Wait a frame for autoloads/scene tree to be fully ready
	var combat_manager_node = get_tree().get_first_node_in_group("CombatManager") 
	if combat_manager_node:
		if not combat_manager_node.is_connected("turn_order_updated", Callable(self, "_on_turn_order_updated")):
			combat_manager_node.turn_order_updated.connect(_on_turn_order_updated)
		print("TurnOrderUI connected to CombatManager.")
	else:
		printerr("TurnOrderUI: CombatManager node not found in group 'CombatManager'. UI will not update turn order.")
	
	_refresh_bar() # Initial refresh (likely empty until combat starts)

func _on_turn_order_updated(new_character_node_order : Array[Node]):
	character_node_list = new_character_node_order
	_refresh_bar()
	
func _refresh_bar():
	if not is_inside_tree(): return # Avoid errors if called after node is removed
	
	# Using call_deferred to ensure UI updates happen after other processing
	call_deferred("_deferred_refresh_bar_contents")

func _deferred_refresh_bar_contents():
	if not is_instance_valid(character_container): return

	_clear_data()
	
	for character_node in character_node_list:
		if not is_instance_valid(character_node): 
			printerr("TurnOrderUI: Invalid character node in turn order list.")
			continue

		var character_display_node = CHARACTER_DISPLAY_CONTAINER.instantiate()
		
		# Get character_type from the TurnBasedAgent script on the character_node
		# This assumes the character_node itself IS or HAS a TurnBasedAgent component.
		var agent_script: TurnBasedAgent = null
		if character_node is TurnBasedAgent:
			agent_script = character_node
		else: # Try to find it as a child
			agent_script = character_node.get_node_or_null("TurnBasedAgent") # Adjust name if needed

		if not is_instance_valid(agent_script):
			printerr("TurnOrderUI: Character node '%s' does not have a TurnBasedAgent script/component. Skipping." % character_node.name)
			character_display_node.queue_free() 
			continue

		var char_type = agent_script.character_type

		var styleBox = character_display_node.get_theme_stylebox("panel").duplicate() # Duplicate to avoid modifying shared resource
		
		match char_type:
			TurnBasedAgent.Character_Type.PLAYER:
				styleBox.bg_color = playerBackgroundColor
			TurnBasedAgent.Character_Type.ENEMY:
				styleBox.bg_color = enemyBackgroundColor
			TurnBasedAgent.Character_Type.NEUTRAL:
				styleBox.bg_color = neutralBackgroundColor
			_: # Default case
				styleBox.bg_color = Color.GRAY # Fallback color

		character_display_node.add_theme_stylebox_override("panel", styleBox)
		
		# TODO: Set character icon/name on characterDisplayNode if it has those elements
		# Example:
		# if character_display_node.has_node("NameLabel"):
		#    character_display_node.get_node("NameLabel").text = character_node.name
		# if character_display_node.has_node("Portrait") and agent_script.has_method("get_portrait_texture"):
		#    character_display_node.get_node("Portrait").texture = agent_script.get_portrait_texture()

		character_container.add_child(character_display_node)
	
func _clear_data():
	if not is_instance_valid(character_container): return
	for child in character_container.get_children():
		child.queue_free()
