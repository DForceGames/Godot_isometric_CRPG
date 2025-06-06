# ui/BattleUI/battle_ui.gd
extends CanvasLayer

# References to child UI elements
@onready var action_bar = $ActionBar
@onready var turn_order_display = $TurnOrderDisplay
@onready var health_displays = $HealthDisplayContainer
# Add more UI element references as needed

# Animation players or tweens for transitions
@onready var anim_player = $AnimationPlayer

func _ready():
    # Start hidden
    visible = false
    
    # Connect to the CombatManager signals
    var combat_manager = get_node("/root/CombatManager")
    if combat_manager:
        combat_manager.combat_started.connect(_on_combat_started)
        combat_manager.combat_ended.connect(_on_combat_ended)
        combat_manager.turn_started.connect(_on_turn_started)
        # Connect other relevant signals
    else:
        printerr("BattleUI: CombatManager not found")

func _on_combat_started():
    # Show and animate the UI
    visible = true
    if anim_player and anim_player.has_animation("show"):
        anim_player.play("show")
    else:
        # Simple fade-in without animation player
        self.modulate.a = 0
        var tween = create_tween()
        tween.tween_property(self, "modulate:a", 1.0, 0.3)

func _on_combat_ended(_result):
    # Hide the UI when combat ends
    if anim_player and anim_player.has_animation("hide"):
        anim_player.play("hide")
        await anim_player.animation_finished
        visible = false
    else:
        # Simple fade-out without animation player
        var tween = create_tween()
        tween.tween_property(self, "modulate:a", 0.0, 0.3)
        await tween.finished
        visible = false

func _on_turn_started(character_node):
    # Update UI to show whose turn it is
    # Highlight active character in the turn order, update available actions, etc.
    pass

func update_health_displays():
    # Refresh health bars based on current character stats
    pass

# Add more UI update methods as needed