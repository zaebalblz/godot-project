extends CharacterBody3D

const FOOTSTEP_STREAMS: Array[AudioStream] = [
	preload("res://assets/audio/sfx/footsteps/grass_step_01.wav"),
	preload("res://assets/audio/sfx/footsteps/grass_step_02.wav"),
	preload("res://assets/audio/sfx/footsteps/grass_step_03.wav"),
	preload("res://assets/audio/sfx/footsteps/grass_step_04.wav"),
]

@export var speed: float = 5.0
@export var walk_speed: float = 2.35
@export var sprint_speed: float = 7.8
@export var ground_acceleration: float = 22.0
@export var ground_deceleration: float = 26.0
@export var sprint_ground_acceleration: float = 34.0
@export var sprint_ground_deceleration: float = 40.0
@export var air_acceleration: float = 8.0
@export var air_deceleration: float = 3.5
@export var air_control: float = 0.55
@export var jump_velocity: float = 4.15
@export var gravity_scale: float = 1.1
@export var fall_gravity_multiplier: float = 1.45
@export var low_jump_gravity_multiplier: float = 1.25
@export var mouse_sensitivity: float = 0.0025
@export var camera_pitch_limit: float = 89.0
@export var footstep_interval: float = 0.43
@export var walk_footstep_interval: float = 0.68
@export var sprint_footstep_interval: float = 0.29
@export var head_bob_frequency: float = 8.0
@export var head_bob_vertical_amount: float = 0.07
@export var head_bob_horizontal_amount: float = 0.04
@export var head_bob_roll_amount: float = 0.018
@export var walk_bob_scale: float = 0.82
@export var sprint_bob_scale: float = 1.22
@export var walk_bob_frequency_scale: float = 0.72
@export var sprint_bob_frequency_scale: float = 1.22
@export var camera_smoothing: float = 14.0
@export var movement_response: float = 10.0
@export var movement_pitch_amount: float = 0.04
@export var movement_roll_amount: float = 0.05
@export var movement_yaw_amount: float = 0.018
@export var movement_side_offset_amount: float = 0.024
@export var movement_forward_offset_amount: float = 0.016
@export var mouse_sway_position_amount: float = 0.004
@export var mouse_sway_rotation_amount: float = 0.02
@export var turn_roll_amount: float = 0.06
@export var turn_yaw_amount: float = 0.014
@export var mouse_sway_return_speed: float = 12.0
@export var mouse_sway_clamp: float = 0.08
@export var landing_bob_amount: float = 0.035
@export var landing_bob_recovery: float = 8.0
@export var footstep_volume_db: float = -8.0
@export var footstep_pitch_randomness: float = 0.04
@export var footstep_volume_randomness_db: float = 1.2

@onready var camera: Camera3D = $Camera3D
@onready var footstep_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

var _camera_pitch: float = 0.0
var _camera_base_position: Vector3
var _footstep_timer: float = 0.0
var _head_bob_time: float = 0.0
var _landing_bob_offset: float = 0.0
var _walk_mode_enabled: bool = false
var _look_input: Vector2 = Vector2.ZERO
var _mouse_sway: Vector2 = Vector2.ZERO
var _movement_ratio: float = 0.0
var _forward_ratio: float = 0.0
var _side_ratio: float = 0.0
var _camera_forward_blend: float = 0.0
var _camera_side_blend: float = 0.0
var _bob_scale: float = 1.0
var _bob_frequency_scale: float = 1.0
var _current_speed: float = 0.0
var _footstep_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_footstep_index: int = -1


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.current = true
	floor_snap_length = 0.2
	_camera_base_position = camera.position
	_current_speed = speed
	_footstep_rng.randomize()
	footstep_player.volume_db = footstep_volume_db


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Z:
		_walk_mode_enabled = not _walk_mode_enabled
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_input += event.screen_relative


func _process(delta: float) -> void:
	_apply_look_input()
	_update_camera_motion(delta)


