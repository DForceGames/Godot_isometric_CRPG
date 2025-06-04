# Attached as a child node to your Player scene
class_name AbilityComponent
extends Node

@export var known_abilities: Array[AbilityData] # Assign your .tres ability files here in the Inspector
var ability_cooldowns: Dictionary = {} # To track cooldowns: {ability_id: time_remaining}

func _process(delta):
    # Update cooldowns
    for ability_id in ability_cooldowns:
        ability_cooldowns[ability_id] = max(0.0, ability_cooldowns[ability_id] - delta)

func can_use_ability(ability_data: AbilityData, player_stats) -> bool:
    if not ability_data:
        return false
    if ability_cooldowns.get(ability_data.id, 0) > 0:
        print("%s is on cooldown." % ability_data.ability_name)
        return false
    if player_stats.current_ap < ability_data.ap_cost: # Assuming current_sp is on player
        print("Not enough AP for %s." % ability_data.ability_name)
        return false
    # Add other checks like range, line of sight, target validity etc.
    return true

func use_ability(ability_id: int, player_node: CharacterBody2D, target_data: Dictionary = {}):
    var ability_data: AbilityData = null
    for ab in known_abilities:
        if ab.id == ability_id:
            ability_data = ab
            break

    if not ability_data:
        printerr("Ability %s not found!" % ability_id)
        return

    # Assuming player_node.stats exists and can_use_ability is updated
    # to use player_node.stats.get_current_ap()
    if not can_use_ability(ability_data, player_node): 
        return

    print("Using ability: %s" % ability_data.ability_name)

    # Deduct AP using the new Stats method
    player_node.stats.spend_ap(ability_data.ap_cost) 
    # Assuming the signal is meant to reflect the new AP value,
    # and player_node.stats.get_current_ap() returns the updated AP.
    # If _on_sp_changed is strictly for SP and SP is a separate stat, 
    # this line might need different handling based on your Stats class.
    player_node.emit_signal("_on_sp_changed", player_node.stats.get_current_ap())

    # Set cooldown
    ability_cooldowns[ability_data.id] = ability_data.cooldown_time

    # Play caster animation (from player's AnimatedSprite2D or AnimationPlayer)
    var anim_sprite = player_node.get_node_or_null("AnimatedSprite2D") # Or your animation player
    if anim_sprite and ability_data.animation_name != &"":
        # You'll need logic to determine direction for the animation like in your basic attack
        # e.g., anim_sprite.play(str(ability_data.animation_name) + "_" + player_node.facing_direction_string)
        anim_sprite.play(ability_data.animation_name) # Simplified

    # Play cast sound
    if ability_data.cast_sound:
        # Get or create an AudioStreamPlayer node to play this
        pass 

    # --- Execute ability-specific logic ---
    # This part can get more complex. You might have different functions based on ability_type or target_type.

    if ability_data.projectile_scene: # Ranged attack
        var projectile = ability_data.projectile_scene.instantiate()
        # Setup projectile (position, direction, damage from ability_data, who fired it)
        player_node.get_parent().add_child(projectile) # Add to scene tree
        projectile.global_position = player_node.global_position # Or a muzzle position
        # projectile.fire(player_node.global_position.direction_to(target_data.get("target_pos", player_node.global_position + player_node.facing_direction * 100)), ability_data, player_node)

    elif ability_data.damage > 0: # Melee or direct damage ability
        # Find targets in range/area (similar to your _find_attack_target)
        var targets = _find_targets_for_ability(player_node, ability_data, target_data)
        for target_enemy in targets:
            if target_enemy.has_method("take_damage"):
                target_enemy.take_damage(ability_data.damage) # Pass more data if needed

        if ability_data.impact_effect_scene and targets.size() > 0:
            # Instantiate impact effect at target or player position
            pass

    # Handle buffs, debuffs, healing, etc. based on ability_data properties

# Helper to find targets, can be more sophisticated
func _find_targets_for_ability(caster: Node2D, ability: AbilityData, target_data: Dictionary) -> Array[Node2D]:
    var found_targets: Array[Node2D] = []
    # Example: Simple melee range check
    var enemies = caster.get_tree().get_nodes_in_group("enemies")
    for enemy in enemies:
        if enemy is Node2D and caster.global_position.distance_to(enemy.global_position) <= ability.range:
            # Add line of sight, cone checks etc.
            found_targets.append(enemy)
    return found_targets

func decrement_turn_based_cooldowns():
    var keys_to_update = ability_cooldowns.keys() # Iterate over a copy of keys
    for ability_id_key in keys_to_update:
        if ability_cooldowns[ability_id_key] > 0:
            ability_cooldowns[ability_id_key] -= 1 # Decrement by 1 turn
            if ability_cooldowns[ability_id_key] < 0: # Ensure it doesn't go below zero
                ability_cooldowns[ability_id_key] = 0