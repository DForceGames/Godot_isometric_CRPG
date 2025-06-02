# res://Combat/CombatManager.gd
extends Node
class_name CombatManager

# --- Signals ---
signal combat_started
signal combat_ended(result: String) # "victory", "defeat"
signal turn_started(character_node: Node)
signal turn_ended(character_node: Node)
signal action_taken(character_node: Node, ability_data: AbilityData, target_info: Dictionary)
signal player_target_selection_required(character_node: Node, ability_data: AbilityData)
signal combat_log_message(message: String)

# --- Enums ---
enum CombatState {
    IDLE,                   # Combat not active or between states
    INITIALIZING,           # Setting up combat
    AWAITING_PLAYER_INPUT,  # Player's turn, waiting for action selection (UI interaction)
    PLAYER_TARGETING,       # Player has selected an ability, now selecting target(s) on grid
    ACTION_RESOLVING,       # An action (player or enemy) is being executed and animated
    ENEMY_TURN_THINKING,    # Enemy AI is deciding its action
    CHECKING_VICTORY_DEFEAT # Checking win/loss conditions
}

# --- Exported Variables (Links to other scenes/nodes) ---
@export var ability_bar_node: NodePath  # Path to your AbilityBar node
@export var combat_grid_node: NodePath  # Path to your CombatGrid node
@export var turn_order_ui_node: NodePath # Path to your TurnOrderUI node

# --- Public Variables ---
var all_combatants: Array[Node] = []
var player_party_nodes: Array[Node] = []
var enemy_party_nodes: Array[Node] = []

var turn_order: Array[Node] = []
var current_turn_index: int = -1
var current_active_character: Node = null
var current_round: int = 0

var is_combat_active: bool = false
var current_combat_state: CombatState = CombatState.IDLE

# --- Private Variables for Action Handling ---
var _selected_ability_for_use: AbilityData = null
var _character_using_ability: Node = null

# --- Node References (set in _ready or when combat starts) ---
var _ability_bar: Node # HBoxContainer with AbilityBar.gd
var _combat_grid: Node # Node with CombatGrid.gd
var _turn_order_ui: Node # UI element for turn order

# ==============================================================================
# Initialization
# ==============================================================================
func _ready():
    # Get references to UI and Grid - ensure these paths are correct
    if not ability_bar_node.is_empty():
        _ability_bar = get_node_or_null(ability_bar_node)
        if _ability_bar and _ability_bar.has_signal("ability_selected_for_targeting"):
            _ability_bar.ability_selected_for_targeting.connect(_on_ui_ability_selected_for_targeting)
        elif _ability_bar:
            printerr("CombatManager: AbilityBar node found but does not have 'ability_selected_for_targeting' signal.")
        else:
            printerr("CombatManager: AbilityBar node not found at path: ", ability_bar_node)
            
    if not combat_grid_node.is_empty():
        _combat_grid = get_node_or_null(combat_grid_node)
        # Example: Connect to a signal from the grid when a target is clicked by the player
        # if _combat_grid and _combat_grid.has_signal("player_confirmed_target"):
        #     _combat_grid.player_confirmed_target.connect(confirm_target_and_execute_action)

    if not turn_order_ui_node.is_empty():
        _turn_order_ui = get_node_or_null(turn_order_ui_node)

    # Example: Connect to a global GameStateManager if you have one
    # GameStateManager.start_combat_requested.connect(initialize_combat_encounter)


