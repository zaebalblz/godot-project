extends CharacterBody3D

const CORPSE_VISUAL_SCRIPT := preload("res://scenes/enemies/pale_watcher_corpse.gd")
const FOOTSTEP_STREAMS: Array[AudioStream] = [
	preload("res://assets/audio/sfx/enemies/pale_watcher/step_01.wav"),
	preload("res://assets/audio/sfx/enemies/pale_watcher/step_02.wav"),
	preload("res://assets/audio/sfx/enemies/pale_watcher/step_03.wav"),
	preload("res://assets/audio/sfx/enemies/pale_watcher/step_04.wav"),
]

@export var move_speed: float = 2.2
@export var max_health: float = 3.0
@export var wounded_speed_multiplier: float = 0.7
@export var critical_speed_multiplier: float = 0.4
@export var acceleration: float = 9.0
@export var deceleration: float = 11.0
@export var gravity_scale: float = 1.1
@export var detection_range: float = 48.0
@export var stop_distance: float = 1.6
@export var slowdown_distance: float = 6.0
@export var turn_speed: float = 5.0
@export var walk_bob_amount: float = 0.012
@export var walk_sway_amount: float = 0.004
@export var walk_bob_frequency: float = 4.8
@export var footstep_base_interval: float = 1.08
@export var footstep_fast_interval: float = 0.46
@export var footstep_volume_db: float = -11.0
@export var footstep_pitch_randomness: float = 0.04
@export var death_flatten_frame: int = 4
@export var corpse_pose_offset: Vector3 = Vector3(0.0, 0.03, -0.82)

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var footstep_player: AudioStreamPlayer3D = $FootstepPlayer3D

var _target: Node3D
var _footstep_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_footstep_index: int = -1
var _footstep_timer: float = 0.0
var _walk_cycle: float = 0.0
var _sprite_base_position: Vector3
var _sprite_base_rotation: Vector3
var _sprite_base_billboard: int
var _is_dead: bool = false
var _health: float = 0.0


func _ready() -> void:
	_sprite_base_position = sprite.position
	_sprite_base_rotation = sprite.rotation_degrees
	_sprite_base_billboard = sprite.billboard
	_health = max_health
	_footstep_rng.randomize()
	footstep_player.volume_db = footstep_volume_db
	sprite.play("idle")


func _physics_process(delta: float) -> void:
	if _is_dead:
		velocity = Vector3.ZERO
		return

	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta

	_resolve_target()

	var horizontal_velocity := Vector2(velocity.x, velocity.z)
	var move_direction := Vector3.ZERO
	var desired_speed := 0.0

	if _target != null and is_instance_valid(_target):
		var to_target := _target.global_position - global_position
		var horizontal_to_target := Vector3(to_target.x, 0.0, to_target.z)
		var distance_to_target := horizontal_to_target.length()
		var current_move_speed := move_speed * _get_speed_multiplier()

		if distance_to_target <= detection_range and distance_to_target > stop_distance:
			move_direction = horizontal_to_target / distance_to_target
			desired_speed = current_move_speed

			if distance_to_target < slowdown_distance:
				var slowdown_ratio := clampf(
					(distance_to_target - stop_distance) / maxf(slowdown_distance - stop_distance, 0.001),
					0.08,
					1.0
				)
				desired_speed *= slowdown_ratio

			var desired_rotation := atan2(move_direction.x, move_direction.z)
			rotation.y = lerp_angle(rotation.y, desired_rotation, minf(turn_speed * delta, 1.0))

	if move_direction != Vector3.ZERO:
		horizontal_velocity.x = move_toward(horizontal_velocity.x, move_direction.x * desired_speed, acceleration * delta)
		horizontal_velocity.y = move_toward(horizontal_velocity.y, move_direction.z * desired_speed, acceleration * delta)
	else:
		horizontal_velocity.x = move_toward(horizontal_velocity.x, 0.0, deceleration * delta)
		horizontal_velocity.y = move_toward(horizontal_velocity.y, 0.0, deceleration * delta)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.y
	var horizontal_speed := horizontal_velocity.length()
	_update_animation(horizontal_speed)
	_update_walk_presentation(delta, horizontal_speed)
	_update_footsteps(delta, horizontal_speed)

	move_and_slide()


func _resolve_target() -> void:
	if _target != null and is_instance_valid(_target):
		return

	_target = get_tree().get_first_node_in_group("player") as Node3D


