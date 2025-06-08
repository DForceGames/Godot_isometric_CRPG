extends PanelContainer

@onready var portait_rect: TextureRect = $PortraitRect

var character: Node = null

func set_character_data(combatant: Node):
	self.character = combatant
	if character and character.has_method("get_portrait_texture"):
		portait_rect.texture = character.get_portrait_texture()
	else:
		portait_rect.texture = preload("res://art_source/ui/portraits/default_portrait.png")  # Fallback texture

func set_is_active(is_active: bool):
	if is_active:
		self.modulate = Color.WHITE
	else:
		self.modulate = Color(0.6, 0.6, 0.6)  # Inactive color