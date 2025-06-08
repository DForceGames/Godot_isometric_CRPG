extends Node

# Signals
signal party_updated

const MAX_PARTY_SIZE = 4

var main_character: Node
var active_allies: Dictionary = {}

func register_main_character(character_node: Node):
	if main_character != null:
		printerr("PartyManager: Main character already registered.")
		return

	main_character = character_node
	var slot_data = {
		"name": main_character.name,
		"node": main_character,
		"role": "Leader"  # Assuming stats is a property of the character
	}

	active_allies[1] = slot_data

	party_updated.emit()
	print("PartyManager: Main character %s registered in slot 1." % main_character.name)

# Call this when the game starts or player character is created
func add_member_to_party(character_node: Node):
	if active_allies.size() >= MAX_PARTY_SIZE:
		print("PartyManager: Cannot add %s to party, party is full." % character_node.name)
		return

	for slot_data in active_allies.values():
		if slot_data["node"] == character_node:
			print("PartyManager: %s is already in the party." % character_node.name)
			return

	var assigned_slot = -1
	for i in range(2, MAX_PARTY_SIZE + 1):
		if not active_allies.has(i):
			assigned_slot = i
			break
	
	if assigned_slot != -1:
		var new_slot_data = {
			"name": character_node.name,
			"node": character_node,
			"role": "Ally"  # Assuming stats is a property of the character
		}
		active_allies[assigned_slot] = new_slot_data
		party_updated.emit()
		print("PartyManager: Added %s to party in slot %d." % [character_node.name, assigned_slot])

func remove_member_from_party(character_node: Node):
	if character_node == main_character:
		print("PartyManager: Cannot remove main character from party.")
		return
	
	var slot_to_remove = -1
	for slot_number in active_allies.keys():
		if active_allies[slot_number]["node"] == character_node:
			slot_to_remove = slot_number
			break 

	if slot_to_remove != -1:
		active_allies.erase(slot_to_remove)
		party_updated.emit()
		print("PartyManager: Removed %s from party." % character_node.name)

func get_current_party() -> Array[Node]:
	var members_in_order: Array[Node] = []
	for i in range(1, MAX_PARTY_SIZE + 1):
		if active_allies.has(i):
			var slot_data = active_allies[i]
			if is_instance_valid(slot_data["node"]):
				members_in_order.append(slot_data["node"])
	
	return members_in_order
