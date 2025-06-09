extends Node

# Signals
signal party_updated
signal selected_character_changed(new_character_node)

const MAX_PARTY_SIZE = 4

var main_character: Node
var active_allies: Dictionary = {}
var selected_character: Node = null

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
	print("PartyManager: active_allies: ", active_allies)

	party_updated.emit()
	print("PartyManager: Main character %s registered in slot 1." % main_character.name)
	set_selected_character(main_character)

func set_selected_character(character_node: Node):
	if selected_character == character_node:
		print("PartyManager: Selected character is already %s." % character_node.name)
		return
	
	if not is_instance_valid(character_node) or not is_character_in_party(character_node):
		print("PartyManager: Cannot set selected character to %s, not in party." % character_node.name)
		return
		
	print("PartyManager: Selected character changed to ", character_node.name)
	self.selected_character = character_node

	selected_character_changed.emit(self.selected_character)

func is_character_in_party(character_node: Node) -> bool:
	for slot_data in active_allies.values():
		if slot_data["node"] == character_node:
			if slot_data["node"] and slot_data["node"] == character_node:
				return true
		
	return false

func get_selected_character() -> Node:
	return selected_character

# Call this when the game starts or player character is created
func add_member_to_party(character_node: Node):
	if active_allies.size() >= MAX_PARTY_SIZE:
		print("PartyManager: Cannot add %s to party, party is full." % character_node.name)
		return

	if is_character_in_party(character_node):
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

func make_party_persistent_for_transition():
	print("PartyManager: Moving active party to root 'life raft' to survive scene change.")
	var current_party = get_current_party()

	for member in current_party:
		if member.get_parent():
			member.get_parent().remove_child(member)

		get_tree().root.call_deferred("add_child", member)