func initialize_combat_encounter(player_nodes: Array[Node], enemy_nodes: Array[Node]):
    if is_combat_active:
        printerr("CombatManager: Cannot initialize new combat while one is already active.")
        return

    current_combat_state = CombatState.INITIALIZING
    emit_combat_log_message("Combat initiated!")

    player_party_nodes = player_nodes
    enemy_party_nodes = enemy_nodes
    all_combatants.clear()
    all_combatants.append_array(player_party_nodes)
    all_combatants.append_array(enemy_party_nodes)

    # Ensure all combatants are valid and perhaps set them into a "combat mode"
    for combatant in all_combatants:
        if not is_instance_valid(combatant):
            printerr("CombatManager: Invalid combatant found during initialization.")
            # Handle error, perhaps remove invalid combatant or abort
            return
        # combatant.enter_combat_mode() # Example method on combatant script

    _calculate_turn_order()
    if _turn_order_ui and _turn_order_ui.has_method("update_display"):
        _turn_order_ui.update_display(turn_order)

    is_combat_active = true
    current_turn_index = -1 # Will be incremented to 0 by _start_next_turn
    current_round = 0
    
    emit_signal("combat_started")
    _start_next_turn()


# ==============================================================================
# Turn Management
# ==============================================================================
func _calculate_turn_order():
    # Simple turn order: all players, then all enemies.
    # TODO: Implement a proper initiative system (e.g., based on a 'speed' stat).
    turn_order.clear()
    turn_order.append_array(player_party_nodes)
    turn_order.append_array(enemy_party_nodes)
    # Example: Shuffle or sort by initiative if you add that
    # turn_order.sort_custom(func(a, b): return get_combatant_initiative(a) > get_combatant_initiative(b))


func _start_next_turn():
    if not is_combat_active:
        return

    current_turn_index += 1
    if current_turn_index >= turn_order.size():
        current_turn_index = 0
        current_round += 1
        emit_combat_log_message("Round %s begins." % (current_round + 1))
        # TODO: Handle any "start of round" effects or cooldowns for all combatants

    current_active_character = turn_order[current_turn_index]

    if not is_instance_valid(current_active_character) or not _is_combatant_able_to_act(current_active_character):
        # Skip turn if combatant is dead or incapacitated
        emit_combat_log_message("%s's turn skipped (incapacitated)." % current_active_character.name if is_instance_valid(current_active_character) else "Invalid combatant")
        _end_current_turn_actions() # This will proceed to check win/loss and start next if needed
        return

    emit_combat_log_message("%s's turn." % current_active_character.name)

    # Replenish Action Points (AP) - assuming combatant script has this method/property
    # This should ideally be part of the combatant's own turn start logic.
    var ability_comp = current_active_character.get_node_or_null("AbilityComponent")
    if ability_comp and current_active_character.has_method("get_max_ap"):
         # This assumes player_node.movement_system.current_sp is the AP source
         # You might need a more generic AP system on each combatant.
         if current_active_character.has_node("PlayerMovement"): # Example for player
            current_active_character.get_node("PlayerMovement").current_sp = current_active_character.get_max_ap()
            current_active_character.emit_signal("_on_sp_changed", current_active_character.get_node("PlayerMovement").current_sp)
         # elif current_active_character.has_method("set_current_ap"): # For enemies
         #    current_active_character.set_current_ap(current_active_character.get_max_ap())
    
    # Handle turn-based cooldowns
    if ability_comp and ability_comp.has_method("decrement_turn_based_cooldowns"):
        ability_comp.decrement_turn_based_cooldowns() # You'll need to add this to AbilityComponent.gd

    emit_signal("turn_started", current_active_character)

    if _ability_bar and _ability_bar.has_method("set_active_character"):
        _ability_bar.set_active_character(current_active_character)
    
    if _is_player_controlled(current_active_character):
        current_combat_state = CombatState.AWAITING_PLAYER_INPUT
    else:
        current_combat_state = CombatState.ENEMY_TURN_THINKING
        _handle_enemy_turn(current_active_character)


func _end_current_turn_actions():
    emit_signal("turn_ended", current_active_character)
    current_combat_state = CombatState.CHECKING_VICTORY_DEFEAT
    
    # Clear any per-turn selections
    _selected_ability_for_use = null
    _character_using_ability = null
    if _combat_grid and _combat_grid.has_method("clear_targeting_overlays"):
        _combat_grid.clear_targeting_overlays()

    if _check_win_loss_conditions(): # This will call end_combat if true
        return 

    if is_combat_active: # If combat didn't end from win/loss
        _start_next_turn()
    else: # Combat ended for other reasons, ensure state is idle
        current_combat_state = CombatState.IDLE


