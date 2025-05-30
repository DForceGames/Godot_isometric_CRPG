extends Button

@export var player_node_path: NodePath


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	if player_node_path.is_empty():
		printerr("RefreshButton: Player node path not set.")
		return

	var player_node = get_node_or_null(player_node_path)
	if not player_node:
		printerr("RefreshButton: Player node not found at path: ", player_node_path)
		return

	if player_node.has_method("Refresh_resources"):
		player_node.Refresh_resources()
		print("RefreshButton: Called Refresh_resources on player.")
	else:
		printerr("RefreshButton: Player node does not have Refresh_resources method.")


func _process(_delta: float) -> void:
	pass
