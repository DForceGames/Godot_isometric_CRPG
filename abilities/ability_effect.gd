extends Resource
class_name AbilityEffect

func execute(user, target_tile: Vector2, affected_tiles: Array[Vector2], _damage) -> void:
	print("Executing base effect for user: ", user, " on tile: ", target_tile)
	print("Affected tiles: ", affected_tiles)
	pass