extends NPC

func get_dialogue() -> Dictionary:
	var dialogue_manager = get_node_or_null("/root/DialogueManager")
	var dialogue_state = ""
	
	if dialogue_manager:
		dialogue_state = dialogue_manager.get_npc_dialogue_state(npc_id, "dialogue_state")
	
	# Default to initial state if no state is set
	if not dialogue_state:
		dialogue_state = "initial"
	
	# Return dialogue based on state
	match dialogue_state:
		"initial":
			return {
				"npc_id": npc_id,
				"text": "Greetings, traveler! What brings you to my humble abode?",
				"options": [
					{
						"id": "quest",
						"text": "I'm looking for adventure.",
						"next_dialogue": {
							"text": "Well, I might have a task for someone brave...",
							"options": [
								{"id": "accept", "text": "I'm interested. Tell me more."},
								{"id": "decline", "text": "Sorry, I'm busy right now."}
							]
						}
					},
					{
						"id": "goodbye",
						"text": "Just passing by, farewell!"
					}
				]
			}
		"quest_accepted":
			return {
				"npc_id": npc_id,
				"text": "Have you completed the adventure yet?",
				"options": [
					{"id": "complete", "text": "Yes, it's done!"},
					{"id": "progress", "text": "Still working on it..."}
				]
			}
		_:
			# Default dialogue
			return {
				"npc_id": npc_id,
				"text": "Hello again, traveler.",
				"options": [{"id": "goodbye", "text": "Farewell!"}]
			}

func _on_dialogue_ended(_npc_id: String) -> void:
	var dialogue_manager = get_node_or_null("/root/DialogueManager")
	if dialogue_manager:
		var last_option = dialogue_manager.get_last_selected_option()
		
		# Update dialogue state based on the last option selected
		if last_option == "accept":
			dialogue_manager.set_npc_dialogue_state(npc_id, "dialogue_state", "quest_accepted")
		elif last_option == "complete":
			dialogue_manager.set_npc_dialogue_state(npc_id, "dialogue_state", "quest_completed")
