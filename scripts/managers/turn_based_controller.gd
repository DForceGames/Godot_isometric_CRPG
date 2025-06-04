extends Node
# class_name TurnBasedController # No longer the main controller

# THIS SCRIPT IS DEPRECATED.
# Its responsibilities for turn order management and active character control
# have been moved to CombatManager.gd.

# The TurnOrderUI (turn_order.gd) should now connect to signals
# from CombatManager (e.g., CombatManager.turn_order_updated)
# to refresh its display.

# It is recommended to remove this node and script from your scene(s)
# if CombatManager is correctly set up and integrated.

func _ready() -> void:
	printerr("DEPRECATION WARNING: TurnBasedController is still in the scene but its functionality has been migrated to CombatManager. Please remove TurnBasedController.")
	# queue_free() # Optionally, self-destruct to prevent issues