# ==============================================================================
# Player Action Handling (Triggered by UI/Input)
# ==============================================================================
func _on_ui_ability_selected_for_targeting(character: Node, ability_data: AbilityData):
    if not is_combat_active or current_combat_state != CombatState.AWAITING_PLAYER_INPUT:
        return
    if character != current_active_character:
        printerr("CombatManager: Ability selected for non-active character.")
        return

    var ability_comp = character.get_node_or_null("AbilityComponent")
    if not ability_comp or not ability_comp.can_use_ability(ability_data, character):
        emit_combat_log_message("Cannot use %s." % ability_data.ability_name) # Feedback already in can_use_ability
        return

    _character_using_ability = character
    _selected_ability_for_use = ability_data
    current_combat_state = CombatState.PLAYER_TARGETING
    
    emit_signal("player_target_selection_required", character, ability_data)
    emit_combat_log_message("Select target for %s." % ability_data.ability_name)

    # Tell the CombatGrid to show valid targets
    if _combat_grid and _combat_grid.has_method("show_valid_targets_for_ability"):
        _combat_grid.show_valid_targets_for_ability(character, ability_data)
    else:
        printerr("CombatManager: CombatGrid not found or missing 'show_valid_targets_for_ability' method.")


# This function would be called by your input handler for the grid
# after the player clicks on a valid target cell or character.
func confirm_target_and_execute_action(target_info: Dictionary):
    if not is_combat_active or current_combat_state != CombatState.PLAYER_TARGETING:
        printerr("CombatManager: Not in targeting state or combat inactive.")
        return
    if not _selected_ability_for_use or not _character_using_ability:
        printerr("CombatManager: No ability or character was prepared.")
        return

    current_combat_state = CombatState.ACTION_RESOLVING
    emit_combat_log_message("Executing %s..." % _selected_ability_for_use.ability_name)

    var ability_comp = _character_using_ability.get_node_or_null("AbilityComponent")
    if ability_comp:
        ability_comp.use_ability(_selected_ability_for_use.id, _character_using_ability, target_info)
        emit_signal("action_taken", _character_using_ability, _selected_ability_for_use, target_info)
        
        # TODO: Wait for animations/effects from use_ability to complete if it's async.
        # For now, we assume it's synchronous for turn progression.
        # If use_ability becomes async (e.g., using await for animations),
        # then _end_current_turn_actions() should be called by a signal when the action truly finishes.
        
        # Check if the character still has AP or if the action ends the turn
        # For simplicity, let's assume any ability use might end the turn or lead to end.
        # A more complex system would check AP costs vs remaining AP.
        var current_ap = _get_combatant_current_ap(_character_using_ability)
        if current_ap <= 0: # Or if the ability itself is turn-ending
            _end_current_turn_actions()
        else:
            # Player can take more actions
            current_combat_state = CombatState.AWAITING_PLAYER_INPUT
            if _ability_bar and _ability_bar.has_method("update_ability_visuals"): # Refresh UI after AP cost
                 _ability_bar.update_ability_visuals()
            # Clear selection for next action
            _selected_ability_for_use = null
            _character_using_ability = null
            if _combat_grid and _combat_grid.has_method("clear_targeting_overlays"):
                _combat_grid.clear_targeting_overlays()


    else:
        printerr("CombatManager: Active character has no AbilityComponent.")
        current_combat_state = CombatState.AWAITING_PLAYER_INPUT # Revert state


# Call this if player decides to explicitly end their turn via a UI button
func player_ends_turn():
    if not is_combat_active or current_combat_state != CombatState.AWAITING_PLAYER_INPUT:
        return
    if not _is_player_controlled(current_active_character):
        return
    
    emit_combat_log_message("%s ends their turn." % current_active_character.name)
    _end_current_turn_actions()


