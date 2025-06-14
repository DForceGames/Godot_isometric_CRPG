extends AbilityEffect
class_name DamageEffect

func execute(user, center_tile, aoe, damage):
	print("Executing DamageEffect for user: ", user, " on tile: ", center_tile)
	print("Affected tiles: ", aoe)
	for tile in aoe:
		var target = CombatManager.get_combatant_at_tile(tile)
		print("Checking combatant at tile: ", tile, " - Target Character: ", target)
		if is_instance_valid(target):
			print("Applying damage to target: ", target.name)
			target.stats.take_damage(damage)