func _update_animation(horizontal_speed: float) -> void:
	var target_animation := _get_idle_animation_name()

	if horizontal_speed > 0.08:
		target_animation = _get_walk_animation_name()

	if sprite.animation != target_animation:
		sprite.play(target_animation)

	var speed_ratio := clampf(horizontal_speed / maxf(move_speed, 0.001), 0.0, 1.0)
	sprite.speed_scale = lerpf(0.55, 1.0, speed_ratio)


func _update_walk_presentation(delta: float, horizontal_speed: float) -> void:
	var speed_ratio: float = clampf(horizontal_speed / maxf(move_speed, 0.001), 0.0, 1.0)

	if is_on_floor() and speed_ratio > 0.05:
		_walk_cycle += delta * walk_bob_frequency * lerpf(0.75, 1.25, speed_ratio)

	var bob: float = absf(sin(_walk_cycle)) * float(walk_bob_amount) * speed_ratio
	var sway: float = sin(_walk_cycle * 0.5) * float(walk_sway_amount) * speed_ratio
	sprite.position = _sprite_base_position + Vector3(sway, bob, 0.0)


func _update_footsteps(delta: float, horizontal_speed: float) -> void:
	if FOOTSTEP_STREAMS.is_empty():
		return

	if not is_on_floor() or horizontal_speed <= 0.08:
		_footstep_timer = 0.0
		return

	var speed_ratio := clampf(horizontal_speed / maxf(move_speed, 0.001), 0.0, 1.0)
	_footstep_timer -= delta

	if _footstep_timer > 0.0:
		return

	_play_footstep(speed_ratio)
	_footstep_timer = lerpf(footstep_base_interval, footstep_fast_interval, speed_ratio * speed_ratio)


func _play_footstep(speed_ratio: float) -> void:
	var stream_index: int = _footstep_rng.randi_range(0, FOOTSTEP_STREAMS.size() - 1)

	if FOOTSTEP_STREAMS.size() > 1 and stream_index == _last_footstep_index:
		stream_index = (stream_index + 1) % FOOTSTEP_STREAMS.size()

	_last_footstep_index = stream_index
	footstep_player.stream = FOOTSTEP_STREAMS[stream_index]
	footstep_player.pitch_scale = lerpf(0.84, 1.0, speed_ratio) + _footstep_rng.randf_range(-footstep_pitch_randomness, footstep_pitch_randomness)
	footstep_player.volume_db = lerpf(footstep_volume_db - 3.0, footstep_volume_db, speed_ratio)
	footstep_player.play()


func apply_hit(_damage: float, _hit_position: Vector3 = Vector3.ZERO) -> void:
	if _is_dead:
		return

	_health = maxf(_health - maxf(_damage, 0.0), 0.0)

	if _health <= 0.0:
		_start_death()


func take_damage(damage: float) -> void:
	apply_hit(damage)


func hit(damage: float) -> void:
	apply_hit(damage)


func apply_damage(damage: float) -> void:
	apply_hit(damage)


func _get_speed_multiplier() -> float:
	if _health <= 1.0:
		return critical_speed_multiplier

	if _health <= 2.0:
		return wounded_speed_multiplier

	return 1.0


func _get_idle_animation_name() -> StringName:
	if _health <= 1.0:
		return &"critical_idle"

	if _health <= 2.0:
		return &"wounded_idle"

	return &"idle"


func _get_walk_animation_name() -> StringName:
	if _health <= 1.0:
		return &"critical_walk"

	if _health <= 2.0:
		return &"wounded_walk"

	return &"walk"


func _start_death() -> void:
	if _is_dead:
		return

	_is_dead = true
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	var parent := get_parent()
	if parent == null:
		queue_free()
		return

	var corpse := CORPSE_VISUAL_SCRIPT.new() as AnimatedSprite3D
	if corpse == null:
		queue_free()
		return

	corpse.sprite_frames = sprite.sprite_frames
	corpse.pixel_size = sprite.pixel_size
	corpse.texture_filter = sprite.texture_filter
	corpse.billboard = _sprite_base_billboard
	corpse.death_flatten_frame = death_flatten_frame
	corpse.corpse_pose_delta = corpse_pose_offset - _sprite_base_position
	corpse.corpse_yaw = global_rotation.y
	parent.add_child(corpse)
	corpse.global_position = sprite.global_position
	corpse.global_rotation = Vector3(0.0, global_rotation.y, 0.0)

	footstep_player.stop()
	visible = false
	set_process(false)
	set_physics_process(false)
	if is_instance_valid(collision_shape):
		remove_child(collision_shape)
		collision_shape.queue_free()
	queue_free()
