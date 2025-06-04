# res://UI/Combat/AbilityButton.gd
extends TextureButton # Or Button

signal ability_action_initiated(ability_data: AbilityData) # Renamed for clarity

var current_ability_data: AbilityData

@onready var icon_rect: TextureRect = $IconRect # Assuming IconRect is a child
@onready var ap_cost_label: Label = $APCostLabel # Assuming APCostLabel is a child
@onready var cooldown_overlay: Panel = $CooldownOverlay # Assuming CooldownOverlay is a child

func set_ability_data(ability_data: AbilityData):
    current_ability_data = ability_data
    if icon_rect and ability_data.icon:
        icon_rect.texture = ability_data.icon
    if ap_cost_label:
        ap_cost_label.text = str(ability_data.ap_cost) # + " AP" (optional)
    # Hide by default, update_visuals will show if needed
    if cooldown_overlay:
        cooldown_overlay.visible = false
    self.tooltip_text = "%s\n%s" % [ability_data.ability_name, ability_data.description]

func _on_pressed():
    if current_ability_data and not self.disabled:
        emit_signal("ability_action_initiated", current_ability_data)

func update_visuals(cooldown_remaining: float, is_usable: bool):
    if not current_ability_data:
        return

    self.disabled = not is_usable

    if cooldown_overlay:
        if cooldown_remaining > 0.0 and current_ability_data.cooldown_time > 0.0:
            cooldown_overlay.value = (cooldown_remaining / current_ability_data.cooldown_time) * 100
            cooldown_overlay.visible = true
        else:
            cooldown_overlay.visible = false

    # Example: Greyscale if not usable
    if is_usable:
        self.modulate = Color(1,1,1,1) # Normal color
    else:
        self.modulate = Color(0.5,0.5,0.5,0.7) # Greyed out