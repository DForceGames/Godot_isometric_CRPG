extends StaticBody2D

@onready var game_state_manager = get_node("/root/GameStateManager")

@export var chest_opened: bool = false  # Whether the chest has been opened
@export var container_id: int = 1  # Unique identifier for the chest

func _ready():
	if "opened_containers" in game_state_manager:
		# Check if this chest has already been opened
		if container_id in game_state_manager.opened_containers:
			chest_opened = true
			print("This chest has already been opened.")
		else:
			print("This chest is available to open.")
	else:
		game_state_manager.opened_containers = []  # Initialize if not present


# Make it interatable when player is wihtin range
func interact() -> void:
	if not chest_opened:
		open_chest()
	else:
		print("The chest is already opened.")

func open_chest() -> void:
	if not chest_opened:
		chest_opened = true
		var random_loot = generate_loot()
		add_loot(random_loot)
		add_opened_container(container_id)
		print("Chest opened! You found some loot!")
		print("Loot details: ", random_loot)
		# Here you can add logic to give the player items, gold, etc.
	else:
		print("The chest is already opened.")

func generate_loot() -> Dictionary:
	# Example loot generation logic
	var loot = {
		"gold": randi() % 100 + 1,  # Random gold between 1 and 100
		"items": []
	}
	
	# Randomly add some items
	var item_count = randi() % 3 + 1  # Between 1 and 3 items
	for i in range(item_count):
		var item_name = "Item_" + str(randi() % 10)  # Random item name
		loot["items"].append(item_name)
	
	return loot

func add_loot(loot: Dictionary) -> void:
	# Logic to add loot to the player's inventory
	# This is a placeholder; you would replace this with your actual inventory logic
	print("Adding loot to player's inventory:")
	print("Gold: ", loot.get("gold", 0))
	print("Items: ", loot.get("items", []))
	
	# Here you would typically call a method on the player or inventory manager to add the loot
	# Example: get_node("/root/Player").add_gold(loot["gold"])
	# Example: get_node("/root/InventoryManager").add_items(loot["items"])

# Function to add chest's container_id to the list of opened containers
func add_opened_container(id: int) -> void:
	game_state_manager.opened_containers.append(id)
	# game_state_manager is globally accessible object
	print("Container with ID ", id, " has been marked as opened.")
	
	# Example: You might want to store this in a global list or a player's data structure
	# get_node("/root/Player").add_opened_container(id)
