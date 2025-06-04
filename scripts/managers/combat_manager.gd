extends Node
class_name CombatManager

# --- Signals ---
signal combat_started
signal combat_ended(result: String) # "victory", "defeat"
signal turn_started(character_node: Node) # Emitted with the character whose turn is starting
signal turn_ended(character_node: Node)   # Emitted with the character whose turn just ended
signal action_taken(character_node: Node, ability_data: AbilityData, target_info: Dictionary)
signal player_target_selection_required(character_node: Node, ability_data: AbilityData) # For UI/Grid to show targeting
signal combat_log_message(message: String)
signal turn_order_updated(new_turn_order: Array[Node]) # For TurnOrderUI to refresh

# --- Enums ---
enum CombatState {
    IDLE,
    INITIALIZING,
    AWAITING_PLAYER_INPUT, # Player's turn, CombatManager waits for UI (e.g. AbilityBar) or Agent action
    PLAYER_TARGETING,      # Player has selected an ability, agent is handling target selection on grid
    ACTION_RESOLVING,
    ENEMY_TURN_THINKING,
    CHECKING_VICTORY_DEFEAT
}

# --- Exported Variables (Links to other scenes/nodes) ---
@export var ability_bar_node_path: NodePath  # Renamed for clarity
@export var combat_grid_node_path: NodePath  # Renamed for clarity
# turn_order_ui_node_path is not strictly needed here if UI connects to this manager's signals

# --- Public Variables ---
var all_combatants: Array[Node] = []
var player_party_nodes: Array[Node] = []
var enemy_party_nodes: Array[Node] = []

var turn_order: Array[Node] = []
var current_turn_index: int = -1
var current_active_character: Node = null # This node is expected to HAVE a TurnBasedAgent script or be one
var current_round: int = 0

var is_combat_active: bool = false
var current_combat_state: CombatState = CombatState.IDLE

# --- Private Variables for Action Handling ---
var _selected_ability_for_use: AbilityData = null # Set when UI ability is picked by player
var _character_using_ability: Node = null       # Set when UI ability is picked by player

# --- Node References (set in _ready or when combat starts) ---
var _ability_bar: Node
var _combat_grid: Node
# var _turn_order_ui: Node # UI will get its data via signals

# ==============================================================================
# Initialization
# ==============================================================================
func _ready():
    add_to_group("CombatManager") # So other nodes (like TurnOrderUI) can find it

    if not ability_bar_node_path.is_empty():
        _ability_bar = get_node_or_null(ability_bar_node_path)
        if _ability_bar and _ability_bar.has_signal("ability_selected_for_targeting"):
            _ability_bar.ability_selected_for_targeting.connect(_on_ui_ability_selected_for_targeting)
        elif _ability_bar:
            printerr("CombatManager: AbilityBar node found but does not have 'ability_selected_for_targeting' signal.")
        else:
            printerr("CombatManager: AbilityBar node not found at path: ", ability_bar_node_path)
            
    if not combat_grid_node_path.is_empty():
        _combat_grid = get_node_or_null(combat_grid_node_path)


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

    for combatant in all_combatants:
        if not is_instance_valid(combatant):
            printerr("CombatManager: Invalid combatant found during initialization.")
            return
        # combatant.enter_combat_mode() # Example

    _calculate_turn_order() # This will also emit turn_order_updated

    is_combat_active = true
    current_turn_index = -1
    current_round = 0
    
    emit_signal("combat_started")
    _start_next_turn()

# ==============================================================================
# Turn Management
# ==============================================================================
func _calculate_turn_order():
    turn_order.clear()
    # Simple turn order: all players, then all enemies.
    # TODO: Implement a proper initiative system (e.g., based on a 'speed' stat from Stats component).
    turn_order.append_array(player_party_nodes)
    turn_order.append_array(enemy_party_nodes)
    
    # Example initiative sort (requires 'initiative' or 'speed' in Stats.gd)
    # turn_order.sort_custom(func(a, b):
    #     var stats_a = a.get_node_or_null("Stats")
    #     var stats_b = b.get_node_or_null("Stats")
    #     if stats_a and stats_b and stats_a.has_method("get_initiative") and stats_b.has_method("get_initiative"):
    #         return stats_a.get_initiative() > stats_b.get_initiative()
    #     return false # Default sort or error
    # )
    emit_signal("turn_order_updated", turn_order)


