extends Button

class_name AbilityButton

var assigned_ability: AbilityData = null
var usable: bool = true

func _ready():
	pressed.connect(_on_button_pressed)

func set_ability(ability: AbilityData):
	assigned_ability = ability

	icon = assigned_ability.icon if assigned_ability else null
	tooltip_text = String(assigned_ability.ability_name) if assigned_ability else "No ability assigned"

	if assigned_ability:
		check_if_usable()
	else:
		set_empty()

	disabled = false
	if usable:
		set_usable()
	else:
		set_unusable()

	%AbilityCost.text = str(assigned_ability.ap_cost)

func check_if_usable():
	if assigned_ability and assigned_ability.ap_cost > PartyManager.get_selected_character().stats.current_ap:
		set_unusable()
	else:
		set_usable()

func set_usable():
	if not usable:
		usable = true
		modulate = Color.WHITE

func set_unusable():
	if usable:
		usable = false
		modulate = Color(1, 1, 1, 0.5)

func set_empty():
	self.assigned_ability = null
	icon = null
	tooltip_text = "No ability assigned"
	disabled = true
	modulate = Color(1, 1, 1, 0.5) 

func _on_button_pressed():
	if assigned_ability and usable:
		var player = get_tree().get_first_node_in_group("Player")
		if player:
			var movement_system = player.get_node("PlayerMovement")
			movement_system.enter_targeting_mode(assigned_ability)
