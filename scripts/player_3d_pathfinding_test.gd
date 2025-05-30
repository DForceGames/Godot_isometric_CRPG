extends CharacterBody3D # Or Node3D, depending on how you want to move it

# Example basic structure for 3D pathfinding tests

# NavigationAgent3D node - assign this in the editor
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

@export var movement_speed: float = 4.0

func _ready():
	# Ensure NavigationAgent3D is valid
	if not navigation_agent:
		printerr("NavigationAgent3D node not found or not assigned. Please assign it in the editor.")
		set_physics_process(false)
		return
	
	# Call this to make sure the agent is aware of the latest navigation mesh
	await get_tree().physics_frame 
	# Or if you update navmesh at runtime:
	# navigation_agent.get_navigation_map().map_force_update()


func _physics_process(delta):
	if not navigation_agent or navigation_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var current_agent_position: Vector3 = global_transform.origin
	var next_path_position: Vector3 = navigation_agent.get_next_path_position()

	var new_velocity: Vector3 = (next_path_position - current_agent_position).normalized() * movement_speed
	
	# Optional: Add some smoothing or more advanced movement logic here
	# For example, using PID controller or lerping velocity for smoother turns.

	velocity = new_velocity
	move_and_slide()

# Example function to set a target for the agent
func set_target_position(target_pos: Vector3):
	if navigation_agent:
		navigation_agent.target_position = target_pos
		print("Navigation target set to: ", target_pos)
	else:
		printerr("Cannot set target: NavigationAgent3D is not ready.")

# Example of how you might get input to set a target (e.g., mouse click)
# This would require a way to raycast from camera to 3D world position
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		# This is a placeholder for 3D raycasting logic
		# You'll need to implement raycasting from your camera to get a 3D world point
		var camera = get_viewport().get_camera_3d()
		if camera:
			var mouse_pos = event.position
			var ray_origin = camera.project_ray_origin(mouse_pos)
			var ray_end = ray_origin + camera.project_ray_normal(mouse_pos) * 1000 # Ray length
			
			var space_state = get_world_3d().direct_space_state
			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
			# query.collide_with_areas = true # Optional: if you want to click on areas
			# query.collide_with_bodies = true # Usually true for navigation
			
			var result = space_state.intersect_ray(query)
			
			if result:
				print("Clicked at 3D position: ", result.position)
				set_target_position(result.position)
			else:
				print("No 3D point found under mouse click.")
		else:
			printerr("No 3D camera found to perform raycast.")

# --- For AStar3D (alternative or complementary to NavigationServer3D) ---
# var astar3d = AStar3D.new()
# var point_id_counter = 0
# var points = {} # Dictionary to map Vector3 to point ID

# func add_astar_point(position: Vector3):
# 	if not points.has(position):
# 		astar3d.add_point(point_id_counter, position)
# 		points[position] = point_id_counter
# 		point_id_counter += 1
# 	return points[position]

# func connect_astar_points(pos1: Vector3, pos2: Vector3, bidirectional: bool = true):
# 	var id1 = add_astar_point(pos1)
# 	var id2 = add_astar_point(pos2)
# 	astar3d.connect_points(id1, id2, bidirectional)

# func find_astar_path(start_pos: Vector3, end_pos: Vector3):
# 	var start_id = points.get(start_pos, -1)
# 	var end_id = points.get(end_pos, -1)
	
# 	if start_id == -1 or end_id == -1:
# 		printerr("AStar3D: Start or end point not found.")
# 		return []
		
# 	var path_points: PackedVector3Array = astar3d.get_point_path(start_id, end_id)
# 	print("AStar3D path: ", path_points)
# 	return path_points

func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		# This ensures that the NavigationAgent3D node is available.
		# If you add it dynamically, you might need to adjust.
		if not is_node_ready(): # Wait until node is ready
			await ready 
		
		navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
		if not navigation_agent:
			printerr("Failed to find NavigationAgent3D child node. Ensure it exists and is named correctly.")
			set_physics_process(false)
		else:
			# It's good practice to wait for the navigation map to be ready,
			# especially if it's generated at runtime or in a separate thread.
			# This signal is emitted when the map changes, e.g., after baking or updates.
			navigation_agent.navigation_map_changed.connect(_on_navigation_map_changed)
			# Initial check in case map is already ready
			if navigation_agent.get_navigation_map():
				_on_navigation_map_changed()


func _on_navigation_map_changed():
	# This function is called when the navigation map is ready or changes.
	# You can put logic here that depends on the navigation map being available.
	print("Navigation map is ready or has changed.")
	# For example, you might want to set an initial target or enable movement.
	# set_target_position(some_initial_target_vector3) # If you have one
	pass
