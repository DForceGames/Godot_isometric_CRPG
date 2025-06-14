extends PanelContainer

const TurnOrderIcon = preload("res://ui/BattleUI/character_icon_display.tscn")

@onready var container: HBoxContainer =  %CharacterContainer

func populate(turn_queue: Array[Node]):
	clear_icons()
	print("Populating turn order with characters: ", turn_queue)
	for character in turn_queue:
		var icon_instance = TurnOrderIcon.instance()
		icon_instance.set_character_data(character)
		container.add_child(icon_instance)

func update_active_icon(active_character: Node):
	for icon in container.get_children():
		if icon.character == active_character:
			icon.set_is_active(true)
		else:
			icon.set_is_active(false)

func clear_icons():
	for icon in container.get_children():
		icon.queue_free()
