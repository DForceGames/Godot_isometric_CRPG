# scripts/interactable/interactable.gd
extends Node2D

signal interaction_started(interactable_id)
signal interaction_ended(interactable_id)

@export var interactable_id: String = ""
@export var is_interactive: bool = true

func _ready():
    if interactable_id.is_empty():
        interactable_id = str(get_instance_id())
    
    # Add to interactable group
    add_to_group("interactable")
    
    # Make sure this interactable has collision
    var has_collision = false
    for child in get_children():
        if child is CollisionShape2D or child is CollisionPolygon2D:
            has_collision = true
            break
    
    if not has_collision:
        print("WARNING: Interactable ", name, " has no collision shape. Pathfinding may not avoid it.")

func interact() -> void:
    print("Interactable base interact() called")
    if not is_interactive:
        return
    
    # Emit signal
    interaction_started.emit(interactable_id)
    
    # Override in child classes to implement specific behavior
    
func end_interaction() -> void:
    # Emit signal
    interaction_ended.emit(interactable_id)