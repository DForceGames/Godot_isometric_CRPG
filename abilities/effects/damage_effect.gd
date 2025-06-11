extends AbilityEffect
class_name DamageEffect

func execute(user, center_tile, AoE, damage):
	print("Executing DamageEffect for user: ", user, " on tile: ", center_tile)
	print("Affected tiles: ", AoE)

	for tile in AoE:
		var combatant = CombatManager.get_combatant_at_tile(tile)
		if is_instance_valid(combatant):
			print("Applying damage to combatant: ", combatant.name)
			combatant.stats.take_damage(damage)
