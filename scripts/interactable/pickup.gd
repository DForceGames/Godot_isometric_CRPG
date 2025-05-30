# scripts/interactable/pickup.gd
extends Interactable
class_name Pickup

@export var item_id: String = ""
@export var quantity: int = 1

func _ready():
    super()  # Call parent _ready
    add_to_group("pickup")
    
func interact() -> void:
    super()  # Call parent interact
    print("Pickup: Collecting item " + item_id)
    
    # Add to player inventory
    var inventory_manager = get_node_or_null("/root/InventoryManager")
    if inventory_manager:
        inventory_manager.add_to_player_inventory(item_id, quantity)
        
    # Remove the pickup from the scene
    queue_free()