func _physics_process(delta: float) -> void:
	var was_on_floor := is_on_floor()
	var vertical_velocity_before_move := velocity.y

	if not is_on_floor():
		var gravity_multiplier := gravity_scale

		if velocity.y < 0.0:
			gravity_multiplier *= fall_gravity_multiplier
		elif velocity.y > 0.0 and not Input.is_action_pressed("jump"):
			gravity_multiplier *= low_jump_gravity_multiplier

		velocity += get_gravity() * gravity_multiplier * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var move_dir := (basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var is_walking := _walk_mode_enabled
	var is_sprinting := Input.is_physical_key_pressed(KEY_SHIFT) and not is_walking and input_dir != Vector2.ZERO
	var current_ground_acceleration := ground_acceleration
	var current_ground_deceleration := ground_deceleration

	if is_walking:
		_current_speed = walk_speed
	elif is_sprinting:
		_current_speed = sprint_speed
		current_ground_acceleration = sprint_ground_acceleration
		current_ground_deceleration = sprint_ground_deceleration
	else:
		_current_speed = speed

	if move_dir != Vector3.ZERO:
		var target_velocity_x := move_dir.x * _current_speed
		var target_velocity_z := move_dir.z * _current_speed

		if is_on_floor():
			velocity.x = move_toward(velocity.x, target_velocity_x, current_ground_acceleration * delta)
			velocity.z = move_toward(velocity.z, target_velocity_z, current_ground_acceleration * delta)
		else:
			velocity.x = move_toward(velocity.x, target_velocity_x, air_acceleration * air_control * delta)
			velocity.z = move_toward(velocity.z, target_velocity_z, air_acceleration * air_control * delta)
	else:
		if is_on_floor():
			velocity.x = move_toward(velocity.x, 0.0, current_ground_deceleration * delta)
			velocity.z = move_toward(velocity.z, 0.0, current_ground_deceleration * delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, air_deceleration * delta)
			velocity.z = move_toward(velocity.z, 0.0, air_deceleration * delta)

	move_and_slide()
	_update_camera_state(delta, was_on_floor, vertical_velocity_before_move, is_walking, is_sprinting)
	_update_footsteps(delta, input_dir, is_walking, is_sprinting)


func _apply_look_input() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_look_input = Vector2.ZERO
		return

	if _look_input == Vector2.ZERO:
		return

	var mouse_delta: Vector2 = _look_input
	_look_input = Vector2.ZERO

	rotate_y(-mouse_delta.x * mouse_sensitivity)
	_camera_pitch = clampf(
		_camera_pitch - mouse_delta.y * mouse_sensitivity,
		deg_to_rad(-camera_pitch_limit),
		deg_to_rad(camera_pitch_limit)
	)

	_mouse_sway.x = clampf(
		_mouse_sway.x + mouse_delta.x * mouse_sensitivity * 0.22,
		-mouse_sway_clamp,
		mouse_sway_clamp
	)
	_mouse_sway.y = clampf(
		_mouse_sway.y + mouse_delta.y * mouse_sensitivity * 0.18,
		-mouse_sway_clamp,
		mouse_sway_clamp
	)


func _update_camera_state(
	delta: float,
	was_on_floor: bool,
	vertical_velocity_before_move: float,
	is_walking: bool,
	is_sprinting: bool
) -> void:
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var local_velocity: Vector3 = basis.inverse() * velocity
	var speed_denominator: float = maxf(_current_speed, 0.001)
	var movement_blend: float = minf(movement_response * delta, 1.0)
	var target_forward_blend: float = -Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	).y
	var target_side_blend: float = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	).x

	_movement_ratio = clampf(horizontal_speed / speed_denominator, 0.0, 1.0)
	_forward_ratio = clampf(-local_velocity.z / speed_denominator, -1.0, 1.0)
	_side_ratio = clampf(local_velocity.x / speed_denominator, -1.0, 1.0)
	_camera_forward_blend = lerpf(_camera_forward_blend, target_forward_blend, movement_blend)
	_camera_side_blend = lerpf(_camera_side_blend, target_side_blend, movement_blend)
	_bob_scale = 1.0
	_bob_frequency_scale = 1.0

	if is_walking:
		_bob_scale = walk_bob_scale
		_bob_frequency_scale = walk_bob_frequency_scale
	elif is_sprinting:
		_bob_scale = sprint_bob_scale
		_bob_frequency_scale = sprint_bob_frequency_scale

	if is_on_floor() and _movement_ratio > 0.05:
		_head_bob_time += delta * head_bob_frequency * _bob_frequency_scale * lerpf(0.9, 1.2, _movement_ratio)

	if not was_on_floor and is_on_floor() and vertical_velocity_before_move < -1.0:
		_landing_bob_offset = min(-vertical_velocity_before_move * landing_bob_amount * 0.02, landing_bob_amount)

	_landing_bob_offset = move_toward(_landing_bob_offset, 0.0, landing_bob_recovery * delta)


