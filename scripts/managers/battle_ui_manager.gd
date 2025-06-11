extends CanvasLayer

@onready var turn_order_display = $TurnOrder

@onready var anim_player = $AnimationPlayer

func _ready():
	# Start hidden
	visible = false
	
	# Connect to the CombatManager signals
	var combat_manager = get_node_or_null("/root/CombatManager")
	if combat_manager:
		# We need to make sure our signal handlers can receive arguments
		combat_manager.combat_started.connect(_on_combat_started)
		combat_manager.combat_ended.connect(_on_combat_ended)
		combat_manager.turn_started.connect(_on_turn_started)
	else:
		printerr("BattleUIManager: CombatManager not found!")

func _on_combat_started(turn_queue: Array[Node]):
	# Make the entire battle UI visible with an animation
	visible = true
	print("BattleUIManager: Combat started with turn queue: ", turn_queue)
	# anim_player.play("show") # Assuming you have a "show" animation

	await turn_order_display.ready

	# Tell the TurnOrderDisplay to populate itself with the combatants
	print("BattleUIManager: Populating turn order display with combatants.")
	turn_order_display.populate(turn_queue)

func _on_combat_ended(_result: String):
	# Hide the UI when combat ends
	anim_player.play("hide")
	await anim_player.animation_finished
	visible = false

	# Also tell the TurnOrderDisplay to clean up its icons
	turn_order_display.clear_icons()

func _on_turn_started(character_node: Node):
	turn_order_display.update_active_icon(character_node)


func _on_end_turn_button_pressed() -> void:
	print("BattleUI: End Turn button pressed")
	CombatManager.end_current_turn()
