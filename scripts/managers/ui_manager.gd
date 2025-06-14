extends Node

signal stats_changed()
signal health_changed()
signal steps_changed()

const BattleUIScene = preload("res://ui/BattleUI/main_battle_ui.tscn")

var battle_ui_instance = null

func _ready():
	await get_tree().process_frame
	var player = PartyManager.get_selected_character()

	if player:
		player.stats.ap_changed.connect(update_ui)
		player.stats.sp_changed.connect(update_sp)
		player.stats.health_changed.connect(update_health_bar)

func show_battle_ui():
	if battle_ui_instance == null:
		battle_ui_instance = BattleUIScene.instantiate()
		
		get_tree().root.add_child(battle_ui_instance)
		emit_signal("stats_changed")
		print("UIManager: BattleUI created and added to the scene.")

func update_health_bar(_health):
	emit_signal("health_changed")

func update_ui(_ap):
	emit_signal("stats_changed")	

func update_sp(_sp):
	emit_signal("steps_changed")