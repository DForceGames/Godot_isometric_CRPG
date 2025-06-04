extends Resource
class_name EncounterData

# Array of dictionaries, each defining an enemy type and count
# Example: [{"scene_path": "res://Actors/Enemies/Enemy_1.tscn", "count": 2, "level": 5},
#           {"scene_path": "res://Actors/Enemies/Enemy_2.tscn", "count": 1, "level": 6}]
@export var enemy_scene: PackedScene
@export var count: int = 1
@export var level: int = 1

# You could add other properties like music, specific battle background, etc.
@export var combat_music: AudioStream