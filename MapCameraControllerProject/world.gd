extends Node3D

@onready var pointer = $env/pointer

func _on_map_camera_controller_map_camera_controller_mouse_position_signal(ray_from: Vector3, ray_to: Vector3):
	var space_state = get_world_3d().direct_space_state
	var params = PhysicsRayQueryParameters3D.new()
	params.from = ray_from
	params.to = ray_to
	var intersect = space_state.intersect_ray(params)
	if intersect == null || !intersect.has("position"): return
	pointer.position.x = intersect.position.x
	pointer.position.z = intersect.position.z
