extends Node3D

signal map_camera_controller_mouse_position_signal(ray_from: Vector3, ray_to: Vector3)

@export_group("move")
## moving the camera in two asix (horizontal plane) parallel to the map, usually by WASD in keyboard
@export var allow_move: bool = true
## action name in input map for move forward
@export var input_forward: StringName
## action name in input map for move backward
@export var input_backward: StringName
## action name in input map for move left
@export var input_left: StringName
## action name in input map for move right
@export var input_right: StringName
## speed move
@export_range (0, 100, 0.5) var speed_move: float = 20

@export_group("zoom")
## camera zoom in one asix (in and out), usually by mouse scroll wheel
@export var allow_zoom: bool = true
## action name in input map for zoom in
@export var input_zoom_in: StringName
## action name in input map for  zoom out
@export var input_zoom_out: StringName
## if true, lens zoom to mouse cursor, else - to center screen
@export var to_cursor_zoom: bool = true
## minimum distance to map
@export_range (0, 1000, 0.5) var min_zoom: float = 3
## maximum distance from map
@export_range (0, 1000, 0.5) var max_zoom: float = 20
## speed zoom
@export_range (0, 1000, 0.5) var speed_zoom: float = 20
## inertia 
@export_range (0, 1, 0.05) var fade_zoom: float = 0.8

@export_group("rotate")
## rotate camera in two asix by mouse move, usually by middle mouse button
@export var allow_rotate: bool = true
## action name in input map for rotate
@export var input_rotate: StringName
## min elevator in rotate 
@export_range (0, 90) var angle_rotate_min: int = 10 
## max elevator in rotate 
@export_range (0, 90) var angle_rotate_max: int = 80
## speed rotate
@export_range (0, 100, 0.5) var speed_rotate: float = 20

@export_group("pan")
## moving the camera in two asix (horizontal plane) parallel to the map by mouse
@export var allow_pan: bool = true
## action name in input map for pan
@export var input_pan: StringName
## inverted asix y between mouse move over map 
@export var inverted_y_pan: bool = false
## speed pan
@export_range (0, 100, 1) var speed_pan: int = 2

@export_group("mouse position on terrain")
## send signal "map_camera_controller_mouse_position_changed" with ray from camera to mouse cursor
@export var allow_ray_to_terrain: bool = false
## ray length
@export var length_ray_to_terrain: int = 1000

const RAY_LENGTH = 1000
const GROUND_PLANE = Plane(Vector3.UP, 0)

@onready var controller = $"."
@onready var lens = $Elevator/Lens
@onready var elevator = $Elevator

var zoom_direction = 0
var can_rotate = false
var is_in_pan_mode = false
var last_mouse_position = Vector2()
var prev_ray_to_terrain = Vector3()
var prev_ray_from_terrain = Vector3()

func set_rotate(x: int):
	elevator.rotation_degrees.x = -1 * abs(x)

func _process(delta: float) -> void:
	if allow_move && !is_in_pan_mode: _move(delta)
	if allow_rotate && can_rotate: _rotate(delta)
	if allow_zoom && zoom_direction != 0: _zoom(delta)
	if allow_pan && is_in_pan_mode:	_pan(delta)

func _input(event: InputEvent) -> void:
	if allow_ray_to_terrain && event is InputEventMouseMotion:
		var mouse_position = (event as InputEventMouseMotion).position
		var ray_from = lens.project_ray_origin(mouse_position)
		var ray_to = ray_from + lens.project_ray_normal(mouse_position) * length_ray_to_terrain
		if ray_from != null && ray_to != null && (ray_from != prev_ray_from_terrain || ray_to != prev_ray_to_terrain):
			prev_ray_from_terrain = ray_from
			prev_ray_to_terrain = ray_to
			map_camera_controller_mouse_position_signal.emit(ray_from,ray_to)
	
	if !input_zoom_in.is_empty() && event.is_action_pressed(input_zoom_in):
		zoom_direction = -1
	if !input_zoom_out.is_empty() && event.is_action_pressed(input_zoom_out):
		zoom_direction = 1

	if !input_rotate.is_empty(): 
		if event.is_action_pressed(input_rotate):
			can_rotate = true
			last_mouse_position = get_viewport().get_mouse_position()
		if event.is_action_released(input_rotate):	
			can_rotate = false
		
	if !input_pan.is_empty():	
		if event.is_action_pressed(input_pan):
			is_in_pan_mode = true
			last_mouse_position = get_viewport().get_mouse_position()
		if event.is_action_released(input_pan):
			is_in_pan_mode = false


func _move(delta: float) -> void:
	if !input_forward.is_empty() && Input.is_action_pressed(input_forward):
		position += (-transform.basis.z.normalized() * delta * speed_move)
	elif !input_backward.is_empty() && Input.is_action_pressed(input_backward):
		position += (transform.basis.z.normalized() * delta * speed_move)
	elif !input_left.is_empty() && Input.is_action_pressed(input_left):
		position += (-transform.basis.x.normalized() * delta * speed_move)
	elif !input_right.is_empty() && Input.is_action_pressed(input_right):
		position += (transform.basis.x.normalized() * delta * speed_move)


func _rotate(delta: float) -> void:
	var mouse_speed = _get_mouse_speed()
	rotation_degrees.y += speed_rotate * mouse_speed.x * delta
	elevator.rotation_degrees.x = clamp(
		elevator.rotation_degrees.x + ((1 if inverted_y_pan else -1) * (speed_rotate * mouse_speed.y * delta)),
		-angle_rotate_max,
		-angle_rotate_min
	)

func _zoom(delta: float) -> void:
	var rotate_angle_rad = deg_to_rad(abs(elevator.rotation_degrees.x))
	var base_zoom = zoom_direction * speed_zoom * delta
	var new_global_position_y = controller.global_position.y + (base_zoom * sin(rotate_angle_rad))

	if (zoom_direction < 0 && min_zoom > new_global_position_y): return
	if (zoom_direction > 0 && new_global_position_y > max_zoom): return

	var new_global_position_z = controller.global_position.z + (base_zoom * cos(rotate_angle_rad))

	controller.global_position.y = new_global_position_y
	controller.global_position.z = new_global_position_z
	
	zoom_direction *= fade_zoom
	if abs(zoom_direction) < 0.0001: zoom_direction = 0
	
	if !to_cursor_zoom: return 
	var pointing_at = _get_ground_position()
	if pointing_at == null: return
	_realign_lens(pointing_at)


func _pan(delta: float) -> void:
	var mouse_speed = _get_mouse_speed()
	var velocity = (global_transform.basis.z * mouse_speed.y + global_transform.basis.x * mouse_speed.x) * delta * speed_pan
	position -= velocity

##############################
# HELPERS
##############################

func _get_mouse_speed() -> Vector2:
	var current_mouse_pos = get_viewport().get_mouse_position()
	var mouse_speed = current_mouse_pos - last_mouse_position
	last_mouse_position = current_mouse_pos
	return mouse_speed

func _realign_lens(point: Vector3) -> void:
	var new_position = _get_ground_position()
	if new_position == null: return
	position += point - new_position

func _get_ground_position():
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_from = lens.project_ray_origin(mouse_pos)
	var ray_to = ray_from + lens.project_ray_normal(mouse_pos) * RAY_LENGTH
	return GROUND_PLANE.intersects_ray(ray_from, ray_to)
