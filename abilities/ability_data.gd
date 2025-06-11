# res://Abilities/ability_data.gd
extends Resource
class_name AbilityData

@export var ability_id: StringName          # Unique identifier
@export var ability_name: String
@export_multiline var description: String
@export var icon: Texture2D
@export var damage_type: String # e.g., "physical", "magical", "healing"
@export var damage_multiplier: float = 1.0 # Multiplier for damage or healing effects

@export_group("Gameplay Mechanics")
@export var ap_cost: int = 1
@export var cooldown_time: float = 0.0 # Cooldown in turns
@export var max_range: int = 1 # Range of ability in tiles
@export var min_range: int = 0 # Minimum range, e.g., for melee abilities
@export var ability_power: float = 0 # Base power of the ability, e.g., damage or healing amount

@export_group("Targeting & Area of Effect")
enum TargetType {
	SELF,
	ENEMY,
	ALLY,
	AREA
}
@export var target_type: TargetType = TargetType.SELF
enum AoeShape {
	NONE,
	CIRCLE,
	SQUARE,
	VLINE,
	HLINE,
	DIAGONAL
}
@export var aoe_shape: AoeShape # Area of effect shape 
@export var area_of_effect_radius: int = 0 # For abilities that affect an area

@export var effects: Array[AbilityEffect] = []

@export_group("Visuals & Audio")
@export var animation_name: StringName # Animation to play on the caster
@export var projectile_scene: PackedScene # For ranged attacks
@export var impact_effect_scene: PackedScene # e.g., explosion, hit spark
@export var cast_sound: AudioStream
@export var impact_sound: AudioStream

func use_ability(user, center_tile):
	if user.stats.current_ap < ap_cost:
		print("Not enough AP to use ability: " + ability_name)
		return
	print("Using ability: "+ ability_name)
	var affected_tiles = CombatManager.get_aoe_tiles(center_tile, self)
	var damage = calc_damage(user)

	for effect in effects:
		if effect:
			effect.execute(user, center_tile, affected_tiles, damage)


	# Spend AP
	user.stats.current_ap -= ap_cost

func calc_damage(user):
	var base_damage = user.stats.attack_power * damage_multiplier
	return base_damage
