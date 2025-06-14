extends Object
class_name AIBrain

signal turn_finished

# Set this to false to disable detailed AI logs
var debug_mode: bool = false
var new_path = []
# Cache to prevent redundant evaluations
var _evaluation_cache = {}
# Path finding optimization
var _last_path_request_time = 0
var _path_cache = {}
var _path_cache_timeout = 1.0 # 1 second timeout for cached paths

# Helper function for debug prints
func debug_print(message):
	if debug_mode:
		print(message)

func execute_turn_sequence(character):
	debug_print("AIBrain: Executing turn sequence for character: " + character.name)
	var max_actions = 3  # Limit the number of actions per turn to prevent infinite loops
	var action_count = 0
	
	while character.stats.current_ap > 0 and action_count < max_actions:
		var immediate_plan = _find_best_immediate_plan(character)
		if immediate_plan == null:
			debug_print("AIBrain: No immediate plan found, ending turn.")
			break
		
		debug_print("AIBrain: Executing immediate plan: " + str(immediate_plan))
		await _execute_plan(character, immediate_plan)
		action_count += 1

	if character.stats.current_sp > 0 and action_count < max_actions:
		debug_print("AIBrain: Executing step sequence.")
		_reposition_with_leftover_sp(character)

	debug_print("AIBrain: End of turn sequence for character: " + character.name)
	turn_finished.emit() # Emit our own signal that turn is finished
	return true # Return a value to indicate completion

