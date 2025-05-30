extends ItemDefinition
class_name HealthPotion

# A health potion item that restores health when used.
@export var health_restored: int = 50  # Amount of health restored by this potion
@export var potion_icon: Texture2D  # Icon for the health potion
@export var potion_description: String = "Restores %d health points." % health_restored
@export var potion_name: String = "Health Potion"

func _init():
    # Initialize the potion with its specific properties
    item_name = potion_name
    description = potion_description
    icon = potion_icon
    item_type = "consumable"  # Set the item type to consumable
    stackable = true  # Potions can be stacked
    max_stack_size = 10  # Up to 10 potions can be stacked in one slot

func use(user_node: Node) -> bool:
    if not user_node or not user_node.has_method("restore_health"):
        print("Cannot use Health Potion: Invalid user node or missing restore_health method.")
        return false

    # Call the user's restore_health method to apply the potion's effect
    var success = user_node.restore_health(health_restored)
    if success:
        print("Used Health Potion: Restored %d health." % health_restored)
        return true
    else:
        print("Failed to use Health Potion.")
        return false
