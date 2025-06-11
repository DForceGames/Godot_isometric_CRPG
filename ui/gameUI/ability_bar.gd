extends VBoxContainer

var all_ability_buttons: Array[AbilityButton] = []

func _ready():
	for hbox in get_children():
		if hbox is HBoxContainer:
			for button in hbox.get_children():
				if button is AbilityButton:
					all_ability_buttons.append(button)
					print("AbilityBar: Found ability button: ", button)

	PartyManager.selected_character_changed.connect(populate_for_character)
	
	var initial_character = PartyManager.get_selected_character()
	# print("AbilityBar: Initial character: ", initial_character)
	if initial_character:
		print("AbilityBar: Initial character found: ", initial_character)
		populate_for_character(initial_character)

	# Connect stats change signal to update AP display
	UiManager.stats_changed.connect(update_ability_bar)

func update_ability_bar():
	print("AbilityBar: Updating ability bar for selected character.")
	populate_ap_for_character()
	populate_for_character(PartyManager.get_selected_character())

func populate_for_character(character_node: Node):
	# print("AbilityBar: Populating for character: ", character_node)
	if not is_instance_valid(character_node) or not character_node.stats:
		print("AbilityBar: Invalid character node or stats not found.")
		for button in all_ability_buttons:
			print("AbilityBar: Invalid character node or stats not found.")
			button.set_empty()
		return

	var ability_comp = character_node.find_child("AbilityComponent") as AbilityComponent
	# print("AbilityBar: Found AbilityComponent: ", ability_comp)
	if not ability_comp:
		for button in all_ability_buttons:
			print("AbilityBar: AbilityComponent not found.")
			button.set_empty()
		return
	
	var abilities = ability_comp.get_learned_abilities()
	# print("AbilityBar: Learned abilities: ", abilities)
	for i in range(all_ability_buttons.size()):
		var button = all_ability_buttons[i]
		if i < abilities.size():
			print("AbilityBar: Setting ability for button index ", i, ": ", abilities[i])
			button.set_ability(abilities[i])
		else:
			print("AbilityBar: No ability for button index ", i)
			button.set_empty()
	
func populate_ap_for_character():
	var initial_character = PartyManager.get_selected_character()
	# This function can be used to update AP display if needed
	if not is_instance_valid(initial_character) or not initial_character.stats:
		print("AbilityBar: Invalid character node or stats not found for AP update.")
		return
	
	var current_ap = initial_character.stats.current_ap
	var max_ap = initial_character.stats.max_action_points
	print("AbilityBar: Current AP for character: ", current_ap)
	print("AbilityBar: Max AP for character: ", max_ap)
	%CurrentAP.text = "%s/%s" % [current_ap, max_ap]
