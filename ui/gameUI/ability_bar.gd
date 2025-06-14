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

	# Connect stats change signal to update stats display
	UiManager.health_changed.connect(update_health_bar)
	UiManager.stats_changed.connect(update_ability_bar)
	UiManager.steps_changed.connect(update_sp_per_step)

func update_ability_bar():
	# print("AbilityBar: Updating ability bar for selected character.")
	populate_stats_for_character()
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
			# print("AbilityBar: Setting ability for button index ", i, ": ", abilities[i])
			button.set_ability(abilities[i])
		else:
			# print("AbilityBar: No ability for button index ", i)
			button.set_empty()
	
func update_health_bar():
	var initial_character = PartyManager.get_selected_character()
	# This function can be used to update health display if needed
	if not is_instance_valid(initial_character) or not initial_character.stats:
		print("AbilityBar: Invalid character node or stats not found for health update.")
		return
	
	var current_health = initial_character.stats._current_health
	var max_health = initial_character.stats.max_health
	if current_health == null:
		current_health = max_health
	%CurrentHealth.text = "%s/%s" % [current_health, max_health]

func populate_stats_for_character():
	var initial_character = PartyManager.get_selected_character()
	# This function can be used to update AP display if needed
	if not is_instance_valid(initial_character) or not initial_character.stats:
		print("AbilityBar: Invalid character node or stats not found for AP update.")
		return
	
	var current_health = initial_character.stats._current_health
	var max_health = initial_character.stats.max_health
	var current_ap = initial_character.stats.current_ap
	var max_ap = initial_character.stats.max_action_points
	var current_sp = initial_character.stats.current_sp
	var max_sp = initial_character.stats.max_step_points
	if current_sp == null:
		current_sp = max_sp
	# print("AbilityBar: Current AP for character: ", current_ap)
	# print("AbilityBar: Max AP for character: ", max_ap)
	%CurrentHealth.text = "%s/%s" % [current_health, max_health]
	%CurrentAP.text = "%s/%s" % [current_ap, max_ap]
	%CurrentSP.text = "%s/%s" % [current_sp, max_sp]

func update_sp_per_step():
	var initial_character = PartyManager.get_selected_character()
	# This function can be used to update AP display if needed
	if not is_instance_valid(initial_character) or not initial_character.stats:
		print("AbilityBar: Invalid character node or stats not found for AP update.")
		return
	var max_sp = initial_character.stats.max_step_points
	var current_sp = initial_character.stats.current_sp
	if current_sp == null:
		current_sp = max_sp

	%CurrentSP.text = "%s/%s" % [current_sp, max_sp]