# ==============================================================================
# Enemy AI Handling (Placeholder)
# ==============================================================================
func _handle_enemy_turn(enemy_node: Node):
    emit_combat_log_message("%s is thinking..." % enemy_node.name)
    # TODO: Implement Enemy AI logic
    # 1. Analyze battlefield (player positions, health, etc.)
    # 2. Choose an ability from its AbilityComponent.known_abilities
    # 3. Choose target(s) for that ability.
    # 4. Call its own AbilityComponent.use_ability(...)

    # Placeholder: Enemy does nothing and ends turn after a short delay
    await get_tree().create_timer(1.0).timeout # Simulate thinking
    if not is_combat_active: return # Combat might have ended during the timer

    emit_combat_log_message("%s ends their turn (placeholder AI)." % enemy_node.name)
    _end_current_turn_actions()


# ==============================================================================
# Combat Resolution
# ==============================================================================
func _check_win_loss_conditions() -> bool:
    var all_players_defeated = true
    for player_node in player_party_nodes:
        if _is_combatant_able_to_act(player_node):
            all_players_defeated = false
            break
    
    if all_players_defeated:
        end_combat("defeat")
        return true

    var all_enemies_defeated = true
    for enemy_node in enemy_party_nodes:
        if _is_combatant_able_to_act(enemy_node):
            all_enemies_defeated = false
            break
            
    if all_enemies_defeated:
        end_combat("victory")
        return true
        
    return false


func end_combat(result: String):
    if not is_combat_active:
        return

    is_combat_active = false
    current_combat_state = CombatState.IDLE
    
    if result == "victory":
        emit_combat_log_message("Victory!")
        # TODO: Grant rewards (XP, items, etc.)
    elif result == "defeat":
        emit_combat_log_message("Defeat...")
        # TODO: Handle game over or retreat logic
        
    emit_signal("combat_ended", result)
    
    # Cleanup combatants (e.g., take them out of "combat mode")
    for combatant in all_combatants:
        if is_instance_valid(combatant) and combatant.has_method("exit_combat_mode"):
            combatant.exit_combat_mode()

    # TODO: Transition back to exploration map or previous game state
    # GameStateManager.transition_to_exploration()


# ==============================================================================
# Helper Functions
# ==============================================================================
func _is_player_controlled(character_node: Node) -> bool:
    # Basic check, assumes player characters are in player_party_nodes
    return player_party_nodes.has(character_node)
    # Or, character_node.is_in_group("player_character")


func _is_combatant_able_to_act(character_node: Node) -> bool:
    if not is_instance_valid(character_node): return false
    # Basic check: assumes character has a 'current_health' property or a HealthComponent
    # This needs to be adapted to your character's health system.
    var health_component = character_node.get_node_or_null("HealthComponent")
    if health_component and health_component.has_method("is_alive"):
        return health_component.is_alive()
    elif character_node.has_meta("current_health"): # Fallback if health is a direct property
         return character_node.get_meta("current_health", 0) > 0
    
    printerr("CombatManager: Cannot determine if %s is able to act (no health info)." % character_node.name)
    return false # Default to not able if health cannot be determined


func _get_combatant_current_ap(character_node: Node) -> int:
    if not is_instance_valid(character_node): return 0
    # This needs to align with how AP is stored on your characters
    if character_node.has_node("PlayerMovement") and character_node.get_node("PlayerMovement").has_meta("current_sp"): # Example for player
        return character_node.get_node("PlayerMovement").get_meta("current_sp", 0)
    # elif character_node.has_method("get_current_ap"): # For enemies or a generic method
    #    return character_node.get_current_ap()
    elif character_node.has_meta("current_ap"):
        return character_node.get_meta("current_ap", 0)

    printerr("CombatManager: Cannot get current AP for %s." % character_node.name)
    return 0

# Placeholder for global log for now
func emit_combat_log_message(message: String):
    print("COMBAT LOG: ", message)
    emit_signal("combat_log_message", message)