func _start_next_turn():
    if not is_combat_active:
        return

    # Deactivate previous character's agent if it was active
    if is_instance_valid(current_active_character):
        var prev_agent_node = _get_agent_from_character(current_active_character)
        if prev_agent_node:
            prev_agent_node.set_active(false)
            if prev_agent_node.is_connected("target_selected", _on_player_agent_target_confirmed):
                prev_agent_node.target_selected.disconnect(_on_player_agent_target_confirmed)

    current_turn_index += 1
    if current_turn_index >= turn_order.size():
        current_turn_index = 0
        current_round += 1
        emit_combat_log_message("Round %s begins." % (current_round + 1))

    current_active_character = turn_order[current_turn_index]

    if not is_instance_valid(current_active_character) or not _is_combatant_able_to_act(current_active_character):
        emit_combat_log_message("%s's turn skipped (incapacitated)." % current_active_character.name if is_instance_valid(current_active_character) else "Invalid combatant")
        _end_current_turn_actions()
        return

    emit_combat_log_message("%s's turn." % current_active_character.name)

    # Replenish Resources at the start of the turn using Stats component
    var stats_comp = current_active_character.get_node_or_null("Stats")
    if stats_comp:
        if stats_comp.has_method("replenish_action_points"):
            stats_comp.replenish_action_points() # Reset AP to max at start of turn
        else:
            stats_comp.current_ap = stats_comp.max_action_points 

        if stats_comp.has_method("replenish_step_points"):
            stats_comp.replenish_step_points() # Reset SP to max at start of turn
        else:
            stats_comp.current_sp = stats_comp.max_step_points

    # Handle turn-based cooldowns
    var ability_comp = current_active_character.get_node_or_null("AbilityComponent")
    if ability_comp and ability_comp.has_method("decrement_turn_based_cooldowns"):
        ability_comp.decrement_turn_based_cooldowns()

    emit_signal("turn_started", current_active_character)

    # Activate the agent component of the character
    var agent_node = _get_agent_from_character(current_active_character)
    if agent_node:
        agent_node.set_active(true)

    if _ability_bar and _ability_bar.has_method("set_active_character"):
        _ability_bar.set_active_character(current_active_character)
    
    if _is_player_controlled(current_active_character):
        current_combat_state = CombatState.AWAITING_PLAYER_INPUT
        # CombatManager now waits for UI (e.g. AbilityBar) to trigger _on_ui_ability_selected_for_targeting
    else:
        current_combat_state = CombatState.ENEMY_TURN_THINKING
        _handle_enemy_turn(current_active_character)


func _end_current_turn_actions():
    # Deactivate current character's agent (also done at start of next turn, but good for clarity)
    if is_instance_valid(current_active_character):
        var agent_node = _get_agent_from_character(current_active_character)
        if agent_node:
            agent_node.set_active(false)
            if agent_node.is_connected("target_selected", _on_player_agent_target_confirmed):
                agent_node.target_selected.disconnect(_on_player_agent_target_confirmed)
    
    emit_signal("turn_ended", current_active_character)
    current_combat_state = CombatState.CHECKING_VICTORY_DEFEAT
    
    _selected_ability_for_use = null
    _character_using_ability = null
    if _combat_grid and _combat_grid.has_method("clear_targeting_overlays"):
        _combat_grid.clear_targeting_overlays()

    if _check_win_loss_conditions():
        return 

    if is_combat_active:
        _start_next_turn()
    else:
        current_combat_state = CombatState.IDLE

# ==============================================================================
# Player Action Handling
# ==============================================================================
func _on_ui_ability_selected_for_targeting(character: Node, ability_data: AbilityData):
    if not is_combat_active or current_combat_state != CombatState.AWAITING_PLAYER_INPUT:
        return
    if character != current_active_character:
        printerr("CombatManager: Ability selected for non-active character.")
        return

    var ability_comp = character.get_node_or_null("AbilityComponent")
    var stats_comp = character.get_node_or_null("Stats") # Get stats for can_use_ability

    if not ability_comp or not stats_comp or not ability_comp.can_use_ability(ability_data, stats_comp): # Pass stats
        emit_combat_log_message("Cannot use %s." % ability_data.ability_name)
        return

    _character_using_ability = character
    _selected_ability_for_use = ability_data
    current_combat_state = CombatState.PLAYER_TARGETING
    
    var agent_node = _get_agent_from_character(character)
    if agent_node:
        if not agent_node.target_selected.is_connected(_on_player_agent_target_confirmed):
            agent_node.target_selected.connect(_on_player_agent_target_confirmed)
        if agent_node.has_method("prepare_to_select_target"):
            agent_node.prepare_to_select_target(ability_data) # Tell agent to start targeting mode
            
    emit_signal("player_target_selection_required", character, ability_data) # For CombatGrid
    emit_combat_log_message("Select target for %s." % ability_data.ability_name)

    if _combat_grid and _combat_grid.has_method("show_valid_targets_for_ability"):
        _combat_grid.show_valid_targets_for_ability(character, ability_data)

