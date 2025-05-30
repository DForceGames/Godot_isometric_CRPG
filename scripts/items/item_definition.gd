extends Resource
class_name ItemDefinition # Makes it easy to reference this type

# The base class for defining items in the game.
# This class can be extended to create specific item types with unique behaviors.

## The display name of the item.
@export var item_name: String = "Unnamed Item"

## A description of the item, shown in UI (e.g., tooltips).
@export var description: String = ""

## Texture for the item's icon in the inventory UI.
@export var icon: Texture2D

## Can this item be stacked in a single inventory slot?
@export var stackable: bool = false

## If stackable, what's the maximum number of items in one stack?
@export var max_stack_size: int = 1

## A general type for the item (e.g., "potion", "weapon", "armor", "key", "material").
## This can be used for quick categorization.
@export var item_type: String = "generic"
