extends Camera2D

@export var camera_speed: float = 300.0 # Speed of camera movement in pixels per second


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var input_direction = Vector2.ZERO

	# Check for WASD input (uses default Godot input actions)
	if Input.is_action_pressed("ui_up"): # W key / Up Arrow
		input_direction.y -= 1
	if Input.is_action_pressed("ui_down"): # S key / Down Arrow
		input_direction.y += 1
	if Input.is_action_pressed("ui_left"): # A key / Left Arrow
		input_direction.x -= 1
	if Input.is_action_pressed("ui_right"): # D key / Right Arrow
		input_direction.x += 1

	# Normalize the direction vector to ensure consistent speed diagonally
	if input_direction != Vector2.ZERO:
		input_direction = input_direction.normalized()
	
	# Update the camera's position
	global_position += input_direction * camera_speed * delta