# Called when the TurnBasedAgent confirms a target after player input
func _on_player_agent_target_confirmed(target_node: Node, command_data: AbilityData):
    if not is_combat_active or current_combat_state != CombatState.PLAYER_TARGETING:
        printerr("CombatManager: Not in targeting state or combat inactive for agent confirmation.")
        return
    if _character_using_ability != current_active_character:
        printerr("CombatManager: Target confirmed for non-active character.")
        return
    if command_data != _selected_ability_for_use:
        printerr("CombatManager: Agent confirmed target for a different ability than selected by UI.")
        # Optionally reset or show error to player
        current_combat_state = CombatState.AWAITING_PLAYER_INPUT # Revert state
        var agent_node = _get_agent_from_character(_character_using_ability)
        if agent_node and agent_node.has_method("cancel_targeting"): agent_node.cancel_targeting()
        return

    var target_info: Dictionary = {"primary_target": target_node} 
    # More complex target_info can be built here if ability has AoE based on primary_target, etc.
    
    confirm_target_and_execute_action(target_info)

# This function executes the action once ability and target are fully confirmed
func confirm_target_and_execute_action(target_info: Dictionary):
    if not is_combat_active or current_combat_state != CombatState.PLAYER_TARGETING: # Should be targeting or resolving
         # If called directly after agent confirmation, state is still PLAYER_TARGETING
        pass # Allow this if called from _on_player_agent_target_confirmed

    if not _selected_ability_for_use or not _character_using_ability:
        printerr("CombatManager: No ability or character was prepared for execution.")
        current_combat_state = CombatState.AWAITING_PLAYER_INPUT # Revert
        return

    current_combat_state = CombatState.ACTION_RESOLVING
    emit_combat_log_message("Executing %s..." % _selected_ability_for_use.ability_name)

    var ability_comp = _character_using_ability.get_node_or_null("AbilityComponent")
    if ability_comp:
        # Pass character node itself, not just stats, to use_ability if it needs more from character
        ability_comp.use_ability(_selected_ability_for_use.id, _character_using_ability, target_info)
        emit_signal("action_taken", _character_using_ability, _selected_ability_for_use, target_info)
        
        var current_ap = _get_combatant_current_ap(_character_using_ability)
        if current_ap <= 0 or _selected_ability_for_use.ends_turn: # Assuming AbilityData has 'ends_turn'
            _end_current_turn_actions()
        else:
            current_combat_state = CombatState.AWAITING_PLAYER_INPUT
            if _ability_bar and _ability_bar.has_method("update_ability_visuals"):
                 _ability_bar.update_ability_visuals(_character_using_ability) # Pass char to update for
            _selected_ability_for_use = null # Ready for next ability selection
            # _character_using_ability remains current_active_character
            if _combat_grid and _combat_grid.has_method("clear_targeting_overlays"):
                _combat_grid.clear_targeting_overlays()
    else:
        printerr("CombatManager: Active character has no AbilityComponent.")
        current_combat_state = CombatState.AWAITING_PLAYER_INPUT

    # Disconnect agent's signal after action is resolved or if turn ends
    var agent_node = _get_agent_from_character(_character_using_ability)
    if agent_node and agent_node.is_connected("target_selected", _on_player_agent_target_confirmed):
        agent_node.target_selected.disconnect(_on_player_agent_target_confirmed)


func player_ends_turn():
    if not is_combat_active or current_combat_state != CombatState.AWAITING_PLAYER_INPUT:
        return
    if not _is_player_controlled(current_active_character):
        return
    
    emit_combat_log_message("%s ends their turn." % current_active_character.name)
    _end_current_turn_actions()

