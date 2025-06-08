extends Node

const BattleUIScene = preload("res://ui/BattleUI/main_battle_ui.tscn")

var battle_ui_instance = null

func show_battle_ui():
	if battle_ui_instance == null:
		battle_ui_instance = BattleUIScene.instantiate()
		
		get_tree().root.add_child(battle_ui_instance)
		print("UIManager: BattleUI created and added to the scene.")