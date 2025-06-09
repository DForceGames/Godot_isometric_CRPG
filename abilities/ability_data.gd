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
@export var area_of_effect_radius: int = 0 # For abilities that affect an area
# Add more common properties:
#@export var damage_type: Enum.DamageType # you'd define this enum
#@export var target_type: Enum.TargetType # Ensure TargetType is defined within your Enum scope (e.g., an Enum script or class)
# @export var effects_to_apply: Array[StatusEffectData] # Another custom resource

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

# You might add a base 'execute' method here if there's common activation logic,
# or leave it to an AbilityHandler.
# func activate(caster: Node, target_data: Dictionary):
#     pass
#func use_ability(caster: Node, target_data: Dictionary) -> void:
	# This method can be overridden by specific ability implementations
	# to define how the ability is used.
	#pass
