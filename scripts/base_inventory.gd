extends Node

# Signal emitted when the inventory contents change
signal inventory_changed(inventory_node)

# Default inventory size, can be overridden in inheriting scripts or in the editor
@export var inventory_size: int = 9

# Array to store the items. The structure of item_data is up to you.
# It could be a Dictionary, a custom Resource, or an ID.
var items: Array = []

func _ready():
	# Initialize the items array to have a fixed size, if desired,
	# or allow it to grow dynamically. For a fixed size based on inventory_size:
	items.resize(inventory_size) # Fills with null by default
	# If you prefer a dynamic list, you can skip items.resize()
	# and check items.size() < inventory_size in can_add_item.
	print("BaseInventory initialized with size: %d" % inventory_size)

# --- Core Inventory Functions ---

## Checks if an item can be added to the inventory.
## item_data: The item to potentially add.
## Returns: true if the item can be added, false otherwise.
func can_add_item(_item_data) -> bool:
	# Check for an empty slot
	for i in range(items.size()):
		if items[i] == null:
			return true
	# Alternative for dynamic list:
	# if items.size() < inventory_size:
	# 	return true
	print("Inventory is full. Cannot add item.")
	return false

## Adds an item to the first available slot in the inventory.
## item_data: The item to add.
## Returns: true if the item was added successfully, false otherwise.
func add_item(item_data) -> bool:
	if not item_data:
		printerr("Attempted to add null item_data.")
		return false
		
	if can_add_item(item_data):
		for i in range(items.size()):
			if items[i] == null:
				items[i] = item_data
				print("Item added to slot %d: %s" % [i, str(item_data)])
				inventory_changed.emit(self)
				return true
		# Should not be reached if can_add_item is implemented correctly with fixed size
		# For dynamic list:
		# items.append(item_data)
		# print("Item added: %s" % str(item_data))
		# inventory_changed.emit(self)
		# return true
	return false

## Removes an item from the inventory.
## item_slot_or_data: Can be an integer (slot index) or the item_data itself to find and remove.
## Returns: true if the item was removed successfully, false otherwise.
func remove_item(item_slot_or_data) -> bool:
	if item_slot_or_data is int: # Removing by slot index
		var slot_index = item_slot_or_data
		if slot_index >= 0 and slot_index < items.size() and items[slot_index] != null:
			var removed_item = items[slot_index]
			items[slot_index] = null
			print("Item removed from slot %d: %s" % [slot_index, str(removed_item)])
			inventory_changed.emit(self)
			return true
		else:
			printerr("Failed to remove item: Invalid slot index %d or slot is empty." % slot_index)
			return false
	else: # Removing by item data (first occurrence)
		var item_data_to_remove = item_slot_or_data
		for i in range(items.size()):
			if items[i] == item_data_to_remove: # Note: This requires proper equality check for complex item_data
				var removed_item = items[i]
				items[i] = null # Or use items.remove_at(i) for dynamic list
				print("Item removed by data from slot %d: %s" % [i, str(removed_item)])
				inventory_changed.emit(self)
				return true
		printerr("Failed to remove item: Item data not found: %s" % str(item_data_to_remove))
		return false

## Placeholder for using an item from the inventory.
## item_slot_or_data: Can be an integer (slot index) or the item_data itself.
func use_item(item_slot_or_data):
	var item_to_use = null
	var slot_used = -1

	if item_slot_or_data is int:
		var slot_index = item_slot_or_data
		if slot_index >= 0 and slot_index < items.size() and items[slot_index] != null:
			item_to_use = items[slot_index]
			slot_used = slot_index
		else:
			printerr("Cannot use item: Invalid slot index %d or slot is empty." % slot_index)
			return
	else:
		# Find the item by data if you want to allow using item by reference/value
		# For simplicity, this example assumes using by slot is primary
		printerr("Using item by data reference not fully implemented in this example. Please use slot index.")
		# Example: Find first occurrence
		# for i in range(items.size()):
		# 	if items[i] == item_slot_or_data:
		# 		item_to_use = items[i]
		#		slot_used = i
		# 		break
		if item_to_use == null:
			printerr("Cannot use item: Item data not found: %s" % str(item_slot_or_data))
			return

	if item_to_use:
		print("Using item from slot %d: %s" % [slot_used, str(item_to_use)])
		#
		# --- Add your item usage logic here ---
		# e.g., check item type, apply effects, consume item, etc.
		# Example: if item_to_use.has("type") and item_to_use.type == "potion":
		# 	get_parent().heal(item_to_use.heal_amount) # Assuming player is parent
		# 	remove_item(slot_used) # Consume the potion
		#
		inventory_changed.emit(self) # Emit if usage changes inventory (e.g. consumption)
	else:
		# This case should ideally be caught by earlier checks
		printerr("Failed to identify item to use with: %s" % str(item_slot_or_data))


# --- Helper Functions (Optional) ---

## Gets the item at a specific slot.
## slot_index: The integer index of the slot.
## Returns: The item_data at the slot, or null if slot is empty or invalid.
func get_item_at_slot(slot_index: int):
	if slot_index >= 0 and slot_index < items.size():
		return items[slot_index]
	printerr("Invalid slot index: %d" % slot_index)
	return null

## Clears the entire inventory.
func clear_inventory():
	for i in range(items.size()):
		items[i] = null
	# For dynamic list: items.clear()
	print("Inventory cleared.")
	inventory_changed.emit(self)

## Returns the number of currently filled slots.
func get_item_count() -> int:
	var count = 0
	for item in items:
		if item != null:
			count += 1
	return count

## Returns the total capacity of the inventory.
func get_capacity() -> int:
	return inventory_size # or items.size() if using fixed-size array initialized in _ready

## Prints the current inventory contents to the console (for debugging).
func print_inventory_contents():
	print("--- Inventory (Size: %d/%d) ---" % [get_item_count(), get_capacity()])
	for i in range(items.size()):
		if items[i] != null:
			print("Slot %d: %s" % [i, str(items[i])])
		else:
			print("Slot %d: Empty" % i)
	print("---------------------------")

