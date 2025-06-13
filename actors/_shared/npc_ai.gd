extends Object
class_name AIBrain

signal turn_finished

func execute_turn_sequence(character):
	print("AIBrain: Executing turn sequence.")
	while character.stats.current_ap > 0:
		var immediate_plan = _find_best_immediate_plan(character)
		if immediate_plan == null:
			print("AIBrain: No immediate plan found, ending turn.")
			break
		print("AIBrain: Executing immediate plan: ", immediate_plan)
		_execute_plan(character, immediate_plan)

	if character.stats.current_sp > 0:
		print("AIBrain: Executing step sequence.")
		_reposition_with_leftover_sp(character)

	turn_finished.emit()
	print("AIBrain: End of turn sequence for character: ", character.name)

func _find_best_immediate_plan(character):
	# var persona = character.stats
	var best_overall_plan = null
	var ability_comp = character.find_child("AbilityComponent") as AbilityComponent

	var affordable_abilities = []
	for ability in ability_comp.get_learned_abilities():
		if ability.ap_cost <= character.stats.current_ap:
			affordable_abilities.append(ability)

	print("AIBrain: Affordable abilities for ", character.name, ": ", affordable_abilities.size())
	var opportunities = []
	for ability in affordable_abilities:
		var best_use_for_this_ability = _evaluate_ability_potential(character, ability)
		print("AIBrain: Evaluating ability: ", ability.ability_name, " | Score: ", best_use_for_this_ability)
		if best_use_for_this_ability:
			opportunities.append(best_use_for_this_ability)
	print("AIBrain: Found ", opportunities.size(), " opportunities for ", character.name)
	opportunities.sort_custom(func(a, b): return a.score >b.score)

	for opportunity in opportunities:
		var current_pos = CombatManager.combatant_positions.get(character)
		var path = CombatManager.get_tile_path(opportunity.casting_tile, current_pos.global_position)

		if path.size() <= character.stats.current_sp:
			best_overall_plan = opportunity
			best_overall_plan.path = path
			break

	return best_overall_plan

func _evaluate_ability_potential(character, ability):
	var evaluation_result = null
	if ability.area_of_effect_radius == 0:
		evaluation_result = _evaluate_single_target_ability(character, ability)
	else:
		evaluation_result = _evaluate_area_of_effect_ability(character, ability)

	if evaluation_result != null and evaluation_result.score > 0.0:
		evaluation_result.ability = ability
		return evaluation_result

func _evaluate_single_target_ability(character, ability):
	var persona = character.stats
	var highest_score = 0.0
	var best_target_data = {}
	var best_casting_tile = null

	var potential_targets = []
	if ability.target_type == 1: # Enemy for AI
		potential_targets = CombatManager.get_all_players()
	elif ability.target_type == 2: # Ally for AI
		potential_targets = CombatManager.get_all_enemies()
	if potential_targets.is_empty():
		print("AIBrain: No potential targets found for ability: ", ability.ability_name)
		return null

	print("AIBrain: Potential targets for ability ", ability.ability_name, ": ", potential_targets.size())
	var character_pos = CombatManager.get_combatant_position(character)

	for target in potential_targets:
		var target_pos = CombatManager.get_combatant_position(target)

		# Check the kind of ability and range
		var valid_casting_positions = []
		if ability.max_range < 1.5: # Melee abilities
			print("AIBrain: Evaluating melee ability for target: ", target.name)
			var check_tiles = CombatManager.get_adjacent_tiles(target_pos)
			for tile in check_tiles:
				valid_casting_positions.append(tile)
			print("AIBrain: Valid casting positions for melee ability: ", valid_casting_positions)
		else:
			valid_casting_positions = CombatManager.get_tiles_in_range(character_pos, ability.max_range, character)

		if valid_casting_positions.is_empty():
			print("AIBrain: No valid casting positions for target: ", target.name)
			continue
				
		var closest_path_cost = INF # Use infinity for initial comparison
		var chosen_casting_pos_for_this_target = null

		# Find the closest target, even outside of range
		for pos in valid_casting_positions:
			print("AIBrain: Evaluating casting position: ", pos, " for target: ", target)
			var path = CombatManager.get_tile_path(pos, character_pos)
			print("AIBrain: Path from ", pos, " to ", character_pos, ": ", path)
			if not path.is_empty() or character_pos == pos:
				# Check if a path exists or we're already there
				var path_cost = path.size()
				print(path_cost)
				if path_cost < closest_path_cost:
					closest_path_cost = path_cost
					chosen_casting_pos_for_this_target = pos
					print("AIBrain: ",chosen_casting_pos_for_this_target)
		
		if chosen_casting_pos_for_this_target == null:
			print("AIBrain: No valid casting position found for target: ", target.name)
			continue

		# Calculate the score
		var raw_outcome = 1.0 - (float(target.stats._current_health) / target.stats.max_health)
		var weighted_score = raw_outcome * persona.target_lowest_health



		if weighted_score > highest_score:
			highest_score = weighted_score
			best_target_data = {"target_node": target}
			best_casting_tile = chosen_casting_pos_for_this_target

	if highest_score > 0.0:
		return {
			"score": highest_score,
			"casting_tile": best_casting_tile,
			"target_node": best_target_data.target_node,
		}
	return null

func _evaluate_area_of_effect_ability(character, ability):
	var combat_manager = CombatManager
	var persona = character.stats
	var highest_score = 0.0
	var best_target_data = {}
	var best_casting_pos = null

	var character_pos = combat_manager.get_combatant_position(character)
	var reachable_tiles = combat_manager.get_tiles_in_range(character_pos, character.stats.current_sp, character)

	for cast_pos in reachable_tiles:
		var possible_aoe_centers = combat_manager.get_tiles_in_range(cast_pos, ability.range, character)
		for aoe_center_pos in possible_aoe_centers:
			var units_in_aoe = combat_manager.get_units_in_aoe_tiles(aoe_center_pos, ability)
			
			var current_aoe_score = 0.0
			for unit in units_in_aoe:
				if unit.is_in_group("Player"):
					current_aoe_score += (1.0 - (float(unit.stats.health) / unit.stats.max_health)) * persona.target_lowest_health
				elif unit.is_in_group("Enemy"):
					current_aoe_score -= 10.0 * persona.self_preserve
			
			if current_aoe_score > highest_score:
				highest_score = current_aoe_score
				best_target_data = {"target_position": aoe_center_pos}
				best_casting_pos = cast_pos

	if highest_score > 0.0:
		return {"target_data": best_target_data, "casting_position": best_casting_pos, "score": highest_score}
	return null

func _execute_plan(character, plan: Dictionary):
	if plan.has("path") and plan.path != null and plan.path.size() > 0:
		character.follow_path(plan.path)
	
	plan.ability.use_ability(character, plan.casting_tile)
	character.stats.current_ap -= plan.ability.ap_cost

func _reposition_with_leftover_sp(_character):
	pass

func _find_safest_adjacent_tile(character) -> Vector2i:
	var combat_manager = CombatManager
	var current_pos = combat_manager.get_combatant_position(character)
	return current_pos # Placeholder - Replace with real safety logic
