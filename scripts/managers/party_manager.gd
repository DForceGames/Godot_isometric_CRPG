extends Node

var main_player_character: Node = null
var active_allies: Array[Node] = []
const MAX_ALLIES = 3 # Example limit

# Call this when the game starts or player character is created
func register_main_player(player_node: Node):
    main_player_character = player_node
    # Ensure player is not accidentally in allies list
    if active_allies.has(player_node):
        active_allies.erase(player_node)

func add_ally_to_party(ally_node: Node) -> bool:
    if not is_instance_valid(ally_node):
        printerr("PartyManager: Attempted to add invalid ally.")
        return false
    if active_allies.size() < MAX_ALLIES and not active_allies.has(ally_node) and ally_node != main_player_character:
        active_allies.append(ally_node)
        print("PartyManager: Added %s to party." % ally_node.name)
        return true
    elif active_allies.has(ally_node):
        print("PartyManager: %s is already in the party." % ally_node.name)
        return false
    else:
        print("PartyManager: Party is full or invalid ally.")
        return false

func remove_ally_from_party(ally_node: Node):
    if active_allies.has(ally_node):
        active_allies.erase(ally_node)
        print("PartyManager: Removed %s from party." % ally_node.name)

func get_current_combat_party_nodes() -> Array[Node]:
    var party: Array[Node] = []
    if is_instance_valid(main_player_character):
        party.append(main_player_character)
    for ally in active_allies:
        if is_instance_valid(ally):
            party.append(ally)
    return party