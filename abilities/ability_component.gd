# AbilityComponent.gd
extends Node
class_name AbilityComponent

# This will hold our data resource, e.g., 'goblin_ability_set.tres'
@export var ability_set: AbilitySet

# This dictionary will store the RUNTIME state, like cooldowns
var ability_cooldowns: Dictionary = {}

# This is a clean way for other scripts to get the abilities.
func get_learned_abilities() -> Array[AbilityData]:
	# If an ability set is assigned, return its list. Otherwise, return empty.
	if ability_set:
		return ability_set.learned_abilities
	return []

# We can add logic here to manage cooldowns every frame
func _process(delta: float):
	# Example cooldown logic
	for ability in ability_cooldowns:
		ability_cooldowns[ability] -= delta
		if ability_cooldowns[ability] <= 0:
			ability_cooldowns.erase(ability)