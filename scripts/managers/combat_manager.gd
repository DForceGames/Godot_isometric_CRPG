extends Node

# Signals
signal combat_started(turn_order)
signal combat_ended(result)
signal turn_started(combatant)
signal new_round_started(round_number)

var npc_id

var turn_queue: Array[Node] = []
var turn_index: int = -1
var round_number: int = 1
var is_combat_ended: bool = false

func start_combat(player_party, enemies):
	turn_queue.clear()
	turn_index = -1
	round_number = 1

	var combatants_with_rolls = []

	# Setup gridmap from player_movement.gd
	var player_movement = get_node_or_null("/root/actors/player/player_movement.gd")
	if player_movement:
		player_movement.initialize_grid()

	# Turn order setup
	for player in player_party:
		if is_instance_valid(player):
			combatants_with_rolls.append({"Node": player,"Roll": player.stats.initiative})
	
	for enemy in enemies:
		if is_instance_valid(enemy):
			combatants_with_rolls.append({"Node": enemy,"Roll": enemy.initiative})
	
	combatants_with_rolls.sort_custom(func(a, b): return a.Roll > b.Roll)
	print("CombatManager: Combat started with turnorder:" + str(turn_queue))

	for combatant_data in combatants_with_rolls:
		var combatant = combatant_data["Node"]
		turn_queue.append(combatant)
		if combatant.has_method("on_start_combat"):
			combatant.on_start_combat()

	combat_started.emit(turn_queue)

	next_turn()

func end_combat(result: String):
	# Safety check
	if is_combat_ended:
		return
	
	# Signal for rewards or loss
	is_combat_ended = true
	combat_ended.emit(result)

	# Cleanup
	for combatant in turn_queue:
		if not is_instance_valid(combatant):
			if combatant.has_method("end_combat"):
				continue

		# if combatant.died.is_connected(on_combatant_died):
		#     combatant.died.disconnect(on_combatant_died)

		if combatant.has_method("end_combat"):
			combatant.end_combat()
		
	# Reset
	turn_queue.clear()
	turn_index = -1
	round_number = 1

func check_end_of_combat_conditions():
	if is_combat_ended:
		return
	
	var player_combatants_alive = false
	var enemy_combatants_alive = false

	for combatant in turn_queue:
		if combatant.is_dead:
			continue
		if combatant.is_player:
			player_combatants_alive = true
		elif combatant.is_enemy:
			enemy_combatants_alive = true

	if not player_combatants_alive:
		end_combat("DEFEAT")
		return
	elif not enemy_combatants_alive:
		end_combat("VICTORY")
	
	return

# handle turn logic
func next_turn():
	# safety check
	if is_combat_ended:
		return
	
	turn_index += 1
	
	# Check turn and round progression
	if turn_index >= turn_queue.size():
		turn_index = -1
		round_number += 1
		new_round_started.emit(round_number)
	
	var current_combatant = turn_queue[turn_index]
	# Skip dead combatants
	while is_instance_valid(current_combatant) and current_combatant.stats.is_alive() == false:
		print("CombatManager: Skipping dead combatant %s" % current_combatant.name)
		next_turn()
		return

	_begin_turn_for(current_combatant)

func _begin_turn_for(combatant: Node):
	if combatant.has_method("on_start_turn"):
		combatant.on_start_turn()
	
	if combatant.has_method("process_statuses"):
		combatant.process_statuses()
	
	if combatant.stats.is_alive() == false:
		print("CombatManager: Combatant %s is dead, skipping turn." % combatant.name)
		next_turn()
		return
	
	turn_started.emit(combatant)

func end_current_turn():
	# safety check
	if is_combat_ended:
		return
	
	check_end_of_combat_conditions()
	
	next_turn()
