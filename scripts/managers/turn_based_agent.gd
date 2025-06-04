extends Node
# class_name TurnBasedAgent # Important for type hinting

# Emitted when player confirms a target for the prepared command
signal target_selected(target_node: Node, command_data: AbilityData)
# Emitted if player cancels targeting (e.g. presses Esc/Back)
signal undo_targeting_requested 

@export var character_type: Character_Type = Character_Type.NEUTRAL # Default
@export var onTurnIconOffSet: Vector2 = Vector2(0,-50)
@export var targetIconOffSet: Vector2 = Vector2(50,0)

@onready var on_turn_icon_node: TextureRect = $onTurnIconNode
@onready var target_icon_node: TextureRect = $targetIconNode

enum Character_Type {PLAYER, ENEMY, NEUTRAL}

var is_active: bool = false # Is it this agent's turn? (Set by CombatManager)
var is_selecting_target: bool = false # Is player currently in targeting mode for this agent?

var _current_command_for_targeting: AbilityData = null
var _current_selected_target_node: Node = null # The actual node being targeted

# func get_global_position(): # Position of the agent's parent (the character visual)
#     if get_parent() is Node2D:
#         return get_parent().global_position
#     return global_position # Fallback if agent is not child of Node2D

func _unhandled_input(event: InputEvent) -> void:
	if not is_active or not is_selecting_target or character_type != Character_Type.PLAYER:
		return # Only active players in targeting mode process this input

	# TODO: Implement robust target cycling based on _current_command_for_targeting.valid_target_types
	# For now, let's assume a simple cycling through "enemy" or "player" groups.
	var potential_targets_group_name = "enemy" # Default, should be derived from ability
	if _current_command_for_targeting and _current_command_for_targeting.target_type == AbilityData.TargetType.ALLY: # Example
		potential_targets_group_name = "player"
	
	var potential_targets: Array[Node] = get_tree().get_nodes_in_group(potential_targets_group_name)
	potential_targets = potential_targets.filter(func(n): return is_instance_valid(n) and n != get_parent()) # Filter self if not allowed

	if potential_targets.is_empty():
		return

	# Initialize target if none selected or current is invalid
	if not is_instance_valid(_current_selected_target_node) or not _current_selected_target_node in potential_targets:
		_select_new_target_node(potential_targets[0], potential_targets) # Select first valid

	if _cycle_targets(event, potential_targets):
		get_tree().set_input_as_handled()
		return

	if event.is_action_pressed("ui_accept"):
		if is_instance_valid(_current_selected_target_node):
			_confirm_target_selection()
		get_tree().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_cancel_targeting_input()
		get_tree().set_input_as_handled()

# Called by CombatManager when player has chosen an ability and needs to pick a target
func prepare_to_select_target(command: AbilityData):
	if character_type != Character_Type.PLAYER or not is_active: return

	_current_command_for_targeting = command
	is_selecting_target = true
	set_process_unhandled_input(true)
	
	# TODO: Get initial valid targets based on 'command.valid_target_types' (e.g. enemies, allies, range)
	# For now, simplified:
	var initial_targets_group = "enemy" # Default
	if command.target_type == AbilityData.TargetType.ALLY: initial_targets_group = "player"

	var potential_targets: Array[Node] = get_tree().get_nodes_in_group(initial_targets_group)
	potential_targets = potential_targets.filter(func(n): return is_instance_valid(n) and n != get_parent())


	_deselect_all_targets_visually() # Clear previous target icons
	if not potential_targets.is_empty():
		_select_new_target_node(potential_targets[0], potential_targets)
	else:
		_current_selected_target_node = null
		print("No valid initial targets for: ", command.ability_name)


func _cycle_targets(event: InputEvent, available_targets: Array[Node]) -> bool:
	if available_targets.is_empty(): return false
	if not is_instance_valid(_current_selected_target_node) and not available_targets.is_empty():
		_select_new_target_node(available_targets[0], available_targets)
		return true # Target was initialized

	var current_idx = available_targets.find(_current_selected_target_node)
	if current_idx == -1: # Should not happen if initialized correctly
		_select_new_target_node(available_targets[0], available_targets)
		return true

	var new_idx = current_idx
	if event.is_action_pressed("ui_left"): new_idx = (current_idx - 1 + available_targets.size()) % available_targets.size()
	elif event.is_action_pressed("ui_right"): new_idx = (current_idx + 1) % available_targets.size()
	
	if new_idx != current_idx:
		_select_new_target_node(available_targets[new_idx], available_targets)
		return true
	return false

