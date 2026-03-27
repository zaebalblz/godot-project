extends AnimatedSprite3D

var death_flatten_frame: int = 4
var corpse_pose_delta: Vector3 = Vector3.ZERO
var death_animation: StringName = &"death"
var corpse_yaw: float = 0.0
var corpse_ground_clearance: float = 0.045
var corpse_floor_tilt_degrees: float = 87.5

var _is_flattened: bool = false


func _ready() -> void:
	animation_finished.connect(_on_animation_finished)
	frame_changed.connect(_on_frame_changed)
	play(death_animation)
	set_frame_and_progress(0, 0.0)


func _on_frame_changed() -> void:
	if animation != death_animation or _is_flattened:
		return

	if frame < death_flatten_frame:
		return

	_is_flattened = true
	billboard = BaseMaterial3D.BILLBOARD_DISABLED
	rotation = Vector3(-deg_to_rad(corpse_floor_tilt_degrees), corpse_yaw, 0.0)
	position += corpse_pose_delta.rotated(Vector3.UP, corpse_yaw)
	position.y += corpse_ground_clearance


func _on_animation_finished() -> void:
	if animation != death_animation:
		return

	var last_frame := sprite_frames.get_frame_count(death_animation) - 1
	if last_frame < 0:
		return

	_on_frame_changed()
	stop()
	frame = last_frame