func _update_camera_motion(delta: float) -> void:
	var target_offset: Vector3 = Vector3.ZERO
	var target_roll: float = 0.0
	var target_yaw: float = 0.0
	var target_pitch_offset: float = 0.0
	var blend: float = minf(camera_smoothing * delta, 1.0)
	var mouse_blend: float = minf(mouse_sway_return_speed * delta, 1.0)

	_mouse_sway = _mouse_sway.lerp(Vector2.ZERO, mouse_blend)

	if is_on_floor() and _movement_ratio > 0.05:
		target_offset.x += cos(_head_bob_time * 0.5) * head_bob_horizontal_amount * _bob_scale * _movement_ratio
		target_offset.y += abs(sin(_head_bob_time)) * head_bob_vertical_amount * _bob_scale * _movement_ratio
		target_roll += sin(_head_bob_time * 0.5) * head_bob_roll_amount * _bob_scale * _movement_ratio

	target_offset.x += _camera_side_blend * movement_side_offset_amount * _movement_ratio
	target_offset.z += -_camera_forward_blend * movement_forward_offset_amount * _movement_ratio
	target_offset.y -= _landing_bob_offset
	target_offset.x -= _mouse_sway.x * mouse_sway_position_amount
	target_offset.y -= abs(_mouse_sway.y) * mouse_sway_position_amount * 0.2

	target_pitch_offset -= _camera_forward_blend * movement_pitch_amount * _movement_ratio
	target_pitch_offset -= _landing_bob_offset * 0.35
	target_pitch_offset += _mouse_sway.y * mouse_sway_rotation_amount * 0.45

	target_roll -= _camera_side_blend * movement_roll_amount * _movement_ratio
	target_roll += -_mouse_sway.x * turn_roll_amount
	target_yaw -= _camera_side_blend * movement_yaw_amount * _movement_ratio
	target_yaw += -_mouse_sway.x * turn_yaw_amount

	camera.position = camera.position.lerp(_camera_base_position + target_offset, blend)
	camera.rotation.x = lerpf(camera.rotation.x, _camera_pitch + target_pitch_offset, blend)
	camera.rotation.y = lerpf(camera.rotation.y, target_yaw, blend)
	camera.rotation.z = lerpf(camera.rotation.z, target_roll, blend)


func _update_footsteps(delta: float, input_dir: Vector2, is_walking: bool, is_sprinting: bool) -> void:
	if FOOTSTEP_STREAMS.is_empty():
		return

	if not is_on_floor() or input_dir == Vector2.ZERO:
		_footstep_timer = 0.0
		return

	var current_footstep_interval := footstep_interval
	var footstep_pitch := 1.0

	if is_walking:
		current_footstep_interval = walk_footstep_interval
		footstep_pitch = 0.92
	elif is_sprinting:
		current_footstep_interval = sprint_footstep_interval
		footstep_pitch = 1.08

	footstep_player.pitch_scale = footstep_pitch

	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_play_footstep(footstep_pitch)
		_footstep_timer = current_footstep_interval


func _play_footstep(base_pitch: float) -> void:
	var stream_index: int = _footstep_rng.randi_range(0, FOOTSTEP_STREAMS.size() - 1)

	if FOOTSTEP_STREAMS.size() > 1 and stream_index == _last_footstep_index:
		stream_index = (stream_index + 1) % FOOTSTEP_STREAMS.size()

	_last_footstep_index = stream_index
	footstep_player.stream = FOOTSTEP_STREAMS[stream_index]
	footstep_player.pitch_scale = base_pitch + _footstep_rng.randf_range(-footstep_pitch_randomness, footstep_pitch_randomness)
	footstep_player.volume_db = footstep_volume_db + _footstep_rng.randf_range(-footstep_volume_randomness_db, footstep_volume_randomness_db)
	footstep_player.play()