# ==============================================================================
# Enemy AI Handling
# ==============================================================================
func _handle_enemy_turn(enemy_node: Node):
    emit_combat_log_message("%s is thinking..." % enemy_node.name)
    
    # TODO: Implement Enemy AI logic
    # 1. Get AbilityComponent and StatsComponent from enemy_node.
    # 2. Query AbilityComponent for usable abilities (check AP, cooldowns).
    # 3. Analyze battlefield (player positions, healths - needs access to player_party_nodes).
    # 4. Choose an ability and target(s).
    # 5. Call enemy_node.get_node("AbilityComponent").use_ability(chosen_ability.id, enemy_node, chosen_target_info)
    
    # Placeholder: Enemy does nothing and ends turn after a short delay
    await get_tree().create_timer(1.0).timeout 
    if not is_combat_active: return # Combat might have ended

    # Example: Placeholder action
    # var ability_comp = enemy_node.get_node_or_null("AbilityComponent")
    # if ability_comp and not ability_comp.known_abilities.is_empty():
    #    var first_ability = ability_comp.known_abilities[0]
    #    var stats_comp = enemy_node.get_node_or_null("Stats")
    #    if ability_comp.can_use_ability(first_ability, stats_comp):
    #        var target_player = player_party_nodes.pick_random() # Simplistic target
    #        if is_instance_valid(target_player):
    #            emit_combat_log_message("%s uses %s on %s (placeholder AI)." % [enemy_node.name, first_ability.ability_name, target_player.name])
    #            ability_comp.use_ability(first_ability.id, enemy_node, {"primary_target": target_player})
    #            emit_signal("action_taken", enemy_node, first_ability, {"primary_target": target_player})
    #        else:
    #            emit_combat_log_message("%s has no valid player target (placeholder AI)." % enemy_node.name)
    #    else:
    #         emit_combat_log_message("%s cannot use its first ability (placeholder AI)." % enemy_node.name)
    # else:
    #    emit_combat_log_message("%s has no abilities (placeholder AI)." % enemy_node.name)

    emit_combat_log_message("%s ends their turn (placeholder AI)." % enemy_node.name)
    _end_current_turn_actions()

# ==============================================================================
# Combat Resolution & Helpers
# ==============================================================================
func _check_win_loss_conditions() -> bool:
    var all_players_incapacitated = true
    for player_node in player_party_nodes:
        if _is_combatant_able_to_act(player_node):
            all_players_incapacitated = false
            break
    if all_players_incapacitated and not player_party_nodes.is_empty(): # Ensure there were players to begin with
        end_combat("defeat")
        return true

    var all_enemies_incapacitated = true
    for enemy_node in enemy_party_nodes:
        if _is_combatant_able_to_act(enemy_node):
            all_enemies_incapacitated = false
            break
    if all_enemies_incapacitated and not enemy_party_nodes.is_empty(): # Ensure there were enemies
        end_combat("victory")
        return true
        
    return false

func end_combat(result: String):
    if not is_combat_active: return
    is_combat_active = false
    current_combat_state = CombatState.IDLE
    
    if result == "victory": emit_combat_log_message("Victory!")
    elif result == "defeat": emit_combat_log_message("Defeat...")
        
    emit_signal("combat_ended", result)
    
    for combatant in all_combatants:
        if is_instance_valid(combatant) and combatant.has_method("exit_combat_mode"):
            combatant.exit_combat_mode()
        # Deactivate any remaining active agents
        var agent_node = _get_agent_from_character(combatant)
        if agent_node and agent_node.is_active: # Check agent's own is_active state
            agent_node.set_active(false)

func _is_player_controlled(character_node: Node) -> bool:
    return player_party_nodes.has(character_node)

func _is_combatant_able_to_act(character_node: Node) -> bool:
    if not is_instance_valid(character_node): return false
    var stats_comp = character_node.get_node_or_null("Stats")
    if stats_comp: # Assuming Stats has current_health
        return stats_comp.current_health > 0
    
    printerr("CombatManager: Cannot determine if %s is able to act (no Stats component or health info)." % character_node.name)
    return false

func _get_combatant_current_ap(character_node: Node) -> int:
    if not is_instance_valid(character_node): return 0
    var stats_comp = character_node.get_node_or_null("Stats")
    if stats_comp:
        return stats_comp.current_ap
    
    printerr("CombatManager: Cannot get current AP for %s (no Stats component)." % character_node.name)
    return 0

func emit_combat_log_message(message: String):
    print("COMBAT LOG: ", message)
    emit_signal("combat_log_message", message)

func _get_agent_from_character(character_node: Node) -> TurnBasedAgent:
    if not is_instance_valid(character_node): return null
    if character_node is TurnBasedAgent:
        return character_node as TurnBasedAgent
    # Common pattern: Agent script is on a child node. Adjust name if different.
    return character_node.get_node_or_null("TurnBasedAgent") as TurnBasedAgent