extends Node2D

@export var stats: Stats

func execute_turn():
	print("Executing turn for: ", stats.name)

	var closest_player = null
	var min_distance = INF

	for player_character in PartyManager.get_current_party():
		var distance = self.global_position.distance_to(player_character.global_position)
		if distance < min_distance:
			min_distance = distance
			closest_player = player_character

		if closest_player:
			print("Closest player to %s is %s at distance %.2f" % [stats.name, closest_player.stats.name, min_distance])
			# Here you can add logic for the enemy's action against the closest player
			# For example, attacking or moving towards them
			# Example: closest_player.stats.take_damage(10)

		print("Turn executed for enemy: ", stats.name)
		CombatManager.end_current_turn()

func on_combat_started():
	print(name, " says: 'For the horde!'")

func on_combat_ended():
	queue_free()

func on_turn_start():
	if stats:
		stats.on_turn_start()

	execute_turn()

func is_dead() -> bool:
	if not stats: return true
	return not stats.is_alive()