# scripts/interactable/container.gd
extends Interactable
class_name Chest

var inventory = []
@export var container_type: String = "chest"

func _ready():
    super()  # Call parent _ready
    add_to_group("container")
    
func interact() -> void:
    super()  # Call parent interact
    print("Container: Opening " + container_type)
    
    # Open container UI here
    var inventory_manager = get_node_or_null("/root/InventoryManager")
    if inventory_manager:
        inventory_manager.open_container(self)
        
func end_interaction() -> void:
    # Close container UI here
    var inventory_manager = get_node_or_null("/root/InventoryManager")
    if inventory_manager:
        inventory_manager.close_container()
        
    super()  # Call parent end_interaction