func _select_new_target_node(new_target: Node, all_potential_targets: Array[Node]):
	_deselect_all_targets_visually(all_potential_targets) # Pass array to only deselect relevant group
	_current_selected_target_node = new_target
	if is_instance_valid(_current_selected_target_node) and _current_selected_target_node.has_method("set_target_visual"):
		_current_selected_target_node.set_target_visual(true) # Call a method on the target itself

# Called by this agent when player confirms target with "ui_accept"
func _confirm_target_selection():
	if is_instance_valid(_current_selected_target_node) and _current_command_for_targeting:
		emit_signal("target_selected", _current_selected_target_node, _current_command_for_targeting)
	_reset_targeting_state()

# Called by this agent if player presses "ui_cancel" during targeting
func _cancel_targeting_input():
	emit_signal("undo_targeting_requested") # CombatManager can listen to this
	_reset_targeting_state()

# Public method for CombatManager to call if targeting is cancelled externally
func cancel_targeting():
	_reset_targeting_state()

func _reset_targeting_state():
	is_selecting_target = false
	set_process_unhandled_input(false)
	_deselect_all_targets_visually() # Clear all target icons
	_current_selected_target_node = null
	# _current_command_for_targeting = null # Keep this if CM needs to know what was being targeted

func set_active(boolean: bool):
	is_active = boolean
	if is_active:
		on_turn_icon_node.show()
		# Player input for targeting is enabled by prepare_to_select_target
	else:
		on_turn_icon_node.hide()
		_reset_targeting_state() # Ensure targeting stops if turn ends abruptly

func _deselect_all_targets_visually(specific_group: Array[Node] = []):
	var targets_to_clear = specific_group
	if targets_to_clear.is_empty(): # If no specific group, clear all known agents
		targets_to_clear = get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("enemy")

	for node_char in targets_to_clear:
		if is_instance_valid(node_char) and node_char.has_method("set_target_visual"):
			node_char.set_target_visual(false) # Call method on target itself

# This method should be on the character node that can BE targeted
func set_target_visual(is_targeted: bool):
	if not is_instance_valid(target_icon_node): return # target_icon_node is @onready on this agent
	
	# This agent's target_icon_node is for when *IT* is targeted.
	# The _deselect_all_targets_visually needs to call this method on OTHER agents/characters.
	# This current structure is a bit mixed.
	# Let's assume `set_target_visual` is called on the character that IS the target.
	# The character node itself should have the target_icon_node.
	# For now, this will control its own icon if it's targeted.
	if is_targeted:
		target_icon_node.show()
	else:
		target_icon_node.hide()


func _ready() -> void:
	_set_group()
	# _set_on_turn_icon()
	_set_target_icon() # Initialize own target icon
	set_process_unhandled_input(false) # Input off by default

func _set_group():	
	# The parent character node should be in "player" or "enemy" group.
	# This agent script itself can be in "turnBasedAgents" if needed for direct lookup.
	# add_to_group("turnBasedAgents") # If CombatManager iterates agents directly
	pass

func _set_on_turn_icon(): # Position relative to parent character
	if not is_instance_valid(on_turn_icon_node):
		return

	on_turn_icon_node.hide()
	if get_parent() is Node2D:
		on_turn_icon_node.global_position = get_parent().global_position - (on_turn_icon_node.get_global_rect().size / 2.0) + onTurnIconOffSet

func _set_target_icon(): # This agent's own icon for when IT is targeted
	if not is_instance_valid(on_turn_icon_node):
		return

	target_icon_node.hide()
	if get_parent() is Node2D:
		target_icon_node.global_position = get_parent().global_position - (target_icon_node.get_global_rect().size / 2.0) + targetIconOffSet
	
	# Modulate based on this agent's character_type
	if character_type == Character_Type.ENEMY: target_icon_node.modulate = Color.RED
	elif character_type == Character_Type.PLAYER: target_icon_node.modulate = Color.GREEN
	# Add NEUTRAL if needed

# Add this to AbilityData.gd
# enum TargetType { SELF, ALLY, ENEMY, POINT, ALL_ALLIES, ALL_ENEMIES }
# @export var target_type: TargetType = TargetType.ENEMY
# @export var ends_turn: bool = true # If using this ability ends the turn regardless of AP