func _find_best_immediate_plan(character):
	# var persona = character.stats
	var best_overall_plan = null
	var ability_comp = character.find_child("AbilityComponent") as AbilityComponent
	
	# Reset evaluation cache each turn
	_evaluation_cache = {}
	
	var affordable_abilities = []
	for ability in ability_comp.get_learned_abilities():
		if ability.ap_cost <= character.stats.current_ap:
			affordable_abilities.append(ability)

	debug_print("AIBrain: Affordable abilities for " + character.name + ": " + str(affordable_abilities.size()))
	var opportunities = []
	for ability in affordable_abilities:
		var cache_key = ability.ability_name + "_" + character.name
		var best_use_for_this_ability
		
		if _evaluation_cache.has(cache_key):
			best_use_for_this_ability = _evaluation_cache[cache_key]
		else:
			best_use_for_this_ability = _evaluate_ability_potential(character, ability)
			_evaluation_cache[cache_key] = best_use_for_this_ability
			
		debug_print("AIBrain: Evaluating ability: " + ability.ability_name + " | Score: " + str(best_use_for_this_ability))
		if best_use_for_this_ability:
			opportunities.append(best_use_for_this_ability)
	debug_print("AIBrain: Found " + str(opportunities.size()) + " opportunities for " + character.name)
	opportunities.sort_custom(func(a, b): return a.score >b.score)

	for opportunity in opportunities:
		var path = opportunity.path

		if path.size() <= character.stats.current_sp:
			best_overall_plan = opportunity
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
		debug_print("AIBrain: No potential targets found for ability: " + ability.ability_name)
		return null

	debug_print("AIBrain: Potential targets for ability " + ability.ability_name + ": " + str(potential_targets.size()))
	var character_pos = CombatManager.get_combatant_position(character)

	for target in potential_targets:
		var target_pos = CombatManager.get_combatant_position(target)

		# Check the kind of ability and range
		var valid_casting_positions = []
		if ability.max_range < 1.5: # Melee abilities
			debug_print("AIBrain: Evaluating melee ability for target: " + target.name)
			var check_tiles = CombatManager.get_adjacent_tiles(target_pos)
			for tile in check_tiles:
				valid_casting_positions.append(tile)
			debug_print("AIBrain: Valid casting positions for melee ability: " + str(valid_casting_positions))
		else:
			valid_casting_positions = CombatManager.get_tiles_in_range(character_pos, ability.max_range, character)

		if valid_casting_positions.is_empty():
			debug_print("AIBrain: No valid casting positions for target: " + target.name)
			continue
				
		var closest_path_cost = 100 # Use infinity for initial comparison
		var chosen_casting_pos_for_this_target = null

		# Find the closest target, even outside of range
		for pos in valid_casting_positions:
			debug_print("AIBrain: Evaluating casting position: " + str(pos) + " for target: " + str(target) + " and character position: " + str(character_pos))
			
			# Use cached path finding to avoid redundant calculations
			var path = _get_cached_path(pos, character.global_position)
			
			debug_print("AIBrain: Path from " + str(pos) + " to " + str(character_pos) + ": " + str(path))
			if not path.is_empty():
				debug_print("AIBrain: Path found with length: " + str(path.size()))
				var path_cost = path.size() - 1
				debug_print("AIBrain: Path cost is: " + str(path_cost))
				if path_cost < closest_path_cost:
					closest_path_cost = path_cost
					chosen_casting_pos_for_this_target = pos
					new_path.clear()
					for cell_id in path:
						new_path.append(CombatManager.active_tilemap.to_global(CombatManager.active_tilemap.map_to_local(cell_id)))
					debug_print("AIBrain: " + str(new_path))
					debug_print("AIBrain: " + str(chosen_casting_pos_for_this_target))

		if chosen_casting_pos_for_this_target == null:
			debug_print("AIBrain: No valid casting position found for target: " + target.name)
			continue

		# Calculate the score
		var raw_outcome = 2.0 - (float(target.stats._current_health) / target.stats.max_health)
		var weighted_score = raw_outcome * persona.target_lowest_health
		debug_print("AIBrain: Raw outcome for target " + target.name + ": " + str(raw_outcome) + " | Weighted score: " + str(weighted_score))



		if weighted_score > highest_score:
			highest_score = weighted_score
			best_target_data = {"target_node": target}
			best_casting_tile = chosen_casting_pos_for_this_target

	if highest_score > 0.0:
		return {
			"score": highest_score,
			"casting_tile": best_casting_tile,
			"target_node": best_target_data.target_node,
			"path": new_path
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
		debug_print("AIBrain: Following path for character: " + character.name + " | Path: " + str(plan.path))
		
		# Start following the path
		character.follow_path(plan.path)
		
		# Wait for movement to complete with a timeout
		var timeout = 3.0 # 3 second timeout
		var timer = 0.0
		var movement_done = false
		
		# Set up a one-shot timeout timer
		var wait_timer = character.get_tree().create_timer(timeout)
		wait_timer.timeout.connect(func(): movement_done = true)
		
		# Wait for the movement to complete or timeout
		while not movement_done:
			if not character.is_processing():  # Check if character is still active
				break
				
			# Check if character moved to the end position or got stuck
			if character.global_position.distance_to(plan.path[-1]) < 10:
				debug_print("AIBrain: Character reached destination")
				movement_done = true
				break
			
			await character.get_tree().create_timer(0.1).timeout
		
		debug_print("AIBrain: Path following finished for character: " + character.name)
	
	# Execute the ability if the character is still alive
	if character.stats.is_alive():
		await plan.ability.use_ability(character, plan.casting_tile)
		character.stats.current_ap -= plan.ability.ap_cost
		
	await character.get_tree().create_timer(0.5).timeout # Brief pause between actions

# Signal handler for movement completion
func _on_movement_finished(character):
	debug_print("AIBrain: Movement finished signal received for: " + character.name)

func _reposition_with_leftover_sp(_character):
	pass

func _find_safest_adjacent_tile(character) -> Vector2i:
	var combat_manager = CombatManager
	var current_pos = combat_manager.get_combatant_position(character)
	return current_pos # Placeholder - Replace with real safety logic
	
# Method to toggle debug output on or off
func set_debug_mode(enabled: bool):
	debug_mode = enabled
	debug_print("AIBrain debug mode: " + ("ENABLED" if enabled else "DISABLED"))
	
# Helper function to get path with caching
func _get_cached_path(pos, character_position):
	var current_time = Time.get_ticks_msec() / 1000.0
	var cache_key = str(pos) + "_" + str(character_position)
	
	# If we have a recent cached path, use it
	if _path_cache.has(cache_key) and (current_time - _path_cache[cache_key].time < _path_cache_timeout):
		return _path_cache[cache_key].path
	
	# Otherwise, get a new path
	var path = CombatManager.get_tile_path(pos, character_position)
	_path_cache[cache_key] = {
		"path": path,
		"time": current_time
	}
	_last_path_request_time = current_time
	
	return path
