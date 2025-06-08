extends Resource

class_name Stats

signal health_changed(current_health, max_health)
signal ap_changed(current_ap, max_ap)
signal sp_changed(current_sp, max_sp)
signal died()

@export var name: String = "Unknown"
@export var portrait_texture: Texture2D
@export var level: int = 1
@export var max_health: int = 100
var _current_health: int: 
	set(value):
		var previous_health = _current_health
		_current_health = clamp(value, 0, max_health)
		if _current_health != previous_health:
			health_changed.emit(_current_health, max_health)
			if _current_health <= 0:
				died.emit()

@export var max_action_points: int = 6
var _current_ap: 
	get: return _current_ap
	set(value):
		var previous_ap = _current_ap
		_current_ap = clamp(value, 0, max_action_points)
		if _current_ap != previous_ap:
			ap_changed.emit(_current_ap, max_action_points)

@export var max_step_points: int = 6
var _current_sp: 
	get: return _current_sp
	set(value):
		var previous_sp = _current_sp
		_current_sp = clamp(value, 0, max_step_points)
		if _current_sp != previous_sp:
			sp_changed.emit(_current_sp, max_step_points)

@export var attack_power: int = 10
@export var defense: int = 5
@export var magic_power: int = 15
@export var magic_defense: int = 3
@export var initiative: int = 10


func initialize_stats():
	_current_health = max_health
	_current_ap = max_action_points
	_current_sp = max_step_points 

func take_damage(damage_amount: int):
	var effective_damage = damage_amount
	if effective_damage < 0:
		effective_damage = 1
	self.current_health -= effective_damage

func is_alive() -> bool:
	return _current_health > 0

# --- AP Methods ---
func get_current_ap() -> int:
	return _current_ap

func spend_ap(amount: int) -> bool:
	if _current_ap >= amount:
		self.current_ap -= amount
		return true
	return false

func replenish_ap_to_max():
	self.current_ap = max_action_points

# --- SP Methods ---
func get_current_sp() -> int:
	return _current_sp

func spend_sp(amount: int) -> bool:
	if _current_sp >= amount:
		self._current_sp -= amount # This will trigger the sp_changed signal via the setter
		return true
	return false

func replenish_sp_to_max():
	self._current_sp = max_step_points # This will trigger the sp_changed signal