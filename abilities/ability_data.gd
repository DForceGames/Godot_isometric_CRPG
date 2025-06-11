# res://Abilities/ability_data.gd
extends Resource
class_name AbilityData

@export var ability_id: StringName          # Unique identifier
@export var ability_name: String
@export_multiline var description: String
@export var icon: Texture2D

@export_group("Gameplay Mechanics")
@export var ap_cost: int = 1
@export var cooldown_time: float = 0.0 # Cooldown in turns
@export var max_range: int = 1 # Range of ability in tiles
@export var min_range: int = 0 # Minimum range, e.g., for melee abilities
@export var ability_power: float = 0 # Base power of the ability, e.g., damage or healing amount

enum AoeShape {
	NONE,
	CIRCLE,
	SQUARE,
	VLINE,
	HLINE,
	DIAGONAL
}
@export var aoe_shape: AoeShape = AoeShape.NONE # Area of effect shape 
@export var area_of_effect_radius: int = 0 # For abilities that affect an area


@export_group("Visuals & Audio")
@export var animation_name: StringName # Animation to play on the caster
@export var projectile_scene: PackedScene # For ranged attacks
@export var impact_effect_scene: PackedScene # e.g., explosion, hit spark
@export var cast_sound: AudioStream
@export var impact_sound: AudioStream

enum TargetType {
	SELF,
	ENEMY,
	ALLY,
	AREA
}
@export var target_type: TargetType = TargetType.SELF

func use_ability(tile):
	print("Using ability: ", ability_name, " at tile: ", tile)
