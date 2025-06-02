# res://UI/Combat/AbilityBar.gd
extends HBoxContainer # Or your preferred container type

# Preload your AbilityButton scene
@export var ability_button_scene: PackedScene

# These will be set by your CombatManager or TurnManager when a character's turn starts
var current_character_node: CharacterBody2D 
var current_ability_component: AbilityComponent

# This signal is emitted when an ability button is pressed.
# The CombatManager (or similar) should connect to this.
signal ability_selected_for_targeting(character_node: CharacterBody2D, ability_data: AbilityData)

func set_active_character(character: CharacterBody2D):
    current_character_node = character
    if is_instance_valid(current_character_node):
        current_ability_component = current_character_node.get_node_or_null("AbilityComponent")
    else:
        current_ability_component = null
    
    populate_ability_buttons()
    update_ability_visuals()

func populate_ability_buttons():
    # Clear existing buttons
    for child in get_children():
        child.queue_free()

    if not is_instance_valid(current_ability_component):
        return

    for ability_data_res in current_ability_component.known_abilities:
        if ability_button_scene:
            var button_instance = ability_button_scene.instantiate() as TextureButton # Cast to your AbilityButton root type
            add_child(button_instance)
            # Assuming your AbilityButton.gd has a set_ability_data method
            if button_instance.has_method("set_ability_data"):
                button_instance.set_ability_data(ability_data_res)
            
            # Connect the button's signal to a handler in this AbilityBar script
            if button_instance.has_signal("ability_action_initiated"):
                button_instance.ability_action_initiated.connect(_on_ability_button_pressed)

func _on_ability_button_pressed(ability_data: AbilityData):
    if is_instance_valid(current_character_node):
        # The AbilityBar signals that an ability was chosen.
        # The CombatManager will handle targeting and eventual execution.
        emit_signal("ability_selected_for_targeting", current_character_node, ability_data)
        print("AbilityBar: %s selected for targeting." % ability_data.ability_name)

func update_ability_visuals():
    if not is_instance_valid(current_ability_component) or not is_instance_valid(current_character_node):
        for i in range(get_child_count()):
            var button = get_child(i)
            if button and button.has_method("update_visuals"):
                 button.update_visuals(0.0, false) # Effectively disable all
        return

    var buttons = get_children()
    for i in range(buttons.size()):
        var button = buttons[i]
        # Ensure button is valid and has the current_ability_data property set by set_ability_data
        if button and button.has_method("update_visuals") and button.has_method("set_ability_data"):
            # We need to get the AbilityData associated with this button again,
            # as it's not directly stored after populate_ability_buttons unless we add it.
            # A more robust way would be to store a mapping or retrieve it carefully.
            # For simplicity, let's assume order matches known_abilities if not dynamically changing.
            if i < current_ability_component.known_abilities.size():
                var ability_data = current_ability_component.known_abilities[i]
                if ability_data and button.current_ability_data == ability_data: # Check if it's the correct button
                    var cooldown = current_ability_component.ability_cooldowns.get(ability_data.id, 0.0)
                    # Pass the character node itself as 'player_stats'
                    var can_use = current_ability_component.can_use_ability(ability_data, current_character_node)
                    button.update_visuals(cooldown, can_use)

func _process(_delta):
    # Continuously update visuals (especially for cooldowns if they are real-time within a turn, or for AP changes)
    # For a strictly turn-based game, you might only call update_ability_visuals() when game state changes (e.g., AP spent).
    # If cooldowns are turn-based, _process in AbilityComponent handles time-based delta, but UI update for turn start is key.
    if get_child_count() > 0 and is_instance_valid(current_ability_component): # Only update if populated
        update_ability_visuals() # Call this to refresh button states based on current AP/cooldowns